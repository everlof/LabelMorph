import QuartzCore

/// Old characters fade out while new ones fade in.
public final class CrossfadeEffect: TextMorphEffect {

    public init() {}

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 0, to: 1), forKey: "morph.in")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 1, to: 0), forKey: "morph.out")
    }
}
