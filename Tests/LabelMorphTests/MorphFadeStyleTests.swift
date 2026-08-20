import AppKit
import QuartzCore
import XCTest
@testable import LabelMorph

@MainActor
final class MorphFadeStyleTests: XCTestCase {

    private enum Fade {
        static let carrierName = "labelmorph.fade-carrier"
        static let animationKey = "morph.fade.traveling"
    }

    func testTravelingFadeComposesWithEveryPreset() throws {
        for preset in MorphPreset.allCases {
            let fixture = hostedLabel(effect: preset.makeEffect())
            fixture.label.fadeStyle = .traveling

            fixture.label.setText("HIJKLMN")

            let carriers = fadeCarriers(in: fixture.label)
            XCTAssertEqual(carriers.count, 7, preset.displayName)
            let animations = try carriers.map { carrier in
                try XCTUnwrap(
                    carrier.animation(forKey: Fade.animationKey) as? CAKeyframeAnimation,
                    "\(preset.displayName) did not receive the traveling fade"
                )
            }
            let orderedStarts = animations.map(\.beginTime).sorted()
            XCTAssertGreaterThan(
                try XCTUnwrap(orderedStarts.last) - (orderedStarts.first ?? 0),
                0.35,
                "\(preset.displayName) did not travel from leading to trailing"
            )
        }
    }

    func testTravelingFadeDipsAndReturnsToFullOpacity() throws {
        let fixture = hostedLabel(effect: CrossfadeEffect())
        fixture.label.fadeStyle = .traveling

        fixture.label.setText("HIJKLMN")

        let animation = try XCTUnwrap(
            fadeCarriers(in: fixture.label).first?.animation(forKey: Fade.animationKey)
                as? CAKeyframeAnimation
        )
        let values = try XCTUnwrap(animation.values as? [NSNumber])
        XCTAssertEqual(values.first?.doubleValue, 1)
        XCTAssertEqual(values.last?.doubleValue, 1)
        XCTAssertEqual(
            values.filter { $0.doubleValue < 0.2 }.count,
            2,
            "the default should visibly pulse, not dip only once"
        )
    }

    func testTravelingFadeCanPlayWithoutChangingSettledText() throws {
        let fixture = hostedLabel(effect: CrossfadeEffect())
        fixture.label.fadeStyle = .traveling
        let settledText = fixture.label.text

        fixture.label.playFade()

        XCTAssertEqual(fixture.label.text, settledText)
        let carriers = fadeCarriers(in: fixture.label)
        XCTAssertEqual(carriers.count, settledText.count)
        XCTAssertTrue(
            carriers.allSatisfy { $0.animation(forKey: Fade.animationKey) != nil }
        )

        fixture.label.stopFade()

        XCTAssertTrue(fadeCarriers(in: fixture.label).isEmpty)
        XCTAssertEqual(fixture.label.text, settledText)
    }

    func testStandaloneFadeIsIgnoredDuringAnInsertionOnlyTextMorph() throws {
        let fixture = hostedLabel(effect: GlyphMorphEffect())
        fixture.label.fadeStyle = .traveling

        fixture.label.setText("ABCDEFGH")

        let carriersBefore = fadeCarriers(in: fixture.label)
        let transientsBefore = descendants(of: fixture.label.layer)
            .filter { $0.name == MorphTransientLayer.name }
        XCTAssertEqual(carriersBefore.count, 8)
        XCTAssertFalse(transientsBefore.isEmpty)

        fixture.label.playFade()

        XCTAssertEqual(
            fadeCarriers(in: fixture.label).map(ObjectIdentifier.init),
            carriersBefore.map(ObjectIdentifier.init),
            "the standalone fade replaced the text morph's carriers"
        )
        XCTAssertEqual(
            descendants(of: fixture.label.layer)
                .filter { $0.name == MorphTransientLayer.name }
                .map(ObjectIdentifier.init),
            transientsBefore.map(ObjectIdentifier.init),
            "the standalone fade removed Shape Morph's visible incoming outline"
        )
    }

