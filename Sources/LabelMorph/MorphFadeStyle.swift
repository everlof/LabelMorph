import Foundation

/// An optional opacity treatment composed around a morph effect.
public enum MorphFadeStyle: Equatable {
    /// The selected effect owns opacity on its own.
    case none

    /// A dark-to-light opacity trough travels through the glyphs from leading
    /// to trailing, like a soft wipe, while the selected effect keeps owning
    /// its transform, shape, blur, or replacement motion.
    case traveling
}

/// Tuning for the traveling fade composed around a morph effect.
///
/// Values outside their useful ranges are clamped when an animation starts:
/// at least one pulse, opacity between zero and one, and non-negative times.
public struct MorphFadeConfiguration: Equatable, Sendable {
    /// How many times each character position dims and returns to full opacity.
    public var pulseCount: Int

    /// Opacity at the bottom of each pulse. Lower values create a deeper shade.
    public var minimumOpacity: Float

    /// Time for one complete dim-and-return pulse at a character position.
    public var pulseDuration: TimeInterval

    /// Full-opacity pause between consecutive pulses at each character
    /// position. Zero produces a continuous, back-to-back pulse envelope.
    public var pauseDuration: TimeInterval

    /// Time between the first and last character beginning their pulses.
    public var travelDuration: TimeInterval

    public init(pulseCount: Int = 2,
                minimumOpacity: Float = 0.14,
                pulseDuration: TimeInterval = 0.28,
                pauseDuration: TimeInterval = 0.12,
                travelDuration: TimeInterval = 0.42) {
        self.pulseCount = pulseCount
        self.minimumOpacity = minimumOpacity
        self.pulseDuration = pulseDuration
        self.pauseDuration = pauseDuration
        self.travelDuration = travelDuration
    }
}
