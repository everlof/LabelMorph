import AppKit
import QuartzCore

/// A single-line label that animates text changes character by character.
///
/// Setting `text` (or calling `setText(_:animated:)`) diffs the old and new
/// strings: characters present in both fly to their new position, removed
/// characters animate out, and added characters animate in — all according to
/// the current `effect` and `timing`.
public final class MorphingLabel: NSView {

    // MARK: - Public API

    // Each of these three rebuilds or repaints every glyph layer, and a host that
    // reconfigures a reused view restates all of them on every pass. Assigning the value
    // already in force must therefore cost nothing.

    public var font: NSFont = .systemFont(ofSize: 48, weight: .semibold) {
        didSet {
            guard font != oldValue else { return }
            truncationCache = nil
            rebuild()
        }
    }

    /// How text wider than the label is shortened. `intrinsicContentSize` still reports the
    /// whole text's width, so Auto Layout is told what the label wants and truncation only
    /// describes what it does once given less.
    public var truncation: MorphTruncation = .none {
        didSet {
            guard truncation != oldValue else { return }
            truncationCache = nil
            rebuild()
        }
    }

    public var textColor: NSColor = .labelColor {
        didSet {
            guard textColor != oldValue else { return }
            updateTextColors()
        }
    }

    public var alignment: NSTextAlignment = .center {
        didSet {
            guard alignment != oldValue else { return }
            relayoutCurrent()
        }
    }

    /// The strategy used to animate characters. See `MorphPreset` for the
    /// built-in effects, or implement `TextMorphEffect` for custom ones.
    public var effect: TextMorphEffect = CrossfadeEffect()

    public var timing = MorphTiming()

    /// When enabled, characters that exist in both the old and new text fly
    /// to their new position instead of animating out and back in.
    public var reusesMatchingCharacters = true

    /// Setting this morphs to the new value using the current effect.
    public var text: String {
        get { storedText }
        set { setText(newValue) }
    }

    public func setText(_ newText: String, animated: Bool = true) {
        guard newText != storedText else { return }
        guard animated, window != nil, !bounds.isEmpty else {
            storedText = newText
            rebuild()
            return
        }
        morph(to: newText)
    }

