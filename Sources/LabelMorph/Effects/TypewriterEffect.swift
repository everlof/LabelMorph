import QuartzCore

/// New characters pop in one at a time, front to back; old characters are
/// deleted back to front like backspacing. Drive the pace with
/// `MorphTiming.stagger` — the per-character duration barely matters.
public final class TypewriterEffect: TextMorphEffect {

    public init() {}

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 0, to: 1,
                                    delay: context.staggerDelay,
                                    duration: 0.02),
                  forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 1, to: 0,
                                    delay: context.reverseStaggerDelay,
                                    duration: 0.02),
                  forKey: "morph.out.opacity")
    }
}
