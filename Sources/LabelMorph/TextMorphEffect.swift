import QuartzCore

/// A strategy describing how characters enter, leave, and move during a morph.
///
/// Implement this protocol to add new ways for text to morph. Each method
/// receives the per-character layer plus a `MorphContext` with timing and
/// stagger helpers. Model values on the layer are already set to their final
/// state; effects add explicit animations on top.
public protocol TextMorphEffect: AnyObject {

    /// Animate a character that appears in the new text.
    func animateIn(_ layer: CATextLayer, context: MorphContext)

    /// Animate a character that is removed from the old text.
    /// The layer is removed from the hierarchy after the morph completes.
    func animateOut(_ layer: CATextLayer, context: MorphContext)

    /// Animate a character that exists in both texts and changes position.
    func animateMove(_ layer: CATextLayer, from: CGPoint, to: CGPoint, context: MorphContext)

    /// Extra time to wait before outgoing layers are removed, on top of
    /// `duration + stagger`. Spring-based effects need a larger margin.
    var settleMargin: CFTimeInterval { get }
}

/// Effects that replace a character in place — the old glyph transforms into
/// the new one at its slot — instead of separately animating the old
/// character out and the new one in. `MorphingLabel` pairs old and new
/// characters by position for these effects.
public protocol TextReplacementMorphEffect: TextMorphEffect {
    /// Animate `oldLayer`'s character turning into `newLayer`'s character.
    /// Both layers are in the layer tree; `container` is the label's backing
    /// layer, available for temporary overlay layers.
    func animateReplace(from oldLayer: CATextLayer,
                        to newLayer: CATextLayer,
                        in container: CALayer,
                        context: MorphContext)
}

/// An effect that replaces the complete old line with the complete new line.
///
/// Unlike character-scoped effects, a whole-line effect does not diff or reuse
/// matching characters. `MorphingLabel` builds both complete glyph runs and
/// calls this method once, allowing the effect to move each run in lockstep.
public protocol WholeLineMorphEffect: TextMorphEffect {
    /// Animate one complete single-line value into another.
    ///
    /// `outgoing` and `incoming` preserve visual character order. Either array
    /// can be empty when text is first introduced or cleared.
    func animateLineTransition(from outgoing: [CATextLayer],
                               to incoming: [CATextLayer],
                               in container: CALayer,
                               context: MorphContext)
}

public extension WholeLineMorphEffect {
    /// Whole-line effects receive the transition through
    /// `animateLineTransition`; the character callbacks are intentionally idle.
    func animateIn(_ layer: CATextLayer, context: MorphContext) {}
    func animateOut(_ layer: CATextLayer, context: MorphContext) {}
}

/// Name for temporary layers an effect adds to the label's backing layer
/// (shape stand-ins, particles, …). `MorphingLabel` removes every sublayer
/// carrying this name when a morph is interrupted or the label is rebuilt.
public enum MorphTransientLayer {
    public static let name = "labelmorph.transient"
}

public extension TextMorphEffect {

    var settleMargin: CFTimeInterval { 0.35 }

    func animateMove(_ layer: CATextLayer, from: CGPoint, to: CGPoint, context: MorphContext) {
        // Animate a relative translation instead of absolute positions: the
        // layer's model position stays authoritative even if the label is
        // re-laid out while the morph is in flight.
        let delta = CGSize(width: from.x - to.x, height: from.y - to.y)
        let move = context.animation("transform.translation",
                                     from: morphSizeValue(delta),
                                     to: morphSizeValue(.zero))
        layer.add(move, forKey: "morph.move")
    }
}
