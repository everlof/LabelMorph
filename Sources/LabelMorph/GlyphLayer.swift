#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
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
    var glyphFont: MorphFont = .systemFont(ofSize: 13) {
        didSet {
            guard glyphFont != oldValue else { return }
            setNeedsDisplay()
        }
    }

    /// The glyph's colour. Also written into `string` by the label so that
    /// `GlyphMorphEffect` can style its stand-in shape from the same source.
    var ink: CGColor = MorphColor.morphLabelColor.cgColor {
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
    ///
    /// The slot owns the frame in both directions: a layer that is not where its slot
    /// says is brought back even when the slot it is handed is the one it already holds.
    /// `shift(by:)` keeps the two together so a morph can see what it has to travel;
    /// this guard is what turns any frame written behind the slot's back into a slip
    /// the next layout corrects rather than a glyph left off its line for good.
    func apply(_ slot: CharacterSlot) {
        guard slot != self.slot || frame != slot.frame else { return }

        let rasterChanged = self.slot.map {
            $0.character != slot.character
                || $0.frame.size != slot.frame.size
                || $0.phaseBucket != slot.phaseBucket
                || $0.baseline != slot.baseline
                || $0.inset != slot.inset
        } ?? true
        let framed = frame != slot.frame
        self.slot = slot
        if framed { frame = slot.frame }
        if rasterChanged { setNeedsDisplay() }
    }

    /// Moves the layer by `delta` without changing what it draws.
    ///
    /// The slot moves with the frame, and that is the point of this being a method rather
    /// than a frame assignment. `apply(_:)` decides it has nothing to do by comparing slots,
    /// so a layer whose frame was moved *behind* its slot looked settled while sitting
    /// somewhere else: the label shifted every old glyph to stay where the eye last saw it,
    /// then handed the character it was keeping the slot it already held, and the layer kept
    /// the shift — no animation was asked to move it, and no later pass had a reason to
    /// correct a slot that already matched. A sidebar row renamed in the pass that moved it
    /// drew its first letter half a line below the rest of its name, indefinitely.
    /// Moving the slot too means the next `apply` sees a real difference and the effect is
    /// asked to travel it, and an effect positioning a stand-in from `slot.inkFrame` starts
    /// it where the glyph is actually drawn.
    func shift(by delta: CGPoint) {
        guard delta != .zero else { return }
        frame = frame.offsetBy(dx: delta.x, dy: delta.y)
        slot = slot?.offset(by: delta)
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
