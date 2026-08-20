import AppKit
import QuartzCore
import LabelMorph

final class ShowcaseViewController: NSViewController {

    static let initialContentSize = NSSize(width: 980, height: 800)
    static let minimumContentSize = NSSize(width: 760, height: 540)

    // MARK: - Views

    private let label = MorphingLabel()

    private let presetPopup = NSPopUpButton()
    private let easingPopup = NSPopUpButton()

    private lazy var durationSlider = NSSlider(value: 0.45, minValue: 0.05, maxValue: 2.0,
                                               target: self, action: #selector(controlsChanged))
    private lazy var staggerSlider = NSSlider(value: 0.025, minValue: 0, maxValue: 0.15,
                                              target: self, action: #selector(controlsChanged))
    private lazy var intensitySlider = NSSlider(value: 0.6, minValue: 0, maxValue: 1,
                                                target: self, action: #selector(controlsChanged))
    private lazy var fontSlider = NSSlider(value: 44, minValue: 16, maxValue: 96,
                                           target: self, action: #selector(fontChanged))
    private lazy var fadePulseSlider = NSSlider(value: 2, minValue: 1, maxValue: 5,
                                                target: self, action: #selector(controlsChanged))
    private lazy var fadeDepthSlider = NSSlider(value: 0.86, minValue: 0.1, maxValue: 0.95,
                                                target: self, action: #selector(controlsChanged))
    private lazy var fadePulseDurationSlider = NSSlider(value: 0.28, minValue: 0.1, maxValue: 0.8,
                                                        target: self, action: #selector(controlsChanged))
    private lazy var fadePauseSlider = NSSlider(value: 0.12, minValue: 0, maxValue: 0.8,
                                                target: self, action: #selector(controlsChanged))
    private lazy var fadeTravelSlider = NSSlider(value: 0.42, minValue: 0, maxValue: 1.0,
                                                 target: self, action: #selector(controlsChanged))

    private let durationValue = NSTextField(labelWithString: "")
    private let staggerValue = NSTextField(labelWithString: "")
    private let intensityValue = NSTextField(labelWithString: "")
    private let fontValue = NSTextField(labelWithString: "")
    private let fadePulseValue = NSTextField(labelWithString: "")
    private let fadeDepthValue = NSTextField(labelWithString: "")
    private let fadePulseDurationValue = NSTextField(labelWithString: "")
    private let fadePauseValue = NSTextField(labelWithString: "")
    private let fadeTravelValue = NSTextField(labelWithString: "")

    private let durationCaption = ShowcaseViewController.captionLabel("")
    private let staggerCaption = ShowcaseViewController.captionLabel("")
    private let intensityCaption = ShowcaseViewController.captionLabel("")

    private let textField = NSTextField(string: "Hello, World!")

    private lazy var reuseCheckbox = NSButton(checkboxWithTitle: "Reuse matching characters",
                                              target: self, action: #selector(controlsChanged))
    private lazy var fadeCheckbox = NSButton(checkboxWithTitle: "Traveling fade",
                                             target: self, action: #selector(controlsChanged))
    private lazy var autoCheckbox = NSButton(checkboxWithTitle: "Auto-cycle phrases every 2 s",
                                             target: self, action: #selector(autoToggled))

    // MARK: - State

    private var autoTimer: Timer?
    private var phraseIndex = 0

    private let phrases = [
        "Hello, World!",
        "LabelMorph",
        "Thirteen ways to morph",
        "The quick brown fox",
        "jumps over the lazy dog",
        "0123456789",
        "9876543210",
        "Morph all the things",
        "Goodbye!",
    ]

    private let easingOptions: [(name: String, function: CAMediaTimingFunctionName)] = [
        ("Ease In-Out", .easeInEaseOut),
        ("Ease Out", .easeOut),
        ("Ease In", .easeIn),
        ("Linear", .linear),
    ]

    private var currentPreset: MorphPreset {
        guard let rawValue = presetPopup.selectedItem?.representedObject as? String,
              let preset = MorphPreset(rawValue: rawValue) else {
            return .crossfade
        }
        return preset
    }

    deinit {
        autoTimer?.invalidate()
    }

    // MARK: - View construction

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.initialContentSize))

        let preview = NSView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(preview)

        label.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(label)

        preview.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(nextPhrase)))

        let hint = NSTextField(labelWithString: "Click anywhere to morph to the next phrase")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(hint)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        let panel = NSStackView()
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 14
        panel.translatesAutoresizingMaskIntoConstraints = false

        let panelDocument = ShowcaseFlippedView()
        panelDocument.translatesAutoresizingMaskIntoConstraints = false
        panelDocument.addSubview(panel)

        let panelScroll = NSScrollView()
        panelScroll.translatesAutoresizingMaskIntoConstraints = false
        panelScroll.hasVerticalScroller = true
        panelScroll.autohidesScrollers = true
        panelScroll.drawsBackground = false
        panelScroll.borderType = .noBorder
        panelScroll.documentView = panelDocument
        root.addSubview(panelScroll)

        func addRow(_ row: NSView) {
            row.translatesAutoresizingMaskIntoConstraints = false
            panel.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        }

        addRow(labeledRow("Effect", control: presetPopup))
        addRow(labeledRow("Duration", control: durationSlider, value: durationValue,
                          caption: durationCaption))
        addRow(labeledRow("Stagger", control: staggerSlider, value: staggerValue,
                          caption: staggerCaption))
        addRow(labeledRow("Intensity", control: intensitySlider, value: intensityValue,
                          caption: intensityCaption))
        easingPopup.toolTip = "Timing curve for regular animations. Bounce and Drop use spring physics and ignore it."
        addRow(labeledRow("Easing", control: easingPopup))
        addRow(labeledRow("Font size", control: fontSlider, value: fontValue))

        let separator = NSBox()
        separator.boxType = .separator
        addRow(separator)

        let morphButton = NSButton(title: "Morph", target: self, action: #selector(morphToFieldText))
        morphButton.keyEquivalent = "\r"
        textField.placeholderString = "Type text and press Return"
        let textRow = NSStackView(views: [textField, morphButton])
        textRow.orientation = .horizontal
        textRow.spacing = 8
        textField.setContentHuggingPriority(.init(1), for: .horizontal)
        addRow(labeledRow("Custom text", control: textRow))

        let nextButton = NSButton(title: "Next Phrase", target: self, action: #selector(nextPhrase))
        addRow(nextButton)
        addRow(reuseCheckbox)
        fadeCheckbox.toolTip = "Pass a soft opacity wave through the glyphs while the selected effect runs."
        addRow(labeledRow("Fade overlay", control: fadeControls()))
        addRow(autoCheckbox)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 760),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 540),

            preview.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            preview.topAnchor.constraint(equalTo: root.topAnchor),
            preview.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            preview.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),

            divider.leadingAnchor.constraint(equalTo: preview.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            panelScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            panelScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            panelScroll.topAnchor.constraint(equalTo: root.topAnchor),
            panelScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            panelDocument.topAnchor.constraint(equalTo: panelScroll.contentView.topAnchor),
            panelDocument.leadingAnchor.constraint(equalTo: panelScroll.contentView.leadingAnchor),
            panelDocument.trailingAnchor.constraint(equalTo: panelScroll.contentView.trailingAnchor),

            panel.leadingAnchor.constraint(equalTo: panelDocument.leadingAnchor, constant: 20),
            panel.trailingAnchor.constraint(equalTo: panelDocument.trailingAnchor, constant: -20),
            panel.topAnchor.constraint(equalTo: panelDocument.topAnchor, constant: 20),
            panel.bottomAnchor.constraint(equalTo: panelDocument.bottomAnchor, constant: -20),
            panel.widthAnchor.constraint(equalToConstant: 280),

            label.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: preview.centerYAnchor),

            hint.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -16),
        ])

        self.view = root
        preferredContentSize = Self.initialContentSize
    }

    private static func captionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .tertiaryLabelColor
        label.isSelectable = false
        return label
    }

    private func labeledRow(_ title: String, control: NSView, value: NSTextField? = nil,
                            caption: NSTextField? = nil) -> NSView {
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let header: NSView
        if let value {
            value.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            value.textColor = .secondaryLabelColor
            value.alignment = .right
            let headerStack = NSStackView(views: [titleLabel, value])
            headerStack.orientation = .horizontal
            titleLabel.setContentHuggingPriority(.init(1), for: .horizontal)
            header = headerStack
        } else {
            header = titleLabel
        }

        var views: [NSView] = [header, control]
        if let caption { views.append(caption) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func fadeControls() -> NSView {
        fadePulseSlider.numberOfTickMarks = 5
        fadePulseSlider.allowsTickMarkValuesOnly = true
        fadePauseSlider.toolTip = "Full-opacity pause between pulses. Zero runs them back-to-back."

        let stack = NSStackView(views: [
            fadeCheckbox,
            compactSliderRow("Pulses", slider: fadePulseSlider, value: fadePulseValue),
            compactSliderRow("Depth", slider: fadeDepthSlider, value: fadeDepthValue),
            compactSliderRow("Pulse", slider: fadePulseDurationSlider, value: fadePulseDurationValue),
            compactSliderRow("Pause", slider: fadePauseSlider, value: fadePauseValue),
            compactSliderRow("Travel", slider: fadeTravelSlider, value: fadeTravelValue),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return stack
    }

    private func compactSliderRow(_ title: String, slider: NSSlider, value: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 10)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .right
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        value.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.translatesAutoresizingMaskIntoConstraints = false
        value.widthAnchor.constraint(equalToConstant: 43).isActive = true

        let row = NSStackView(views: [titleLabel, slider, value])
        row.orientation = .horizontal
        row.spacing = 6
        slider.setContentHuggingPriority(.init(1), for: .horizontal)
        return row
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        populatePresetPopup()
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        easingPopup.addItems(withTitles: easingOptions.map(\.name))
        easingPopup.target = self
        easingPopup.action = #selector(controlsChanged)

        reuseCheckbox.state = .on

        textField.target = self
        textField.action = #selector(morphToFieldText)

        label.font = .systemFont(ofSize: CGFloat(fontSlider.doubleValue), weight: .semibold)
        label.setText(phrases[0], animated: false)

        loadRecommendedTiming(for: currentPreset)
        applySettings()

        // Launch arguments for scripted demos include -preset <rawValue>,
        // -fade YES, -fadePause <seconds>, and -autoplay YES.
        let defaults = UserDefaults.standard
        if let presetName = defaults.string(forKey: "preset"),
           let preset = MorphPreset(rawValue: presetName) {
            selectPreset(preset)
            loadRecommendedTiming(for: currentPreset)
            applySettings()
        }
        if defaults.object(forKey: "fadePause") != nil {
            fadePauseSlider.doubleValue = defaults.double(forKey: "fadePause")
            updateValueLabels()
            applySettings()
        }
        if defaults.bool(forKey: "autoplay") {
            autoCheckbox.state = .on
            autoToggled()
        }
        if defaults.bool(forKey: "fade") {
            fadeCheckbox.state = .on
            applySettings()
        }
    }

    // MARK: - Actions

    @objc private func presetChanged() {
        loadRecommendedTiming(for: currentPreset)
        applySettings()
        nextPhrase()
    }

    @objc private func controlsChanged() {
        updateValueLabels()
        applySettings()
    }

    @objc private func fontChanged() {
        updateValueLabels()
        label.font = .systemFont(ofSize: CGFloat(fontSlider.doubleValue), weight: .semibold)
    }

    @objc private func morphToFieldText() {
        let newText = textField.stringValue
        guard !newText.isEmpty else { return }
        label.setText(newText)
    }

    @objc private func nextPhrase() {
        phraseIndex = (phraseIndex + 1) % phrases.count
        label.setText(phrases[phraseIndex])
    }

    /// Starts the same transition as the visible Next Phrase control. Used by
    /// the Showcase's opt-in screenshot launch hook so visual evidence stays
    /// on the real app path.
    func beginScriptedMorph() {
        nextPhrase()
    }

    /// Draws the label's in-flight Core Animation presentation into a window
    /// capture after AppKit has drawn the surrounding controls' model state.
    func drawAnimatedPreview(in context: CGContext, relativeTo contentView: NSView) {
        guard let presentationLayer = label.layer?.presentation() else { return }
        let labelRect = label.convert(label.bounds, to: contentView)

        clearAnimatedPreview(in: context, relativeTo: contentView)

        context.saveGState()
        context.translateBy(x: labelRect.minX, y: labelRect.minY)
        presentationLayer.render(in: context)
        context.restoreGState()
    }

    /// Removes the model-layer label from a cached AppKit backdrop. The live
    /// presentation layer is composited over this clean preview in each frame.
    func clearAnimatedPreview(in context: CGContext, relativeTo contentView: NSView) {
        let labelRect = label.convert(label.bounds, to: contentView)
        context.saveGState()
        context.setBlendMode(.copy)
        context.setFillColor((view.window?.backgroundColor ?? .windowBackgroundColor).cgColor)
        context.fill(labelRect)
        context.restoreGState()
    }

    @objc private func autoToggled() {
        autoTimer?.invalidate()
        autoTimer = nil
        guard autoCheckbox.state == .on else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.nextPhrase()
        }
    }

    // MARK: - Settings

    private func loadRecommendedTiming(for preset: MorphPreset) {
        let timing = preset.recommendedTiming
        durationSlider.doubleValue = timing.duration
        staggerSlider.doubleValue = timing.stagger
        intensityCaption.stringValue = preset.intensityDescription
        updateValueLabels()
    }

    private func applySettings() {
        let easing = easingOptions[max(0, easingPopup.indexOfSelectedItem)].function
        label.timing = MorphTiming(duration: durationSlider.doubleValue,
                                   stagger: staggerSlider.doubleValue,
                                   timingFunction: CAMediaTimingFunction(name: easing))
        label.effect = currentPreset.makeEffect(intensity: intensitySlider.doubleValue)
        label.fadeStyle = fadeCheckbox.state == .on ? .traveling : .none
        label.fadeConfiguration = MorphFadeConfiguration(
            pulseCount: Int(fadePulseSlider.doubleValue.rounded()),
            minimumOpacity: Float(1 - fadeDepthSlider.doubleValue),
            pulseDuration: fadePulseDurationSlider.doubleValue,
            pauseDuration: fadePauseSlider.doubleValue,
            travelDuration: fadeTravelSlider.doubleValue
        )
        label.reusesMatchingCharacters = reuseCheckbox.state == .on

        let usesFade = fadeCheckbox.state == .on
        [fadePulseSlider, fadeDepthSlider, fadePulseDurationSlider, fadePauseSlider, fadeTravelSlider]
            .forEach { $0.isEnabled = usesFade }

        let usesWholeLine = label.effect is WholeLineMorphEffect
        staggerSlider.isEnabled = !usesWholeLine
        reuseCheckbox.isEnabled = !usesWholeLine
        durationCaption.stringValue = usesWholeLine
            ? "Animation time for the complete line handoff."
            : "Animation time for a single character — not the whole morph. Spring effects (Bounce, Drop) settle a little later."
        staggerCaption.stringValue = usesWholeLine
            ? "Not used: the complete line moves in lockstep without a character cascade."
            : "Extra start delay per character, creating the cascade. Whole morph ≈ duration + stagger × (characters − 1)."
        reuseCheckbox.toolTip = usesWholeLine
            ? "Whole-line effects replace both complete lines, so matching characters are not reused."
            : nil
    }

    private func updateValueLabels() {
        durationValue.stringValue = String(format: "%.2f s", durationSlider.doubleValue)
        staggerValue.stringValue = String(format: "%.3f s", staggerSlider.doubleValue)
        intensityValue.stringValue = String(format: "%.2f", intensitySlider.doubleValue)
        fontValue.stringValue = String(format: "%.0f pt", fontSlider.doubleValue)
        fadePulseValue.stringValue = String(format: "%.0f×", fadePulseSlider.doubleValue.rounded())
        fadeDepthValue.stringValue = String(format: "%.0f%%", fadeDepthSlider.doubleValue * 100)
        fadePulseDurationValue.stringValue = String(format: "%.2fs", fadePulseDurationSlider.doubleValue)
        fadePauseValue.stringValue = String(format: "%.2fs", fadePauseSlider.doubleValue)
        fadeTravelValue.stringValue = String(format: "%.2fs", fadeTravelSlider.doubleValue)
    }

    private func populatePresetPopup() {
        guard let menu = presetPopup.menu else { return }
        menu.removeAllItems()

        let singleCharacter = MorphPreset.allCases.filter { $0.scope == .singleCharacter }
        let fullRow = MorphPreset.allCases.filter { $0.scope == .wholeLine }
        addPresetSection("Single Character", presets: singleCharacter, to: menu)
        menu.addItem(.separator())
        addPresetSection("Full Row", presets: fullRow, to: menu)
        selectPreset(singleCharacter.first ?? .crossfade)
    }

    private func addPresetSection(_ title: String, presets: [MorphPreset], to menu: NSMenu) {
        let header = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for preset in presets {
            let item = NSMenuItem(title: preset.displayName, action: nil, keyEquivalent: "")
            item.representedObject = preset.rawValue
            menu.addItem(item)
        }
    }

    private func selectPreset(_ preset: MorphPreset) {
        guard let index = presetPopup.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == preset.rawValue
        }) else { return }
        presetPopup.selectItem(at: index)
    }
}

/// Keeps a scrollable control document pinned to its visual top as the window
/// becomes shorter than the complete settings panel.
private final class ShowcaseFlippedView: NSView {
    override var isFlipped: Bool { true }
}
