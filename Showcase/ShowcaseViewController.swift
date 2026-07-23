import AppKit
import QuartzCore
import LabelMorph

final class ShowcaseViewController: NSViewController {

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

    private let durationValue = NSTextField(labelWithString: "")
    private let staggerValue = NSTextField(labelWithString: "")
    private let intensityValue = NSTextField(labelWithString: "")
    private let fontValue = NSTextField(labelWithString: "")

    private let intensityCaption = ShowcaseViewController.captionLabel("")

    private let textField = NSTextField(string: "Hello, World!")

    private lazy var reuseCheckbox = NSButton(checkboxWithTitle: "Reuse matching characters",
                                              target: self, action: #selector(controlsChanged))
    private lazy var autoCheckbox = NSButton(checkboxWithTitle: "Auto-cycle phrases every 2 s",
                                             target: self, action: #selector(autoToggled))

    // MARK: - State

    private var autoTimer: Timer?
    private var phraseIndex = 0

    private let phrases = [
        "Hello, World!",
        "LabelMorph",
        "Eleven ways to morph",
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
        MorphPreset.allCases[max(0, presetPopup.indexOfSelectedItem)]
    }

    deinit {
        autoTimer?.invalidate()
    }

    // MARK: - View construction

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 620))

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
        root.addSubview(panel)

        func addRow(_ row: NSView) {
            row.translatesAutoresizingMaskIntoConstraints = false
            panel.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        }

        addRow(labeledRow("Effect", control: presetPopup))
        addRow(labeledRow("Duration", control: durationSlider, value: durationValue,
                          caption: Self.captionLabel("Animation time for a single character — not the whole morph. Spring effects (Bounce, Drop) settle a little later.")))
        addRow(labeledRow("Stagger", control: staggerSlider, value: staggerValue,
                          caption: Self.captionLabel("Extra start delay per character, creating the cascade. Whole morph ≈ duration + stagger × (characters − 1).")))
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

            panel.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 20),
            panel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            panel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            panel.widthAnchor.constraint(equalToConstant: 280),

            label.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: preview.centerYAnchor),

            hint.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -16),
        ])

        // The panel prefers to fit fully, but may clip at small window
        // heights rather than fight the required constraints.
        let panelBottom = panel.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        panelBottom.priority = NSLayoutConstraint.Priority(900)
        panelBottom.isActive = true

        self.view = root
        preferredContentSize = NSSize(width: 980, height: 700)
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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        presetPopup.addItems(withTitles: MorphPreset.allCases.map(\.displayName))
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

        // Launch arguments for scripted demos: -preset <rawValue> -autoplay YES
        let defaults = UserDefaults.standard
        if let presetName = defaults.string(forKey: "preset"),
           let index = MorphPreset.allCases.firstIndex(where: { $0.rawValue == presetName }) {
            presetPopup.selectItem(at: index)
            loadRecommendedTiming(for: currentPreset)
            applySettings()
        }
        if defaults.bool(forKey: "autoplay") {
            autoCheckbox.state = .on
            autoToggled()
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
        label.reusesMatchingCharacters = reuseCheckbox.state == .on
    }

    private func updateValueLabels() {
        durationValue.stringValue = String(format: "%.2f s", durationSlider.doubleValue)
        staggerValue.stringValue = String(format: "%.3f s", staggerSlider.doubleValue)
        intensityValue.stringValue = String(format: "%.2f", intensitySlider.doubleValue)
        fontValue.stringValue = String(format: "%.0f pt", fontSlider.doubleValue)
    }
}
