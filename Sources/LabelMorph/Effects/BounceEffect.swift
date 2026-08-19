import QuartzCore

/// New characters spring up from below with an overshoot; old characters
/// sink away.
public final class BounceEffect: TextMorphEffect {

    /// Rise distance as a multiple of the font point size.
    public var distanceFactor: CGFloat

    /// Spring damping — lower values bounce more.
    public var damping: CGFloat

    public var settleMargin: CFTimeInterval { 0.8 }

    public init(distanceFactor: CGFloat = 0.7, damping: CGFloat = 11) {
        self.distanceFactor = distanceFactor
        self.damping = damping
    }

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        let distance = context.font.pointSize * distanceFactor
        layer.add(context.spring("transform.translation.y", from: -distance, to: 0,
                                 damping: damping, stiffness: 220),
                  forKey: "morph.in.y")
        layer.add(context.animation("opacity", from: 0, to: 1,
                                    duration: min(0.2, context.timing.duration)),
                  forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        let distance = context.font.pointSize * distanceFactor
        layer.add(context.animation("transform.translation.y", from: 0, to: -distance * 0.4,
                                    duration: context.timing.duration * 0.6,
                                    timingFunction: CAMediaTimingFunction(name: .easeIn)),
                  forKey: "morph.out.y")
        layer.add(context.animation("opacity", from: 1, to: 0,
                                    duration: context.timing.duration * 0.6),
                  forKey: "morph.out.opacity")
    }
}
