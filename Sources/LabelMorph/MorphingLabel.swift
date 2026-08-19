#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import QuartzCore

/// A single-line label that animates text changes character by character.
///
/// Setting `text` (or calling `setText(_:animated:)`) diffs the old and new
/// strings: characters present in both fly to their new position, removed
/// characters animate out, and added characters animate in — all according to
/// the current `effect` and `timing`.
public final class MorphingLabel: MorphView {

    // MARK: - Public API

    // Each of these three rebuilds or repaints every glyph layer, and a host that
    // reconfigures a reused view restates all of them on every pass. Assigning the value
    // already in force must therefore cost nothing.

    public var font: MorphFont = .systemFont(ofSize: 48, weight: .semibold) {
        didSet {
            guard font != oldValue else { return }
            truncationCache = nil
            // A host configures an empty label before giving it its first title. Rebuilding here
            // tears down and lays out an empty layer tree once per property, only for `setText`
            // to build the real glyphs a moment later. Keep the final configuration and let the
            // first non-empty text perform the one useful build.
            guard hasPresentedContent else {
                invalidateIntrinsicContentSize()
                return
            }
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
            guard hasPresentedContent else { return }
            rebuild()
        }
    }

    public var textColor: MorphColor = .morphLabelColor {
        didSet {
            guard textColor != oldValue else { return }
            updateTextColors()
        }
    }

    public var alignment: NSTextAlignment = .center {
        didSet {
            guard alignment != oldValue else { return }
            guard hasPresentedContent else { return }
            relayoutCurrent()
        }
    }

