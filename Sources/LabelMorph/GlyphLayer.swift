import AppKit
import QuartzCore

/// The layer one character is drawn into.
///
/// It subclasses `CATextLayer` rather than `CALayer` deliberately. Nothing of
/// `CATextLayer`'s *rendering* survives — `display()` installs a `GlyphRaster`
/// tile and never calls `super`, which is the whole point of the class (see
/// `GlyphRaster` for what that buys at 1x). What survives is its *interface*:
/// `TextMorphEffect` is written in terms of `CATextLayer`, `GlyphMorphEffect`
/// reads `string` to lift a glyph outline, and `MorphingLabel.displayedCharacters`
/// reads it to answer what is actually on screen. Keeping `string` authoritative
/// means ten effect files and their tests did not have to move.
final class GlyphLayer: CATextLayer {

    /// The slot this layer draws, or `nil` before one is applied.
    private(set) var slot: CharacterSlot?

    /// The face the glyph is rasterised in. `CATextLayer` already has a `font`,
    /// typed `CFTypeRef?` and consulted only by the rendering this class
    /// replaces, so ours needs its own name.
    var glyphFont: NSFont = .systemFont(ofSize: 13) {
        didSet {
            guard glyphFont != oldValue else { return }
            setNeedsDisplay()
        }
    }

    /// The glyph's colour. Also written into `string` by the label so that
    /// `GlyphMorphEffect` can style its stand-in shape from the same source.
    var ink: CGColor = NSColor.labelColor.cgColor {
        didSet {
            guard ink != oldValue else { return }
            setNeedsDisplay()
        }
    }

    /// What the glyph is smoothed against. Font smoothing dilates dark ink on a
    /// light ground and thins light ink on a dark one, so this decides which of
    /// the two the raster is. `nil` leaves the decision to the ink's own
    /// luminance, which is right often enough for a host that does not say.
    var rasterBackground: CGColor? {
        didSet {
            guard rasterBackground != oldValue else { return }
            setNeedsDisplay()
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        isWrapped = false
        truncationMode = .none
    }

    /// Core Animation copies a layer to build its presentation layer, and a
    /// subclass that does not carry its stored properties across renders an
    /// empty tile mid-animation.
    override init(layer: Any) {
        if let source = layer as? GlyphLayer {
            slot = source.slot
            glyphFont = source.glyphFont
            ink = source.ink
            rasterBackground = source.rasterBackground
        }
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Slots

    /// Moves the layer onto `slot`, which owns both the frame and the sub-pixel
    /// phase its raster was cached under — they are one decision and must not be
    /// assigned separately.
    func apply(_ slot: CharacterSlot) {
        let framed = frame != slot.frame
        self.slot = slot
        if framed { frame = slot.frame }
        setNeedsDisplay()
    }

    // MARK: - CALayer

    override func display() {
        guard let slot, bounds.width > 0, bounds.height > 0 else {
            contents = nil
            return
        }
        contents = GlyphRaster.tile(character: slot.character,
                                    font: glyphFont,
                                    ink: ink,
                                    background: rasterBackground ?? Self.unstated,
                                    phaseBucket: slot.phaseBucket,
                                    scale: contentsScale,
                                    size: bounds.size,
                                    baseline: slot.baseline,
                                    inset: slot.inset)
    }

    /// A background nobody stated. Transparent, so `GlyphRaster` falls through to
    /// reading the ink instead of believing this is a black ground.
    private static let unstated = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
}
