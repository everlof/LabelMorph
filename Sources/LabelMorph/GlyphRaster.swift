import AppKit
import CoreText
import QuartzCore

/// Rasterises one glyph the way AppKit rasterises a whole line, so a label built
/// from one layer per character is as crisp as an `NSTextField`.
///
/// On a 2x display none of this is visible. On a 1x display — an external monitor
/// at its native resolution, where one point is one pixel — `CATextLayer` renders
/// text that is measurably lighter and softer than the same string drawn by
/// AppKit. Three things are load-bearing here, and each was arrived at by
/// measuring the alternative at 13pt/1x (ink = mean coverage, edge = mean
/// absolute horizontal gradient; higher is darker and crisper respectively):
///
/// | | ink | edge |
/// |---|---|---|
/// | one AppKit-drawn line, smoothing on | 0.1397 | 34.21 |
/// | one `CATextLayer` per glyph | 0.1187 | 27.73 |
/// | this file | 0.1397 | 34.21 |
///
/// 1. **The glyph is drawn against an opaque background with font smoothing on.**
///    Smoothing is the stem-darkening pass macOS applies below 2x, and it does
///    not run in a transparent context — which is all `CATextLayer` can offer,
///    since it owns its own backing store. Worth the whole of the ink column.
///
/// 2. **The smoothed pixels are inverted back into a coverage mask.** Handing the
///    opaque tiles straight to the layers does not work and is worth stating,
///    because it looks obviously right: glyphs overlap by their side bearings, so
///    each opaque tile paints its background over its neighbour's overhang. That
///    version measured *lighter* (0.0984) than the `CATextLayer` it replaced.
///    Inverting to coverage keeps the dilation and restores transparency.
///
/// 3. **The sub-pixel offset is baked into the raster** and the layer sits on a
///    whole device pixel. Rounding the *layer* rather than the *advance* keeps
///    Core Text's spacing while never handing the compositor a fractional origin
///    to resample — that is the whole of the edge column (a fractional origin
///    measures 29.87 even with the smoothing above).
///
/// The size of that last bake is not a free choice, and guessing it wrong is
/// silent: Core Graphics quantises horizontal glyph positions to **thirds of a
/// device pixel**, flooring at 1/3 and 2/3. Sweeping a glyph across one pixel in
/// hundredths yields exactly three distinct rasters, grouped [0, 0.33],
/// [0.34, 0.66], [0.67, 0.99]. So three phases reproduce what AppKit draws
/// exactly; four quantises to a grid that is not the one underneath, and lands
/// a third of the glyphs in the wrong bucket while looking entirely reasonable.
///
/// Masks are cached without the ink colour so a live theme switch re-tints rather
/// than re-rasterises, and both caches are keyed on the backing scale so a window
/// dragged between a Retina display and a 1x one re-rasterises rather than
/// resampling what it already had.
enum GlyphRaster {

    /// Room around the typographic box for ink that overhangs it. A glyph's
    /// advance does not bound its ink — italic faces, script faces, and combining
    /// marks all reach outside it, and unlike `CATextLayer` a bitmap is clipped
    /// to its layer's bounds. Any user-chosen family may do this, so the margin
    /// is unconditional.
    static let padding: CGFloat = 3

    // MARK: - Sub-pixel phase

    /// Core Graphics' own horizontal quantum for glyph positions, measured rather
    /// than assumed — see the note above.
    static let phaseCount = 3

    /// The offset, in device pixels, that `bucket` represents.
    static func phase(for bucket: Int) -> CGFloat {
        CGFloat(min(max(bucket, 0), phaseCount - 1)) / CGFloat(phaseCount)
    }

    /// Splits a position in device pixels into the whole pixel the layer sits on
    /// and the phase its raster carries.
    ///
    /// Floor on both halves, because that is what Core Graphics does: an offset
    /// of 0.99 stays on this pixel in the last phase rather than rounding onto
    /// the next one. Rounding to nearest here measured further from AppKit's own
    /// rendering, not closer.
    static func quantise(devicePosition: CGFloat) -> (origin: CGFloat, bucket: Int) {
        let whole = devicePosition.rounded(.down)
        let bucket = Int((devicePosition - whole) * CGFloat(phaseCount))
        return (whole, min(bucket, phaseCount - 1))
    }