    /// The colour glyphs are smoothed against.
    ///
    /// Font smoothing is the stem-darkening pass macOS applies below 2x, and it
    /// is most of what separates legible text from grey text on a 1x display. It
    /// only runs against an opaque ground, and it dilates dark ink on a light one
    /// while thinning light ink on a dark one — so the ground is not a detail the
    /// package can guess. A host drawing on a known surface says so here.
    ///
    /// Left `nil`, the ink's own luminance decides the polarity, which is right
    /// far more often than not and wrong only in the gamma.
    public var rasterizationBackground: MorphColor? {
        didSet {
            guard rasterizationBackground != oldValue else { return }
            let background = rasterizationBackground?.cgColor
            (charLayers + leavingLayers).forEach { $0.rasterBackground = background }
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

    public override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
#if canImport(AppKit)
        wantsLayer = true
        layerUsesCoreImageFilters = true
#else
        registerForTraitChanges([UITraitDisplayScale.self]) {
            (label: MorphingLabel, _) in
            label.updateForBackingScale()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (label: MorphingLabel, _) in
            label.updateTextColors()
        }
#endif
        // Perspective for 3D effects such as flip.
        var transform = CATransform3DIdentity
        transform.m34 = -1.0 / 600.0
        morphLayer?.sublayerTransform = transform
    }

    // MARK: - Platform view

    public override var intrinsicContentSize: CGSize {
        let size = CharacterLayout.measure(storedText, font: font)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

#if canImport(AppKit)
    public override func layout() {
        super.layout()
        if !isResolvingMorphLayout {
            relayoutCurrent()
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateForBackingScale()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateForBackingScale()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTextColors()
    }
#elseif canImport(UIKit)
    public override func layoutSubviews() {
        super.layoutSubviews()
        if !isResolvingMorphLayout {
            relayoutCurrent()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        updateForBackingScale()
    }
#endif

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

    /// Where the visible glyphs' ink actually sits, in the label's coordinates.
    ///
    /// Not the glyph layers' frames, which are raster tiles: padded so overhanging
    /// ink is not clipped, and snapped to the display's pixel grid. A caller
    /// asking whether a line fits, or aligning something to its last character,
    /// means these — the boxes Core Text laid the glyphs out in.
    public var glyphInkFrames: [CGRect] {
        charLayers.compactMap { $0.slot?.inkFrame }
    }
    private var charLayers: [GlyphLayer] = []
    private var leavingLayers: [GlyphLayer] = []
    private var generation = 0
    private var isResolvingMorphLayout = false

    /// AppKit creates a backing layer only after `wantsLayer`; UIKit always has one. Keeping the
    /// optional shape here lets the shared engine retain AppKit's lifecycle without forking all
    /// layer management for UIKit.
    private var morphLayer: CALayer? { layer }

    /// Empty pre-presentation configuration has no glyph tree to rebuild. Include outgoing
    /// layers so clearing a label during an animation still lets a later presentation change
    /// settle the pixels that are genuinely on screen.
    private var hasPresentedContent: Bool {
        !storedText.isEmpty || !charLayers.isEmpty || !leavingLayers.isEmpty
    }

    /// The geometry the current glyph slots were resolved against.
    ///
    /// A leading-aligned line does not move when only its available width changes. Width can
    /// still change the string tail truncation chooses, so the displayed text is part of the
    /// snapshot; once that agrees, repeating Core Text layout and invalidating every glyph
    /// raster is work with no visible result. Centered and trailing lines continue to include
    /// width because their origin genuinely moves with it.
    private var layoutSnapshot: LayoutSnapshot?

    private struct LayoutSnapshot {
        let displayedText: String
        let bounds: CGRect
        let alignment: NSTextAlignment
        let scale: CGFloat
    }

    /// The pixel grid the line is currently laid out against. Slots are snapped to
    /// it, so it is a layout input rather than a rendering detail — see
    /// `CharacterLayout.allSlots`.
    private var backingScale: CGFloat {
#if canImport(AppKit)
        window?.backingScaleFactor ?? 2
#else
        window?.screen.scale ?? traitCollection.displayScale
#endif
    }

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
        let originBefore = convert(CGPoint.zero, to: nil)
        isResolvingMorphLayout = true
        invalidateIntrinsicContentSize()
        window?.layoutIfNeeded()
        isResolvingMorphLayout = false

        // Auto Layout may have shifted the label itself (re-centering after a
        // width change). Shift the old characters' model frames to keep their
        // on-screen position, so travel to the new layout happens inside the
        // morph animations — otherwise the whole line jumps first and morphs
        // second.
        // Snapped to the pixel grid the slots were laid out on: the characters
        // being shifted are already sitting on it, and a fractional shift would
        // take every one of them off it for the length of the morph.
        let originAfter = convert(CGPoint.zero, to: nil)
        let scale = backingScale
        let shift = CGPoint(x: ((originBefore.x - originAfter.x) * scale).rounded() / scale,
                            y: ((originBefore.y - originAfter.y) * scale).rounded() / scale)
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
        let displayedText = displayText(in: bounds)
        let newSlots = CharacterLayout.visibleSlots(
            for: displayedText, font: font, bounds: bounds, alignment: alignment,
            scale: backingScale
        )
        visibleSlots = newSlots

        var newLayers = [GlyphLayer?](repeating: nil, count: newSlots.count)

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
        rememberLayout(of: displayedText)

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
    private func morphByDiff(oldSlots: [CharacterSlot], oldLayers: [GlyphLayer],
                             newSlots: [CharacterSlot], newLayers: inout [GlyphLayer?]) {
        let diff = CharacterDiff.compute(
            old: oldSlots.map(\.character),
            new: newSlots.map(\.character),
            matchDistanceLimit: reusesMatchingCharacters ? nil : 0
        )

        for move in diff.moves {
            let layer = oldLayers[move.from]
            let fromPosition = layer.position
            layer.apply(newSlots[move.to])
            newLayers[move.to] = layer
            if fromPosition != layer.position {
                effect.animateMove(layer, from: fromPosition, to: layer.position,
                                   context: context(index: move.to, count: newSlots.count))
            }
        }

        for index in diff.insertions {
            let charLayer = makeLayer(for: newSlots[index])
            morphLayer?.addSublayer(charLayer)
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
                                 oldSlots: [CharacterSlot], oldLayers: [GlyphLayer],
                                 newSlots: [CharacterSlot], newLayers: inout [GlyphLayer?]) {
        guard let container = morphLayer else { return }
        let pairCount = min(oldSlots.count, newSlots.count)

        for index in 0..<newSlots.count {
            if index < pairCount {
                let oldLayer = oldLayers[index]
                if oldSlots[index].character == newSlots[index].character {
                    let fromPosition = oldLayer.position
                    oldLayer.apply(newSlots[index])
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

    private func makeLayer(for slot: CharacterSlot) -> GlyphLayer {
        let ink = resolvedTextColor()
        let charLayer = GlyphLayer()
        // `string` is not what gets drawn — `GlyphLayer.display` replaces that
        // wholesale — but it stays authoritative for what the layer *is*, which
        // `GlyphMorphEffect` and `displayedCharacters` both read.
        charLayer.string = NSAttributedString(
            string: slot.character,
            attributes: CharacterLayout.textAttributes(font: font, color: ink)
        )
        charLayer.glyphFont = font
        charLayer.ink = ink
        charLayer.rasterBackground = rasterizationBackground?.cgColor
        charLayer.contentsScale = backingScale
        charLayer.actions = Self.disabledActions
        charLayer.apply(slot)
        return charLayer
    }

    /// Tears everything down and lays the current text out from scratch.
    private func rebuild() {
        generation += 1
        (charLayers + leavingLayers).forEach { $0.removeFromSuperlayer() }
        leavingLayers.removeAll()
        purgeTransientLayers()

        let displayedText = displayText(in: bounds)
        visibleSlots = CharacterLayout.visibleSlots(
            for: displayedText, font: font, bounds: bounds, alignment: alignment,
            scale: backingScale
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        charLayers = visibleSlots.map { slot in
            let charLayer = makeLayer(for: slot)
            morphLayer?.addSublayer(charLayer)
            return charLayer
        }
        CATransaction.commit()
        rememberLayout(of: displayedText)

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
        let displayedText = displayText(in: bounds)
        guard needsLayout(for: displayedText) else { return }

        let slots = CharacterLayout.visibleSlots(
            for: displayedText, font: font, bounds: bounds, alignment: alignment,
            scale: backingScale
        )
        let commonPrefixCount = zip(slots, visibleSlots)
            .prefix { $0.character == $1.character }
            .count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<commonPrefixCount {
            charLayers[index].apply(slots[index])
        }

        charLayers.dropFirst(commonPrefixCount).forEach { $0.removeFromSuperlayer() }
        let replacementLayers = slots.dropFirst(commonPrefixCount).map { slot in
            let charLayer = makeLayer(for: slot)
            morphLayer?.addSublayer(charLayer)
            return charLayer
        }
        charLayers = Array(charLayers.prefix(commonPrefixCount)) + replacementLayers
        visibleSlots = slots
        CATransaction.commit()
        rememberLayout(of: displayedText)
    }

    /// Whether the current glyph slots can still describe this presentation exactly.
    private func needsLayout(for displayedText: String) -> Bool {
        guard let layoutSnapshot,
              layoutSnapshot.displayedText == displayedText,
              layoutSnapshot.alignment == alignment,
              layoutSnapshot.scale == backingScale else {
            return true
        }

        switch alignment {
        case .center, .right:
            return layoutSnapshot.bounds != bounds
        default:
            return layoutSnapshot.bounds.origin != bounds.origin
                || layoutSnapshot.bounds.height != bounds.height
        }
    }

    private func rememberLayout(of displayedText: String) {
        let scale = backingScale
        layoutSnapshot = LayoutSnapshot(
            displayedText: displayedText,
            bounds: bounds,
            alignment: alignment,
            scale: scale
        )
        // Every caller has just laid out or rebuilt the glyph rasters at this scale. Remember
        // that fact here, at the same boundary as the geometry snapshot, so attaching a label
        // that was prepared off-window to a display with the same scale does not rebuild an
        // identical layer tree. A genuinely different display scale still crosses the guard in
        // `updateForBackingScale` and performs the required rerasterization.
        lastRasterizedScale = scale
    }

    /// Removes temporary overlay layers effects may have added (see
    /// `MorphTransientLayer`).
    private func purgeTransientLayers() {
        morphLayer?.sublayers?
            .filter { $0.name == MorphTransientLayer.name }
            .forEach { $0.removeFromSuperlayer() }
    }

    /// Re-lays out and re-rasterises the line for the display it is now on.
    ///
    /// A retag of `contentsScale` was enough while glyphs were drawn by
    /// `CATextLayer`, which re-renders itself when its scale changes. A bitmap
    /// does not: dragging the window from a Retina screen to a 1x one would leave
    /// every glyph a 2x tile for the compositor to halve, which is softer than
    /// what it replaced. The slots are scale-dependent too — they are snapped to
    /// the pixel grid — so this is a full rebuild rather than a repaint.
    private func updateForBackingScale() {
        guard lastRasterizedScale != backingScale else { return }
        lastRasterizedScale = backingScale
        rebuild()
    }

    private var lastRasterizedScale: CGFloat?

    /// Resolves semantic and custom dynamic colours in this view's effective
    /// appearance before storing them in Core Animation's non-dynamic CGColor.
    private func resolvedTextColor() -> CGColor {
#if canImport(AppKit)
        var resolved = textColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = textColor.cgColor
        }
        return resolved
#else
        textColor.resolvedColor(with: traitCollection).cgColor
#endif
    }

    /// Updates existing model layers in place so an appearance switch does not
    /// cancel or restart an in-flight morph.
    private func updateTextColors() {
        let color = resolvedTextColor()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for textLayer in charLayers + leavingLayers {
            // The tile is re-tinted from the cached mask rather than rasterised
            // again, so a live theme switch costs a blit per glyph.
            textLayer.ink = color
            guard let attributed = textLayer.string as? NSAttributedString else { continue }
            let recolored = NSMutableAttributedString(attributedString: attributed)
            recolored.addAttribute(
                NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                value: color,
                range: NSRange(location: 0, length: recolored.length)
            )
            textLayer.string = recolored
        }

        morphLayer?.sublayers?
            .compactMap { $0 as? CAShapeLayer }
            .filter { $0.name == MorphTransientLayer.name }
            .forEach { $0.fillColor = color }

        CATransaction.commit()
    }
}
