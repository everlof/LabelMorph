import AppKit
import QuartzCore

/// Characters flip around their horizontal axis, like a split-flap display.
/// Requires the perspective transform that `MorphingLabel` installs on its
/// container layer.
public final class FlipEffect: TextMorphEffect {

    public init() {}

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("transform.rotation.x", from: -CGFloat.pi / 2, to: 0),
                  forKey: "morph.in.rotation")
        layer.add(context.animation("opacity", from: 0, to: 1,
                                    duration: context.timing.duration * 0.5),
                  forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("transform.rotation.x", from: 0, to: CGFloat.pi / 2),
                  forKey: "morph.out.rotation")
        layer.add(context.animation("opacity", from: 1, to: 0),
                  forKey: "morph.out.opacity")
    }
}