    // MARK: - Rasterising

    /// A tinted tile for one glyph, or `nil` when the glyph has no ink.
    ///
    /// - Parameters:
    ///   - size: the tile in points. Must land on whole device pixels; the caller
    ///     owns that because it also owns the layer frame the tile has to match.
    ///   - baseline: the glyph's baseline measured up from the tile's bottom edge.
    ///   - inset: how far in from the tile's left edge the glyph's origin sits,
    ///     before the sub-pixel phase is added.
    static func tile(character: String,
                     font: NSFont,
                     ink: CGColor,
                     background: CGColor,
                     phaseBucket: Int,
                     scale: CGFloat,
                     size: CGSize,
                     baseline: CGFloat,
                     inset: CGFloat) -> CGImage? {
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0, !character.isEmpty else { return nil }

        let onLight = isLight(background, relativeTo: ink)
        let maskKey = MaskKey(character: character,
                              fontName: font.fontName,
                              pointSize: font.pointSize,
                              phaseBucket: min(max(phaseBucket, 0), phaseCount - 1),
                              scale: scale,
                              pixelWidth: pixelWidth,
                              pixelHeight: pixelHeight,
                              baseline: baseline,
                              inset: inset,
                              onLightBackground: onLight)

        lock.lock()
        defer { lock.unlock() }

        let imageKey = ImageKey(mask: maskKey, ink: packed(ink))
        if let cached = imageCache[imageKey] { return cached }

        let mask: Mask
        if let cached = maskCache[maskKey] {
            mask = cached
        } else {
            guard let rendered = renderMask(maskKey, font: font) else { return nil }
            if maskCache.count >= maxMasks { maskCache.removeAll(keepingCapacity: true) }
            maskCache[maskKey] = rendered
            mask = rendered
        }

        guard let image = tint(mask, with: ink, scale: scale) else { return nil }
        if imageCache.count >= maxImages { imageCache.removeAll(keepingCapacity: true) }
        imageCache[imageKey] = image
        return image
    }

    /// Drops every cached tile. Rasterisation depends on the display's backing
    /// scale, so this is what a move between screens is entitled to.
    static func flush() {
        lock.lock()
        defer { lock.unlock() }
        maskCache.removeAll()
        imageCache.removeAll()
    }

    // MARK: - Internals

    /// Coverage per pixel, 0 where the tile is bare and 255 under solid ink.
    private struct Mask {
        let pixelWidth: Int
        let pixelHeight: Int
        let coverage: [UInt8]
    }

    private struct MaskKey: Hashable {
        let character: String
        let fontName: String
        let pointSize: CGFloat
        let phaseBucket: Int
        let scale: CGFloat
        let pixelWidth: Int
        let pixelHeight: Int
        let baseline: CGFloat
        let inset: CGFloat
        /// Smoothing dilates dark ink on a light ground and thins light ink on a
        /// dark one, so the two polarities are different rasters — but only the
        /// two, which is why the mask is cached without the colour itself.
        let onLightBackground: Bool
    }

    private struct ImageKey: Hashable {
        let mask: MaskKey
        let ink: UInt32
    }

    private static let lock = NSLock()
    private static var maskCache: [MaskKey: Mask] = [:]
    private static var imageCache: [ImageKey: CGImage] = [:]

    /// Generous enough that a sidebar never thrashes, small enough that the
    /// crude evict-everything policy below stays affordable. A tile is on the
    /// order of a kilobyte.
    private static let maxMasks = 4096
    private static let maxImages = 4096

    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue

