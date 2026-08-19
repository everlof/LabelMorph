import AppKit
import CoreText
import XCTest
@testable import LabelMorph

/// The reason `GlyphRaster` exists is a picture, so these assert on one.
///
/// A 1x display — an external monitor at its native resolution — is where the
/// difference between AppKit's own text rendering and a layer-per-glyph label
/// stops being invisible. Nothing in the package's other tests would notice a
/// regression to `CATextLayer`: the characters, the metrics and the truncation
/// would all still be right, and the text would just be grey and soft. So the
/// contract here is stated against AppKit's own rasterisation of the same line.
final class GlyphRasterTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 13, weight: .regular)
    private let text = "Review findings and plan"
    private let size = CGSize(width: 200, height: 20)

    override func setUp() {
        super.setUp()
        GlyphRaster.flush()
    }

    // MARK: - Against AppKit

    func testALineOfTilesRendersWhatAppKitWouldAtOneX() throws {
        let reference = try XCTUnwrap(drawWithAppKit(scale: 1))
        let ours = try XCTUnwrap(drawWithTiles(scale: 1))

        let referenceInk = ink(reference)
        let referenceEdge = edgeEnergy(reference)

        // Coverage: font smoothing's stem darkening. A `CATextLayer` line measures
        // roughly 15% under the reference here, because smoothing cannot run in
        // the transparent backing store it owns.
        XCTAssertEqual(ink(ours), referenceInk, accuracy: referenceInk * 0.05,
                       "tiles should carry the same ink as AppKit's own rasterisation")

        // Edge contrast: whether stems land on the pixel grid. A fractional layer
        // origin measures roughly 13% under the reference even when smoothed.
        XCTAssertEqual(edgeEnergy(ours), referenceEdge, accuracy: referenceEdge * 0.05,
                       "tiles should land on the grid as hard as AppKit's own line")
    }

    func testTilesAgreeWithAppKitPixelForPixelAtOneX() throws {
        let reference = try XCTUnwrap(drawWithAppKit(scale: 1))
        let ours = try XCTUnwrap(drawWithTiles(scale: 1))

        // Exact, or as near as makes no difference: the phase cache is keyed on
        // Core Graphics' own quantum, so each tile is the same rasterisation
        // AppKit would have produced, placed on the same pixel.
        XCTAssertLessThan(meanAbsoluteDifference(reference, ours), 0.5,
                          "a line of tiles should be the line AppKit draws")
    }

    func testARetinaLineIsAlsoRasterisedRatherThanScaledFromOneX() throws {
        let ours = try XCTUnwrap(drawWithTiles(scale: 2))
        let reference = try XCTUnwrap(drawWithAppKit(scale: 2))
        let referenceInk = ink(reference)
        XCTAssertEqual(ink(ours), referenceInk, accuracy: referenceInk * 0.05)
    }

    // MARK: - Sub-pixel phase

    func testPhasesFloorLikeCoreGraphicsRatherThanRoundingOntoTheNextPixel() {
        XCTAssertEqual(GlyphRaster.quantise(devicePosition: 10.0).origin, 10)
        XCTAssertEqual(GlyphRaster.quantise(devicePosition: 10.0).bucket, 0)
        XCTAssertEqual(GlyphRaster.quantise(devicePosition: 10.5).bucket, 1)
        // Nearly the next pixel is still this one's last phase. Rounding up here
        // would put the glyph a whole pixel from where Core Text placed it.
        XCTAssertEqual(GlyphRaster.quantise(devicePosition: 10.99).origin, 10)
        XCTAssertEqual(GlyphRaster.quantise(devicePosition: 10.99).bucket, 2)
    }

    /// The measurement the phase cache is sized by, pinned so nobody re-derives it.
    ///
    /// Core Graphics quantises horizontal glyph positions to thirds of a device
    /// pixel. Sweeping one pixel in hundredths yields exactly three distinct
    /// rasters — so three phases reproduce AppKit's own rendering, and any other
    /// count silently lands glyphs in the wrong bucket. If this ever fails,
    /// `GlyphRaster.phaseCount` is what has to move.
    func testCoreGraphicsQuantisesGlyphPositionsToThirdsOfADevicePixel() {
        var distinct: [[UInt8]] = []
        for step in 0..<100 {
            guard let image = tile(inset: 3 + CGFloat(step) / 100) else { continue }
            let pixels = greyscale(image)
            if !distinct.contains(where: { $0 == pixels }) { distinct.append(pixels) }
        }
        XCTAssertEqual(distinct.count, GlyphRaster.phaseCount,
                       "the phase count should match Core Graphics' own quantum")
    }

    private func tile(inset: CGFloat) -> CGImage? {
        // Flushed each time: the cache keys on the bucket, and this is deliberately
        // reaching past it to ask what the rasteriser underneath actually does.
        GlyphRaster.flush()
        return GlyphRaster.tile(character: "R", font: font,
                                ink: NSColor.black.cgColor,
                                background: NSColor.white.cgColor,
                                phaseBucket: 0, scale: 1,
                                size: CGSize(width: 16, height: 20),
                                baseline: 5, inset: inset)
    }

    // MARK: - Colour glyphs

    /// A colour glyph is artwork, not ink, and the mask pipeline is written for ink: draw the
    /// glyph opaque, read one channel back as coverage, tint that with the label's colour. Run
    /// a colour bitmap through it and what comes out is a one-channel silhouette wearing the
    /// label's colour — a grey rocket, or, for the marks agents put in front of a chat name, a
    /// white asterisk with a dark cap over its top spoke.
    func testAColourGlyphIsDrawnAsAuthoredRatherThanTintedWithTheLabelsInk() throws {
        GlyphRaster.flush()
        XCTAssertTrue(GlyphRaster.isColorGlyph("🚀", font: font),
                      "this test needs a character the system draws from a colour face")

        let tile = try XCTUnwrap(colourTile(for: "🚀"))
        XCTAssertTrue(hasColour(tile), "the emoji came back monochrome")
    }

    /// The other half of the same contract: ordinary text still goes through the mask, so it
    /// still takes the label's colour and the whole reason `GlyphRaster` exists is untouched.
    func testAnOutlineGlyphIsStillTintedWithTheLabelsInk() throws {
        GlyphRaster.flush()
        XCTAssertFalse(GlyphRaster.isColorGlyph("R", font: font))

        let red = try XCTUnwrap(colourTile(for: "R", ink: NSColor.red.cgColor))
        let blue = try XCTUnwrap(colourTile(for: "R", ink: NSColor.blue.cgColor))
        XCTAssertNotEqual(meanChannels(red).red, meanChannels(blue).red, accuracy: 0.0,
                          "an outline glyph should follow the ink it is given")
        XCTAssertGreaterThan(meanChannels(red).red, meanChannels(blue).red)
    }

    private func colourTile(for character: String, ink: CGColor = NSColor.black.cgColor) -> CGImage? {
        GlyphRaster.tile(character: character, font: font,
                         ink: ink,
                         background: NSColor.white.cgColor,
                         phaseBucket: 0, scale: 2,
                         size: CGSize(width: 24, height: 24),
                         baseline: 6, inset: 3)
    }

    /// Whether the tile carries more than one hue. A tinted mask cannot: every pixel is the
    /// same colour at a different coverage, so the channels stay in a fixed ratio.
    private func hasColour(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return false }
        var ratios: [Double] = []
        for index in stride(from: 0, to: CFDataGetLength(data), by: 4) {
            let alpha = Double(bytes[index])
            guard alpha > 32 else { continue }
            let red = Double(bytes[index + 1]) / alpha
            let blue = Double(bytes[index + 3]) / alpha
            ratios.append(red - blue)
        }
        guard let low = ratios.min(), let high = ratios.max() else { return false }
        return high - low > 0.2
    }

    private func meanChannels(_ image: CGImage) -> (red: Double, blue: Double) {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return (0, 0) }
        let count = CFDataGetLength(data) / 4
        guard count > 0 else { return (0, 0) }
        var red = 0.0
        var blue = 0.0
        for index in stride(from: 0, to: count * 4, by: 4) {
            red += Double(bytes[index + 1])
            blue += Double(bytes[index + 3])
        }
        return (red / Double(count), blue / Double(count))
    }

    // MARK: - Backing scale

    func testSlotsAreLaidOutAgainstTheDisplaysPixelGrid() {
        let bounds = CGRect(origin: .zero, size: size)
        let atOneX = CharacterLayout.visibleSlots(for: text, font: font, bounds: bounds,
                                                  alignment: .left, scale: 1)
        let atTwoX = CharacterLayout.visibleSlots(for: text, font: font, bounds: bounds,
                                                  alignment: .left, scale: 2)
        XCTAssertEqual(atOneX.count, atTwoX.count)

        // Every frame lands on its own grid, which is why a label that moves
        // between screens has to lay out again rather than retag `contentsScale`.
        for slot in atOneX {
            XCTAssertEqual(slot.frame.minX, slot.frame.minX.rounded(), accuracy: 1e-9)
            XCTAssertEqual(slot.frame.width, slot.frame.width.rounded(), accuracy: 1e-9)
        }
        for slot in atTwoX {
            XCTAssertEqual(slot.frame.minX * 2, (slot.frame.minX * 2).rounded(), accuracy: 1e-9)
        }
        XCTAssertNotEqual(atOneX.map(\.frame), atTwoX.map(\.frame),
                          "the two grids should not produce the same layout")
    }

    func testTheInkBoxKeepsCoreTextsSpacingWhileTheTileIsSnapped() {
        let bounds = CGRect(origin: .zero, size: size)
        let slots = CharacterLayout.visibleSlots(for: text, font: font, bounds: bounds,
                                                 alignment: .left, scale: 1)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: CharacterLayout.textAttributes(font: font)))
        let exactWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        // Snapping the layer must not have snapped the advances: the last glyph's
        // ink box still ends where Core Text says the line ends.
        let last = slots.last
        XCTAssertEqual(last?.inkFrame.maxX ?? 0, exactWidth, accuracy: 0.01)
        XCTAssertGreaterThan(last?.frame.maxX ?? 0, exactWidth,
                             "the tile should overhang the ink box by its padding")
    }

    // MARK: - Drawing

    private func drawWithAppKit(scale: CGFloat) -> CGImage? {
        guard let context = makeContext(scale: scale) else { return nil }
        context.setShouldSmoothFonts(true)
        context.setShouldAntialias(true)
        let attributed = NSAttributedString(
            string: text,
            attributes: CharacterLayout.textAttributes(font: font, color: NSColor.black.cgColor))
        context.textPosition = CGPoint(x: 0, y: baseline(scale: scale))
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        return context.makeImage()
    }

    private func drawWithTiles(scale: CGFloat) -> CGImage? {
        guard let context = makeContext(scale: scale) else { return nil }
        let slots = CharacterLayout.visibleSlots(
            for: text, font: font,
            bounds: CGRect(origin: .zero, size: size), alignment: .left, scale: scale)
        for slot in slots {
            guard let tile = GlyphRaster.tile(character: slot.character, font: font,
                                              ink: NSColor.black.cgColor,
                                              background: NSColor.white.cgColor,
                                              phaseBucket: slot.phaseBucket, scale: scale,
                                              size: slot.frame.size,
                                              baseline: slot.baseline, inset: slot.inset)
            else { continue }
            context.draw(tile, in: slot.frame)
        }
        return context.makeImage()
    }

    /// The baseline `CharacterLayout` puts the line on, so the two renderings are
    /// compared where they actually overlap rather than a fraction apart.
    private func baseline(scale: CGFloat) -> CGFloat {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: CharacterLayout.textAttributes(font: font)))
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let originY = (size.height - (ascent + descent)) / 2
        return ((originY + descent) * scale).rounded() / scale
    }

    private func makeContext(scale: CGFloat) -> CGContext? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
        context.scaleBy(x: scale, y: scale)
        return context
    }

    // MARK: - Measuring

    /// Mean coverage: how dark the line renders.
    private func ink(_ image: CGImage) -> Double {
        let pixels = greyscale(image)
        return pixels.reduce(0.0) { $0 + 1 - Double($1) / 255 } / Double(pixels.count)
    }

    /// Mean absolute horizontal gradient: how hard the stem edges land.
    private func edgeEnergy(_ image: CGImage) -> Double {
        let pixels = greyscale(image)
        let width = image.width
        var total = 0.0
        for y in 0..<image.height {
            for x in 0..<(width - 1) {
                total += abs(Double(pixels[y * width + x]) - Double(pixels[y * width + x + 1]))
            }
        }
        return total / Double((width - 1) * image.height)
    }

    private func meanAbsoluteDifference(_ a: CGImage, _ b: CGImage) -> Double {
        let left = greyscale(a)
        let right = greyscale(b)
        guard left.count == right.count, !left.isEmpty else { return .infinity }
        var total = 0.0
        for index in 0..<left.count {
            total += abs(Double(left[index]) - Double(right[index]))
        }
        return total / Double(left.count)
    }

    private func greyscale(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        let count = width * height * 4
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        defer { buffer.deallocate() }
        let context = CGContext(data: buffer, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        context?.setFillColor(NSColor.white.cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (0..<(width * height)).map { buffer[$0 * 4 + 1] }
    }
}
