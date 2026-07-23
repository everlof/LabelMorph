# LabelMorph

An AppKit framework for morphing text on a label, character by character.

`MorphingLabel` lays out its text with Core Text, gives every character its own
layer, and diffs old vs. new text when it changes: characters present in both
strings fly to their new position, removed characters animate out, and added
characters animate in — using a pluggable effect.

## Usage

```swift
import LabelMorph

let label = MorphingLabel()
label.font = .systemFont(ofSize: 48, weight: .semibold)
label.effect = MorphPreset.bounce.makeEffect(intensity: 0.7)
label.timing = MorphTiming(duration: 0.6, stagger: 0.04)

label.text = "Hello, World!"   // morphs using the current effect
label.setText("Goodbye!", animated: false)
```

## Built-in presets

| Preset | Behavior |
| --- | --- |
| Shape Morph | Each glyph's outline is broken into contours and morphed into the new glyph in place; added characters grow from points, removed ones collapse into them |
| Crossfade | Old characters fade out, new fade in |
| Slide Up / Slide Down | Characters slide through vertically, fading |
| Scale | New characters zoom in, old ones blow up and fade |
| Bounce | Characters spring up from below with overshoot |
| Drop | Characters fall in from above with a tilt and spring landing |
| Flip | Split-flap style rotation around the horizontal axis |
| Blur | Characters sharpen into focus from a gaussian blur |
| Scramble | Characters cycle through random glyphs before settling |
| Typewriter | Typed in front-to-back, deleted back-to-front |

Every preset exposes `recommendedTiming` and takes an `intensity` (0…1) that
scales its parameters (distance, spring damping, blur radius, …).

## Custom effects

Implement `TextMorphEffect` to add a new way for text to morph:

```swift
final class MyEffect: TextMorphEffect {
    func animateIn(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 0, to: 1), forKey: "in")
    }
    func animateOut(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 1, to: 0), forKey: "out")
    }
}
```

`MorphContext` carries the character index, timing, and stagger helpers, and
builds pre-configured basic/spring animations. `animateMove` has a default
implementation (a plain translation animation) you can override.

Conform to `TextReplacementMorphEffect` instead when the effect transforms a
character *in place* (like Shape Morph does): the label then pairs old and new
characters by position and calls `animateReplace(from:to:in:context:)` for
each changed pair.

## Showcase app

The `Showcase` target is a small app for playing with the effects: an effect
picker, sliders for duration / stagger / intensity / font size, easing
selection, custom text input, phrase cycling (click the preview), auto-play,
and a toggle for character reuse.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
open LabelMorph.xcodeproj   # run the "Showcase" scheme
```

## Notes / limitations

- Single-line text only (no wrapping); left-to-right scripts.
- Requires macOS 13+.