    func testTravelingFadeConfigurationControlsPulseDepthCountPauseAndTravel() throws {
        let fixture = hostedLabel(effect: CrossfadeEffect())
        fixture.label.fadeStyle = .traveling
        fixture.label.fadeConfiguration = MorphFadeConfiguration(
            pulseCount: 4,
            minimumOpacity: 0.35,
            pulseDuration: 0.19,
            pauseDuration: 0.11,
            travelDuration: 0.63
        )

        fixture.label.setText("HIJKLMN")

        let animations = try fadeCarriers(in: fixture.label).map {
            try XCTUnwrap($0.animation(forKey: Fade.animationKey) as? CAKeyframeAnimation)
        }
        let leading = try XCTUnwrap(animations.min { $0.beginTime < $1.beginTime })
        let values = try XCTUnwrap(leading.values as? [NSNumber])
        let keyTimes = try XCTUnwrap(leading.keyTimes)
        XCTAssertEqual(values[1].doubleValue, 0.35, accuracy: 0.001)
        XCTAssertEqual(values.filter { abs($0.doubleValue - 0.35) < 0.001 }.count, 4)
        XCTAssertEqual(leading.duration, 4 * 0.19 + 3 * 0.11, accuracy: 0.001)
        XCTAssertEqual(
            (keyTimes[3].doubleValue - keyTimes[2].doubleValue) * leading.duration,
            0.11,
            accuracy: 0.001,
            "the configured pause was not preserved between pulses"
        )

        let starts = animations.map(\.beginTime).sorted()
        let firstStart = try XCTUnwrap(starts.first)
        let lastStart = try XCTUnwrap(starts.last)
        XCTAssertEqual(
            lastStart - firstStart,
            0.63,
            accuracy: 0.02
        )
    }

    func testZeroPauseProducesBackToBackPulsesWithoutAFullOpacityHold() throws {
        let fixture = hostedLabel(effect: CrossfadeEffect())
        fixture.label.fadeStyle = .traveling
        fixture.label.fadeConfiguration = MorphFadeConfiguration(
            pulseCount: 2,
            minimumOpacity: 0.2,
            pulseDuration: 0.2,
            pauseDuration: 0,
            travelDuration: 0.6
        )

        fixture.label.setText("HIJKLMN")

        let animation = try XCTUnwrap(
            fadeCarriers(in: fixture.label).first?.animation(forKey: Fade.animationKey)
                as? CAKeyframeAnimation
        )
        let values = try XCTUnwrap(animation.values as? [NSNumber])
        let expectedValues = [1.0, 0.2, 1.0, 0.2, 1.0]
        XCTAssertEqual(values.count, expectedValues.count)
        for (actual, expected) in zip(values, expectedValues) {
            XCTAssertEqual(actual.doubleValue, expected, accuracy: 0.001)
        }
        XCTAssertEqual(animation.duration, 0.4, accuracy: 0.001)
        XCTAssertTrue(
            zip(values, values.dropFirst()).allSatisfy { $0.doubleValue != $1.doubleValue },
            "zero pause inserted a duplicate full-opacity hold keyframe"
        )
    }

    func testShapeMorphsTemporaryOutlineSharesTheFadeCarrier() throws {
        let fixture = hostedLabel(effect: MorphPreset.shapeMorph.makeEffect())
        fixture.label.fadeStyle = .traveling

        fixture.label.setText("HIJKLMN")

        let transientShapes = descendants(of: fixture.label.layer)
            .filter { $0.name == MorphTransientLayer.name }
        XCTAssertFalse(transientShapes.isEmpty)
        XCTAssertTrue(
            transientShapes.allSatisfy { $0.superlayer?.name == Fade.carrierName },
            "the opacity wave did not wrap Shape Morph's visible stand-in"
        )
    }

    func testNoFadeKeepsTheOrdinaryDirectGlyphTree() {
        let fixture = hostedLabel(effect: CrossfadeEffect())

        fixture.label.setText("HIJKLMN")

        XCTAssertTrue(fadeCarriers(in: fixture.label).isEmpty)
        XCTAssertFalse(
            fixture.label.layer?.sublayers?.compactMap { $0 as? GlyphLayer }.isEmpty ?? true
        )
    }

    private func hostedLabel(effect: TextMorphEffect) -> (label: MorphingLabel, window: NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let label = MorphingLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 32, weight: .semibold)
        label.effect = effect
        label.timing = MorphTiming(duration: 0.45, stagger: 0.03)
        window.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 360),
            label.heightAnchor.constraint(equalToConstant: 60),
        ])
        window.layoutIfNeeded()
        label.setText("ABCDEFG", animated: false)
        return (label, window)
    }

    private func fadeCarriers(in label: MorphingLabel) -> [CALayer] {
        descendants(of: label.layer).filter { $0.name == Fade.carrierName }
    }

    private func descendants(of layer: CALayer?) -> [CALayer] {
        guard let children = layer?.sublayers else { return [] }
        return children + children.flatMap { descendants(of: $0) }
    }
}
