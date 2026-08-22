#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import QuartzCore

/// A single-line label that animates text changes by character or as a whole line.
///
/// Setting `text` (or calling `setText(_:animated:)`) diffs the old and new
/// strings for the ordinary character-scoped effects: characters present in
/// both fly to their new position, removed characters animate out, and added
/// characters animate in. A `WholeLineMorphEffect` instead replaces both
/// complete lines without diffing them.
public final class MorphingLabel: MorphView {

    // MARK: - Public API

    /// How far a glyph's raster tile deliberately extends past its typographic box.
    ///
    /// Most hosts leave a label's layer unclipped and need not care. A host that does clip —
    /// navigation chrome, for example — reserves this much room on each horizontal edge so the
    /// first and last raster tiles are not cut at the host boundary.
    public static let glyphRasterOverflow = GlyphRaster.padding

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

    /// The strategy used to animate a text change. See `MorphPreset` for the
    /// built-in effects, or implement `TextMorphEffect` for custom ones.
    public var effect: TextMorphEffect = CrossfadeEffect()

    public var timing = MorphTiming()

    /// An optional fade composed around the selected effect.
    ///
    /// `.traveling` gives every visual character position its own opacity
    /// carrier, so the fade combines with transforms and shape replacements
    /// instead of replacing or fighting their opacity animations.
    public var fadeStyle: MorphFadeStyle = .none

    /// Pulse count, depth, pulse/pause timing, and travel time for `.traveling`.
    /// Changes apply to the next text transition.
    public var fadeConfiguration = MorphFadeConfiguration()

    /// When enabled, character-scoped effects fly characters that exist in
    /// both the old and new text to their new position instead of animating
    /// them out and back in. Whole-line effects always replace the full line.
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

    /// Plays the configured fade over the settled text without changing it.
    ///
    /// This is the activity form of `fadeStyle`: a host can gently restate a label that is still
    /// current without manufacturing a text transition. An in-flight text morph keeps ownership
    /// of its glyph tree; asking for a standalone fade during one is intentionally ignored.
    public func playFade() {
        guard fadeStyle == .traveling,
              window != nil,
              !bounds.isEmpty,
              !charLayers.isEmpty,
              activeTextMorphGeneration == nil else { return }

        generation += 1
        let currentGeneration = generation
        flattenFadeCarriers()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, layer) in charLayers.enumerated() {
            installFadeCarrier(around: [layer], index: index, count: charLayers.count)
        }
        isPlayingStandaloneFade = true
        CATransaction.commit()

