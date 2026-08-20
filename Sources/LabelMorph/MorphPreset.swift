import QuartzCore

/// The built-in morph effects, with factory methods that map a single
/// 0...1 "intensity" knob onto each effect's parameters.
public enum MorphPreset: String, CaseIterable {
    public enum Scope: String, CaseIterable, Sendable {
        case singleCharacter
        case wholeLine
    }

    case shapeMorph
    case crossfade
    case slideUp
    case slideDown
    case lineScrollUp
    case lineScrollDown
    case scale
    case bounce
    case drop
    case flip
    case blur
    case scramble
    case typewriter

    public var displayName: String {
        switch self {
        case .shapeMorph: "Shape Morph"
        case .crossfade: "Crossfade"
        case .slideUp: "Slide Up"
        case .slideDown: "Slide Down"
        case .lineScrollUp: "Line Scroll Up"
        case .lineScrollDown: "Line Scroll Down"
        case .scale: "Scale"
        case .bounce: "Bounce"
        case .drop: "Drop"
        case .flip: "Flip"
        case .blur: "Blur"
        case .scramble: "Scramble"
        case .typewriter: "Typewriter"
        }
    }

    /// Whether this preset diffs and animates characters independently or
    /// hands the complete old and new lines to one coordinated transition.
    public var scope: Scope {
        switch self {
        case .lineScrollUp, .lineScrollDown: .wholeLine
        default: .singleCharacter
        }
    }

    /// Creates the effect, scaling its parameters by `intensity` (0...1).
    public func makeEffect(intensity: Double = 0.6) -> TextMorphEffect {
        let intensity = CGFloat(max(0, min(1, intensity)))
        switch self {
        case .shapeMorph:
            // Intensity buys sampling resolution: smoother outlines cost more.
            return GlyphMorphEffect(pointsPerContour: 32 + Int(96 * intensity))
        case .crossfade:
            return CrossfadeEffect()
        case .slideUp:
            return SlideEffect(direction: .up, distanceFactor: 0.25 + 1.0 * intensity)
        case .slideDown:
            return SlideEffect(direction: .down, distanceFactor: 0.25 + 1.0 * intensity)
        case .lineScrollUp:
            return LineScrollEffect(direction: .up, distanceFactor: 0.65 + 0.85 * intensity)
        case .lineScrollDown:
            return LineScrollEffect(direction: .down, distanceFactor: 0.65 + 0.85 * intensity)
        case .scale:
            return ScaleEffect(inFromScale: max(0.05, 1.0 - 0.9 * intensity),
                               outToScale: 1.0 + 0.8 * intensity)
        case .bounce:
            return BounceEffect(distanceFactor: 0.3 + 0.8 * intensity,
                                damping: max(5, 16 - 11 * intensity))
        case .drop:
            return DropEffect(distanceFactor: 0.6 + 1.2 * intensity,
                              tilt: 0.3 * intensity)
        case .flip:
            return FlipEffect()
        case .blur:
            return BlurEffect(maxRadius: 2 + 28 * intensity)
        case .scramble:
            return ScrambleEffect()
        case .typewriter:
            return TypewriterEffect()
        }
    }

    /// What the `intensity` knob controls for this preset, suitable for
    /// display in a UI.
    public var intensityDescription: String {
        switch self {
        case .shapeMorph: "Outline sampling detail — low values morph visibly polygonal, high values smooth."
        case .crossfade, .flip, .scramble, .typewriter: "Not used by this effect."
        case .slideUp, .slideDown: "How far characters travel while sliding."
        case .lineScrollUp, .lineScrollDown: "How far the complete old and new lines travel."
        case .scale: "How much characters zoom — smaller on entry, bigger on exit."
        case .bounce: "Rise distance and bounciness of the spring."
        case .drop: "Fall distance and tilt while dropping."
        case .blur: "Maximum blur radius characters sharpen from."
        }
    }

    /// Timing that shows the effect off well; a good starting point for
    /// user tweaking.
    public var recommendedTiming: MorphTiming {
        switch self {
        case .shapeMorph: MorphTiming(duration: 0.55, stagger: 0.045)
        case .crossfade: MorphTiming(duration: 0.35, stagger: 0.015)
        case .slideUp, .slideDown: MorphTiming(duration: 0.4, stagger: 0.03)
        case .lineScrollUp, .lineScrollDown: MorphTiming(duration: 0.45, stagger: 0)
        case .scale: MorphTiming(duration: 0.4, stagger: 0.02)
        case .bounce: MorphTiming(duration: 0.6, stagger: 0.04)
        case .drop: MorphTiming(duration: 0.6, stagger: 0.05)
        case .flip: MorphTiming(duration: 0.5, stagger: 0.05)
        case .blur: MorphTiming(duration: 0.55, stagger: 0.03)
        case .scramble: MorphTiming(duration: 0.7, stagger: 0.03)
        case .typewriter: MorphTiming(duration: 0.05, stagger: 0.06)
        }
    }
}
