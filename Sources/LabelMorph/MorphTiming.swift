import Foundation
import QuartzCore

/// Timing configuration shared by all morph effects.
public struct MorphTiming {

    /// Duration of the animation applied to a single character.
    public var duration: CFTimeInterval

    /// Extra delay added per character, producing a cascading effect.
    public var stagger: CFTimeInterval

    /// Timing function used by non-spring animations.
    public var timingFunction: CAMediaTimingFunction

    public init(duration: CFTimeInterval = 0.45,
                stagger: CFTimeInterval = 0.025,
                timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)) {
        self.duration = duration
        self.stagger = stagger
        self.timingFunction = timingFunction
    }
}

/// Per-character information handed to an effect when a morph starts.
public struct MorphContext {

    /// Index of the character within its group (incoming or outgoing).
    public let index: Int

    /// Number of characters in the group.
    public let count: Int

    public let timing: MorphTiming
    public let font: MorphFont

    public init(index: Int, count: Int, timing: MorphTiming, font: MorphFont) {
        self.index = index
        self.count = count
        self.timing = timing
        self.font = font
    }

    /// Delay for this character when cascading front-to-back.
    public var staggerDelay: CFTimeInterval {
        timing.stagger * CFTimeInterval(index)
    }

    /// Delay for this character when cascading back-to-front.
    public var reverseStaggerDelay: CFTimeInterval {
        timing.stagger * CFTimeInterval(max(0, count - 1 - index))
    }

    /// Builds a basic animation pre-configured with this context's timing.
    /// The layer's model values should already be set to their final state.
    public func animation(_ keyPath: String,
                          from: Any? = nil,
                          to: Any? = nil,
                          delay: CFTimeInterval? = nil,
                          duration: CFTimeInterval? = nil,
                          timingFunction: CAMediaTimingFunction? = nil) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = CACurrentMediaTime() + (delay ?? staggerDelay)
        animation.duration = max(0.01, duration ?? timing.duration)
        animation.timingFunction = timingFunction ?? timing.timingFunction
        // Freeze at fromValue until the staggered start, then let the
        // animation be removed so the layer's model values (kept up to date
        // by relayout) take over. Holding stale absolute values would corrupt
        // the layout whenever the label resizes mid-morph.
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        return animation
    }

    /// Builds a spring animation pre-configured with this context's timing.
    public func spring(_ keyPath: String,
                       from: Any? = nil,
                       to: Any? = nil,
                       delay: CFTimeInterval? = nil,
                       damping: CGFloat = 14,
                       stiffness: CGFloat = 220,
                       initialVelocity: CGFloat = 0) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.damping = damping
        animation.stiffness = stiffness
        animation.mass = 1
        animation.initialVelocity = initialVelocity
        animation.duration = animation.settlingDuration
        animation.beginTime = CACurrentMediaTime() + (delay ?? staggerDelay)
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        return animation
    }
}