    // MARK: - Setup

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layerUsesCoreImageFilters = true
        // Perspective for 3D effects such as flip.
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 600.0
        layer?.sublayerTransform = transform
    }

    // MARK: - NSView

    public override var intrinsicContentSize: NSSize {
        let size = CharacterLayout.measure(storedText, font: font)
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    public override func layout() {
        super.layout()
        if !isResolvingMorphLayout {
            relayoutCurrent()
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTextColors()
    }

    // MARK: - Morphing

    private var storedText: String = ""
    private var visibleSlots: [CharacterSlot] = []

    /// The characters currently *drawn*, in visual order — read from the layers rather than
    /// the slot model, because the one bug worth testing here is exactly the two disagreeing:
    /// a reposition pass that updates the model but leaves a stale glyph on screen. `text`
    /// deliberately reports neither.
    var displayedCharacters: [String] {
        charLayers.compactMap { ($0.string as? NSAttributedString)?.string }
    }
    private var charLayers: [CATextLayer] = []
    private var leavingLayers: [CATextLayer] = []
    private var generation = 0
    private var isResolvingMorphLayout = false

    /// Truncation is recomputed on every layout pass, and a sidebar full of these lays out
    /// often, so the answer is kept until the text, the width or the font moves.
    private var truncationCache: (text: String, width: CGFloat, result: String)?

    /// The string actually laid out: the text itself, or its ellipsized head.
    private func displayText(in bounds: CGRect) -> String {
        guard truncation == .tail else { return storedText }

        if let cache = truncationCache, cache.text == storedText, cache.width == bounds.width {
            return cache.result
        }

        let result = CharacterLayout.tailTruncated(storedText, font: font, width: bounds.width)
        truncationCache = (storedText, bounds.width, result)
        return result
    }

    private func morph(to newText: String) {
        generation += 1
        let currentGeneration = generation

        // Finalize any in-flight morph: drop outgoing layers immediately and
        // snap retained layers to their model state.
        leavingLayers.forEach { $0.removeFromSuperlayer() }
        leavingLayers.removeAll()
        purgeTransientLayers()
        charLayers.forEach { $0.removeAllAnimations() }

        let oldSlots = visibleSlots
        let oldLayers = charLayers

        storedText = newText

        // Resolve the label's final geometry now, so every animation is built
        // against the bounds the text will actually settle in.
        let originBefore = convert(NSPoint.zero, to: nil)
        isResolvingMorphLayout = true
        invalidateIntrinsicContentSize()
        window?.layoutIfNeeded()
        isResolvingMorphLayout = false

        // Auto Layout may have shifted the label itself (re-centering after a
        // width change). Shift the old characters' model frames to keep their
        // on-screen position, so travel to the new layout happens inside the
        // morph animations — otherwise the whole line jumps first and morphs
        // second.
        let originAfter = convert(NSPoint.zero, to: nil)
        let shift = NSPoint(x: originBefore.x - originAfter.x, y: originBefore.y - originAfter.y)
        if shift != .zero {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for charLayer in oldLayers {
                charLayer.frame = charLayer.frame.offsetBy(dx: shift.x, dy: shift.y)
            }
            CATransaction.commit()
        }

        // `storedText` is already the new text, so this is the new line as it will be seen —
        // truncated if it has to be. Two names sharing a head morph only where they differ.
        let newSlots = CharacterLayout.visibleSlots(
            for: displayText(in: bounds), font: font, bounds: bounds, alignment: alignment
        )
        visibleSlots = newSlots

        var newLayers = [CATextLayer?](repeating: nil, count: newSlots.count)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let replacementEffect = effect as? TextReplacementMorphEffect {
            morphByPosition(replacementEffect, oldSlots: oldSlots, oldLayers: oldLayers,
                            newSlots: newSlots, newLayers: &newLayers)
        } else {
            morphByDiff(oldSlots: oldSlots, oldLayers: oldLayers,
                        newSlots: newSlots, newLayers: &newLayers)
        }

        CATransaction.commit()

        charLayers = newLayers.compactMap { $0 }

        let cleanupDelay = timing.duration
            + timing.stagger * CFTimeInterval(max(oldSlots.count, newSlots.count))
            + effect.settleMargin
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.leavingLayers.forEach { $0.removeFromSuperlayer() }
            self.leavingLayers.removeAll()
        }
    }

    /// Classic flow: characters common to both texts fly to their new
    /// position; the rest animate out and in.
    private func morphByDiff(oldSlots: [CharacterSlot], oldLayers: [CATextLayer],
                             newSlots: [CharacterSlot], newLayers: inout [CATextLayer?]) {
        let diff = CharacterDiff.compute(
            old: oldSlots.map(\.character),
            new: newSlots.map(\.character),
            matchDistanceLimit: reusesMatchingCharacters ? nil : 0
        )

        for move in diff.moves {
            let layer = oldLayers[move.from]
            let fromPosition = layer.position
            layer.frame = newSlots[move.to].frame
            newLayers[move.to] = layer
            if fromPosition != layer.position {
                effect.animateMove(layer, from: fromPosition, to: layer.position,
                                   context: context(index: move.to, count: newSlots.count))
            }
        }

        for index in diff.insertions {
            let charLayer = makeLayer(for: newSlots[index])
            layer?.addSublayer(charLayer)
            newLayers[index] = charLayer
            effect.animateIn(charLayer, context: context(index: index, count: newSlots.count))
        }

        for index in diff.removals {
            let charLayer = oldLayers[index]
            leavingLayers.append(charLayer)
            effect.animateOut(charLayer, context: context(index: index, count: oldSlots.count))
            // Final model state is invisible: once the effect's animations
            // complete and are removed, the layer must not pop back before
            // the deferred cleanup detaches it.
            charLayer.opacity = 0
        }
    }

    /// Replacement flow: characters are paired by position and the old glyph
    /// turns into the new one in place.
    private func morphByPosition(_ replacementEffect: TextReplacementMorphEffect,
                                 oldSlots: [CharacterSlot], oldLayers: [CATextLayer],
                                 newSlots: [CharacterSlot], newLayers: inout [CATextLayer?]) {
        guard let container = self.layer else { return }
        let pairCount = min(oldSlots.count, newSlots.count)

        for index in 0..<newSlots.count {
            if index < pairCount {
                let oldLayer = oldLayers[index]
                if oldSlots[index].character == newSlots[index].character {
                    let fromPosition = oldLayer.position
                    oldLayer.frame = newSlots[index].frame
                    newLayers[index] = oldLayer
                    if fromPosition != oldLayer.position {
                        effect.animateMove(oldLayer, from: fromPosition, to: oldLayer.position,
                                           context: context(index: index, count: newSlots.count))
                    }
                } else {
                    let newLayer = makeLayer(for: newSlots[index])
                    container.addSublayer(newLayer)
                    newLayers[index] = newLayer
                    leavingLayers.append(oldLayer)
                    replacementEffect.animateReplace(from: oldLayer, to: newLayer, in: container,
                                                     context: context(index: index, count: newSlots.count))
                    oldLayer.opacity = 0
                }
            } else {
                let newLayer = makeLayer(for: newSlots[index])
                container.addSublayer(newLayer)
                newLayers[index] = newLayer
                effect.animateIn(newLayer, context: context(index: index, count: newSlots.count))
            }
        }

        for index in pairCount..<oldSlots.count {
            let oldLayer = oldLayers[index]
            leavingLayers.append(oldLayer)
            effect.animateOut(oldLayer, context: context(index: index, count: oldSlots.count))
            oldLayer.opacity = 0
        }
    }

    private func context(index: Int, count: Int) -> MorphContext {
        MorphContext(index: index, count: count, timing: timing, font: font)
    }

    // MARK: - Layer management

    private static let disabledActions: [String: CAAction] = [
        "position": NSNull(),
        "bounds": NSNull(),
        "opacity": NSNull(),
        "transform": NSNull(),
        "contents": NSNull(),
        "filters": NSNull(),
        "hidden": NSNull(),
        "string": NSNull(),
        "foregroundColor": NSNull(),
    ]

    private func makeLayer(for slot: CharacterSlot) -> CATextLayer {
        let charLayer = CATextLayer()
        charLayer.string = NSAttributedString(
            string: slot.character,
            attributes: CharacterLayout.textAttributes(font: font, color: resolvedTextColor())
        )
        charLayer.frame = slot.frame
        charLayer.contentsScale = window?.backingScaleFactor ?? 2
        charLayer.isWrapped = false
        charLayer.truncationMode = .none
        charLayer.actions = Self.disabledActions
        return charLayer
    }

    /// Tears everything down and lays the current text out from scratch.
    private func rebuild() {
        generation += 1
        (charLayers + leavingLayers).forEach { $0.removeFromSuperlayer() }
        leavingLayers.removeAll()
        purgeTransientLayers()

        visibleSlots = CharacterLayout.visibleSlots(
            for: displayText(in: bounds), font: font, bounds: bounds, alignment: alignment
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        charLayers = visibleSlots.map { slot in
            let charLayer = makeLayer(for: slot)
            layer?.addSublayer(charLayer)
            return charLayer
        }
        CATransaction.commit()

        invalidateIntrinsicContentSize()
    }

    /// Repositions existing layers after a bounds, alignment, or similar change.
    private func relayoutCurrent() {
        // A width change can change how much of the text fits, so this is also where a
        // truncated line grows or shrinks — which changes the laid-out characters and falls
        // through to a rebuild. Compared by *character*, not by count: tail truncation that
        // drops exactly one character replaces it with the ellipsis, so "hi 😂" shortened and
        // restored is eight slots either way, and a count guard repositioned the stale "…"
        // where the emoji belonged — forever, since every later pass agreed about the count.
        let slots = CharacterLayout.visibleSlots(
            for: displayText(in: bounds), font: font, bounds: bounds, alignment: alignment
        )
        guard slots.count == charLayers.count,
              zip(slots, visibleSlots).allSatisfy({ $0.character == $1.character }) else {
            rebuild()
            return
        }
        visibleSlots = slots

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (charLayer, slot) in zip(charLayers, slots) {
            charLayer.frame = slot.frame
        }
        CATransaction.commit()
    }

    /// Removes temporary overlay layers effects may have added (see
    /// `MorphTransientLayer`).
    private func purgeTransientLayers() {
        layer?.sublayers?
            .filter { $0.name == MorphTransientLayer.name }
            .forEach { $0.removeFromSuperlayer() }
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        (charLayers + leavingLayers).forEach { $0.contentsScale = scale }
    }

    /// Resolves semantic and custom dynamic colours in this view's effective
    /// appearance before storing them in Core Animation's non-dynamic CGColor.
    private func resolvedTextColor() -> CGColor {
        var resolved = textColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = textColor.cgColor
        }
        return resolved
    }

    /// Updates existing model layers in place so an appearance switch does not
    /// cancel or restart an in-flight morph.
    private func updateTextColors() {
        let color = resolvedTextColor()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for textLayer in charLayers + leavingLayers {
            guard let attributed = textLayer.string as? NSAttributedString else { continue }
            let recolored = NSMutableAttributedString(attributedString: attributed)
            recolored.addAttribute(
                NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                value: color,
                range: NSRange(location: 0, length: recolored.length)
            )
            textLayer.string = recolored
        }

        layer?.sublayers?
            .compactMap { $0 as? CAShapeLayer }
            .filter { $0.name == MorphTransientLayer.name }
            .forEach { $0.fillColor = color }

        CATransaction.commit()
    }
}