        let cleanupDelay = fadeSettleDuration(characterCount: charLayers.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.flattenFadeCarriers()
        }
    }

    /// Stops a fade started by `playFade()` and restores the settled text immediately.
    /// A fade participating in a real text morph remains owned by that morph.
    public func stopFade() {
        guard isPlayingStandaloneFade else { return }
        generation += 1
        flattenFadeCarriers()
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
    /// A text morph can consist entirely of retained moves or incoming glyphs,
    /// so outgoing-layer presence is not a reliable ownership signal.
    private var activeTextMorphGeneration: Int?
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
        flattenFadeCarriers()
        purgeTransientLayers()
        charLayers.forEach { $0.removeAllAnimations() }
        activeTextMorphGeneration = currentGeneration

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

        if let wholeLineEffect = effect as? WholeLineMorphEffect {
            morphByWholeLine(wholeLineEffect, oldLayers: oldLayers,
                             newSlots: newSlots, newLayers: &newLayers)
        } else if let replacementEffect = effect as? TextReplacementMorphEffect {
            morphByPosition(replacementEffect, oldSlots: oldSlots, oldLayers: oldLayers,
                            newSlots: newSlots, newLayers: &newLayers)
        } else {
            morphByDiff(oldSlots: oldSlots, oldLayers: oldLayers,
                        newSlots: newSlots, newLayers: &newLayers)
        }

        CATransaction.commit()

        charLayers = newLayers.compactMap { $0 }
        rememberLayout(of: displayedText)

        let staggeredUnitCount = effect is WholeLineMorphEffect
            ? 0
            : max(oldSlots.count, newSlots.count)
        let effectCleanupDelay = timing.duration
            + timing.stagger * CFTimeInterval(staggeredUnitCount)
            + effect.settleMargin
        let cleanupDelay = max(
            effectCleanupDelay,
            fadeSettleDuration(characterCount: max(oldSlots.count, newSlots.count))
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.leavingLayers.forEach { $0.removeFromSuperlayer() }
            self.leavingLayers.removeAll()
            self.flattenFadeCarriers()
            self.activeTextMorphGeneration = nil
        }
    }

    /// Whole-line flow: both complete glyph runs coexist and the effect receives
    /// them once. No character identity crosses the transition, even when the
    /// two strings contain matching letters.
    private func morphByWholeLine(_ wholeLineEffect: WholeLineMorphEffect,
                                  oldLayers: [GlyphLayer],
                                  newSlots: [CharacterSlot],
                                  newLayers: inout [GlyphLayer?]) {
        guard let container = morphLayer else { return }

        let incoming = newSlots.enumerated().map { index, slot in
            let layer = makeLayer(for: slot)
            container.addSublayer(layer)
            newLayers[index] = layer
            return layer
        }
        leavingLayers.append(contentsOf: oldLayers)

        let positionCount = max(oldLayers.count, incoming.count)
        for index in 0..<positionCount {
            var layers: [GlyphLayer] = []
            if oldLayers.indices.contains(index) { layers.append(oldLayers[index]) }
            if incoming.indices.contains(index) { layers.append(incoming[index]) }
            installFadeCarrier(around: layers, index: index, count: positionCount)
        }

        wholeLineEffect.animateLineTransition(
            from: oldLayers,
            to: incoming,
            in: container,
            context: context(index: 0, count: 1)
        )

        // Once animations are removed, the outgoing line's model state must
        // remain invisible until deferred cleanup detaches it.
        oldLayers.forEach { $0.opacity = 0 }
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
        let positionCount = max(oldSlots.count, newSlots.count)

        for move in diff.moves {
            let layer = oldLayers[move.from]
            let fromPosition = layer.position
            layer.apply(newSlots[move.to])
            newLayers[move.to] = layer
            installFadeCarrier(around: [layer], index: move.to, count: positionCount)
            if fromPosition != layer.position {
                effect.animateMove(layer, from: fromPosition, to: layer.position,
                                   context: context(index: move.to, count: newSlots.count))
            }
        }

        for index in diff.insertions {
            let charLayer = makeLayer(for: newSlots[index])
            morphLayer?.addSublayer(charLayer)
            newLayers[index] = charLayer
            installFadeCarrier(around: [charLayer], index: index, count: positionCount)
            effect.animateIn(charLayer, context: context(index: index, count: newSlots.count))
        }

        for index in diff.removals {
            let charLayer = oldLayers[index]
            leavingLayers.append(charLayer)
            installFadeCarrier(around: [charLayer], index: index, count: positionCount)
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
        let positionCount = max(oldSlots.count, newSlots.count)

        for index in 0..<newSlots.count {
            if index < pairCount {
                let oldLayer = oldLayers[index]
                if oldSlots[index].character == newSlots[index].character {
                    let fromPosition = oldLayer.position
                    oldLayer.apply(newSlots[index])
                    newLayers[index] = oldLayer
                    installFadeCarrier(around: [oldLayer], index: index,
                                       count: positionCount)
                    if fromPosition != oldLayer.position {
                        effect.animateMove(oldLayer, from: fromPosition, to: oldLayer.position,
                                           context: context(index: index, count: newSlots.count))
                    }
                } else {
                    let newLayer = makeLayer(for: newSlots[index])
                    container.addSublayer(newLayer)
                    newLayers[index] = newLayer
                    leavingLayers.append(oldLayer)
                    let transitionContainer = installFadeCarrier(
                        around: [oldLayer, newLayer],
                        index: index,
                        count: positionCount
                    ) ?? container
                    replacementEffect.animateReplace(from: oldLayer, to: newLayer,
                                                     in: transitionContainer,
                                                     context: context(index: index, count: newSlots.count))
                    oldLayer.opacity = 0
                }
            } else {
                let newLayer = makeLayer(for: newSlots[index])
                container.addSublayer(newLayer)
                newLayers[index] = newLayer
                installFadeCarrier(around: [newLayer], index: index, count: positionCount)
                effect.animateIn(newLayer, context: context(index: index, count: newSlots.count))
            }
        }

        for index in pairCount..<oldSlots.count {
            let oldLayer = oldLayers[index]
            leavingLayers.append(oldLayer)
            installFadeCarrier(around: [oldLayer], index: index, count: positionCount)
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
        activeTextMorphGeneration = nil
        (charLayers + leavingLayers).forEach { $0.removeFromSuperlayer() }
        leavingLayers.removeAll()
        removeFadeCarriers()
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
        resizeFadeCarriers()

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

    // MARK: - Traveling fade

    private enum FadeWaveDefaults {
        static let carrierName = "labelmorph.fade-carrier"
        static let animationKey = "morph.fade.traveling"
    }

    private var fadeCarriers: [CALayer] = []
    private var fadeCarriersByPosition: [Int: CALayer] = [:]
    private var isPlayingStandaloneFade = false

    /// Wraps one visual character position in a full-label carrier. Effects keep
    /// animating the glyphs themselves; the carrier supplies an independent
    /// multiplicative opacity envelope, so two animations never compete for the
    /// same key path. Replacement pairs share one carrier, which also lets a
    /// temporary Shape Morph layer inherit the same fade.
    @discardableResult
    private func installFadeCarrier(around layers: [GlyphLayer],
                                    index: Int,
                                    count: Int) -> CALayer? {
        guard fadeStyle == .traveling, !layers.isEmpty, let container = morphLayer else {
            return nil
        }

        if let carrier = fadeCarriersByPosition[index] {
            layers.forEach { carrier.addSublayer($0) }
            return carrier
        }

        let carrier = CALayer()
        carrier.name = FadeWaveDefaults.carrierName
        carrier.frame = container.bounds
        carrier.sublayerTransform = container.sublayerTransform
        carrier.actions = Self.disabledActions
        container.addSublayer(carrier)
        layers.forEach { carrier.addSublayer($0) }

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        let envelope = fadeEnvelope()
        animation.values = envelope.values
        animation.keyTimes = envelope.keyTimes
        animation.beginTime = CACurrentMediaTime() + fadeDelay(index: index, count: count)
        animation.duration = envelope.duration
        animation.timingFunctions = fadeTimingFunctions(for: envelope.values)
        animation.fillMode = .backwards
        animation.isRemovedOnCompletion = true
        carrier.add(animation, forKey: FadeWaveDefaults.animationKey)

        fadeCarriers.append(carrier)
        fadeCarriersByPosition[index] = carrier
        return carrier
    }

    private func fadeDelay(index: Int, count: Int) -> CFTimeInterval {
        guard count > 1 else { return 0 }
        return normalizedFadeTravelDuration
            * CFTimeInterval(index) / CFTimeInterval(count - 1)
    }

    private func fadeSettleDuration(characterCount: Int) -> CFTimeInterval {
        guard fadeStyle == .traveling, characterCount > 0 else { return 0 }
        return fadeEnvelopeDuration
            + (characterCount > 1 ? normalizedFadeTravelDuration : 0)
    }

    /// Builds one complete pulse train. A zero pause inserts no duplicate
    /// full-opacity keyframe, so consecutive pulses share an exact boundary.
    /// There is never an invisible pause tail after the final pulse.
    private func fadeEnvelope() -> (values: [NSNumber], keyTimes: [NSNumber], duration: CFTimeInterval) {
        let duration = fadeEnvelopeDuration
        var values: [NSNumber] = [1]
        var times: [CFTimeInterval] = [0]

        for pulseIndex in 0..<normalizedFadePulseCount {
            let pulseStart = CFTimeInterval(pulseIndex)
                * (normalizedFadePulseDuration + normalizedFadePauseDuration)
            values.append(NSNumber(value: normalizedFadeMinimumOpacity))
            times.append(pulseStart + normalizedFadePulseDuration / 2)
            values.append(1)
            times.append(pulseStart + normalizedFadePulseDuration)

            if pulseIndex < normalizedFadePulseCount - 1,
               normalizedFadePauseDuration > 0 {
                values.append(1)
                times.append(pulseStart + normalizedFadePulseDuration + normalizedFadePauseDuration)
            }
        }

        return (
            values,
            times.map { NSNumber(value: $0 / duration) },
            duration
        )
    }

    private var fadeEnvelopeDuration: CFTimeInterval {
        normalizedFadePulseDuration * CFTimeInterval(normalizedFadePulseCount)
            + normalizedFadePauseDuration * CFTimeInterval(normalizedFadePulseCount - 1)
    }

    /// Ease away from full opacity and into the shaded trough. At a zero-pause
    /// pulse boundary this avoids the double ease-in/out flattening that reads
    /// as a pause even when no hold keyframe exists.
    private func fadeTimingFunctions(for values: [NSNumber]) -> [CAMediaTimingFunction] {
        zip(values, values.dropFirst()).map { from, to in
            if from == to {
                return CAMediaTimingFunction(name: .linear)
            }
            return CAMediaTimingFunction(name: to.doubleValue < from.doubleValue ? .easeOut : .easeIn)
        }
    }

    private var normalizedFadePulseCount: Int {
        max(1, fadeConfiguration.pulseCount)
    }

    private var normalizedFadeMinimumOpacity: Float {
        min(1, max(0, fadeConfiguration.minimumOpacity))
    }

    private var normalizedFadePulseDuration: CFTimeInterval {
        max(0.01, fadeConfiguration.pulseDuration)
    }

    private var normalizedFadePauseDuration: CFTimeInterval {
        max(0, fadeConfiguration.pauseDuration)
    }

    private var normalizedFadeTravelDuration: CFTimeInterval {
        max(0, fadeConfiguration.travelDuration)
    }

    private func resizeFadeCarriers() {
        guard let bounds = morphLayer?.bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeCarriers.forEach { $0.frame = bounds }
        CATransaction.commit()
    }

    /// Returns the settled glyph run to the ordinary direct layer tree, then
    /// removes outgoing glyphs and temporary replacement shapes with the
    /// carriers that held them.
    private func flattenFadeCarriers() {
        guard let container = morphLayer, !fadeCarriers.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in charLayers where layer.superlayer?.name == FadeWaveDefaults.carrierName {
            container.addSublayer(layer)
        }
        fadeCarriers.forEach { $0.removeFromSuperlayer() }
        fadeCarriers.removeAll()
        fadeCarriersByPosition.removeAll()
        isPlayingStandaloneFade = false
        CATransaction.commit()
    }

    private func removeFadeCarriers() {
        fadeCarriers.forEach { $0.removeFromSuperlayer() }
        fadeCarriers.removeAll()
        fadeCarriersByPosition.removeAll()
        isPlayingStandaloneFade = false
    }

    /// Removes temporary overlay layers effects may have added (see
    /// `MorphTransientLayer`).
    private func purgeTransientLayers() {
        descendantLayers(in: morphLayer)
            .filter { $0.name == MorphTransientLayer.name }
            .forEach { $0.removeFromSuperlayer() }
    }

    private func descendantLayers(in root: CALayer?) -> [CALayer] {
        guard let children = root?.sublayers else { return [] }
        return children + children.flatMap { descendantLayers(in: $0) }
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

        descendantLayers(in: morphLayer)
            .compactMap { $0 as? CAShapeLayer }
            .filter { $0.name == MorphTransientLayer.name }
            .forEach { $0.fillColor = color }

        CATransaction.commit()
    }
}
