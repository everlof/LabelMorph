import AppKit
import QuartzCore

/// New characters drop in from above with a slight tilt and land with a
/// spring; old characters tumble off the bottom.
public final class DropEffect: TextMorphEffect {

    /// Fall distance as a multiple of the font point size.
    public var distanceFactor: CGFloat

    /// Maximum tilt in radians while falling. Alternates per character.
    public var tilt: CGFloat

    public var settleMargin: CFTimeInterval { 0.8 }

    public init(distanceFactor: CGFloat = 1.2, tilt: CGFloat = 0.18) {
        self.distanceFactor = distanceFactor
        self.tilt = tilt
    }

    private func tiltAngle(for index: Int) -> CGFloat {
        tilt * (index.isMultiple(of: 2) ? 1 : -1)
    }

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        let distance = context.font.pointSize * distanceFactor
        layer.add(context.spring("transform.translation.y", from: distance, to: 0,
                                 damping: 18, stiffness: 320),
                  forKey: "morph.in.y")
        layer.add(context.animation("transform.rotation.z",
                                    from: tiltAngle(for: context.index), to: 0),
                  forKey: "morph.in.rotation")
        layer.add(context.animation("opacity", from: 0, to: 1,
                                    duration: min(0.15, context.timing.duration)),
                  forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        let distance = context.font.pointSize * distanceFactor
        let easeIn = CAMediaTimingFunction(name: .easeIn)
        layer.add(context.animation("transform.translation.y", from: 0, to: -distance,
                                    duration: context.timing.duration * 0.8,
                                    timingFunction: easeIn),
                  forKey: "morph.out.y")
        layer.add(context.animation("transform.rotation.z",
                                    from: 0, to: -tiltAngle(for: context.index),
                                    duration: context.timing.duration * 0.8),
                  forKey: "morph.out.rotation")
        layer.add(context.animation("opacity", from: 1, to: 0,
                                    duration: context.timing.duration * 0.8),
                  forKey: "morph.out.opacity")
    }
}