    /// Draws the glyph opaque — black on white, or white on black when the ink is
    /// the lighter of the two — and reads the result back as coverage.
    private static func renderMask(_ key: MaskKey, font: NSFont) -> Mask? {
        let pixels = key.pixelWidth * key.pixelHeight
        guard let context = CGContext(data: nil,
                                      width: key.pixelWidth, height: key.pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: key.pixelWidth * 4,
                                      space: srgb, bitmapInfo: bitmapInfo) else { return nil }

        context.scaleBy(x: key.scale, y: key.scale)
        let pointSize = CGSize(width: CGFloat(key.pixelWidth) / key.scale,
                               height: CGFloat(key.pixelHeight) / key.scale)
        context.setFillColor(key.onLightBackground ? white : black)
        context.fill(CGRect(origin: .zero, size: pointSize))

        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)

        let attributed = NSAttributedString(string: key.character, attributes: [
            .font: font,
            .ligature: 0,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                key.onLightBackground ? black : white,
        ])
        context.textPosition = CGPoint(x: key.inset + phase(for: key.phaseBucket) / key.scale,
                                       y: key.baseline)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)

        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: pixels * 4)
        var coverage = [UInt8](repeating: 0, count: pixels)
        var isBlank = true
        for index in 0..<pixels {
            // Any colour channel will do: the raster is greyscale by construction.
            let channel = bytes[index * 4 + 1]
            let value = key.onLightBackground ? 255 &- channel : channel
            coverage[index] = value
            if value != 0 { isBlank = false }
        }
        guard !isBlank else { return nil }
        return Mask(pixelWidth: key.pixelWidth, pixelHeight: key.pixelHeight, coverage: coverage)
    }

    /// Premultiplies the ink colour through the mask's coverage.
    private static func tint(_ mask: Mask, with ink: CGColor, scale: CGFloat) -> CGImage? {
        guard let components = sRGBComponents(ink) else { return nil }
        let pixels = mask.pixelWidth * mask.pixelHeight
        guard let context = CGContext(data: nil,
                                      width: mask.pixelWidth, height: mask.pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: mask.pixelWidth * 4,
                                      space: srgb, bitmapInfo: bitmapInfo),
              let data = context.data else { return nil }

        let red = UInt16(clamping: Int(components.red * 255))
        let green = UInt16(clamping: Int(components.green * 255))
        let blue = UInt16(clamping: Int(components.blue * 255))
        let inkAlpha = max(0, min(1, components.alpha))

        let bytes = data.bindMemory(to: UInt8.self, capacity: pixels * 4)
        for index in 0..<pixels {
            let alpha = UInt16(Double(mask.coverage[index]) * inkAlpha)
            bytes[index * 4] = UInt8(alpha)
            bytes[index * 4 + 1] = UInt8(red * alpha / 255)
            bytes[index * 4 + 2] = UInt8(green * alpha / 255)
            bytes[index * 4 + 3] = UInt8(blue * alpha / 255)
        }
        return context.makeImage()
    }

    // MARK: - Colour

    private static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    private static func sRGBComponents(_ color: CGColor)
        -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let converted = color.converted(to: srgb, intent: .defaultIntent, options: nil),
              let parts = converted.components, parts.count >= 3 else { return nil }
        return (parts[0], parts[1], parts[2], converted.alpha)
    }

    private static func luminance(_ color: CGColor) -> CGFloat {
        guard let parts = sRGBComponents(color) else { return 0 }
        return 0.2126 * parts.red + 0.7152 * parts.green + 0.0722 * parts.blue
    }

    /// Whether the ink should be dilated as dark-on-light. A fully transparent
    /// background states no opinion, so the ink decides: light text is being read
    /// on something dark.
    private static func isLight(_ background: CGColor, relativeTo ink: CGColor) -> Bool {
        guard background.alpha > 0.01 else { return luminance(ink) < 0.5 }
        return luminance(background) > luminance(ink)
    }

    private static func packed(_ color: CGColor) -> UInt32 {
        guard let parts = sRGBComponents(color) else { return 0 }
        let red = UInt32(clamping: Int(parts.red * 255))
        let green = UInt32(clamping: Int(parts.green * 255))
        let blue = UInt32(clamping: Int(parts.blue * 255))
        let alpha = UInt32(clamping: Int(parts.alpha * 255))
        return red << 24 | green << 16 | blue << 8 | alpha
    }
}
