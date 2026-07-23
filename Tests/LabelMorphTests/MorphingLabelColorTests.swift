import AppKit
import CoreText
import XCTest
@testable import LabelMorph

@MainActor
final class MorphingLabelColorTests: XCTestCase {

    func testChangingTextColorRecolorsExistingGlyphsInPlace() throws {
        let label = MorphingLabel(
            frame: NSRect(x: 0, y: 0, width: 240, height: 60)
        )
        label.setText("Theme", animated: false)
        let originalLayer = try firstGlyphLayer(in: label)
        let accent = NSColor(calibratedRed: 0.4, green: 0.2, blue: 0.8, alpha: 1)

        label.textColor = accent

        XCTAssertTrue(try firstGlyphLayer(in: label) === originalLayer)
        XCTAssertEqual(try glyphColor(in: label), accent.cgColor)
    }

    func testDynamicTextColorFollowsEffectiveAppearance() throws {
        let light = NSColor(calibratedRed: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        let dark = NSColor(calibratedRed: 0.1, green: 0.7, blue: 0.9, alpha: 1)
        let dynamic = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }

        let label = MorphingLabel(
            frame: NSRect(x: 0, y: 0, width: 240, height: 60)
        )
        label.appearance = NSAppearance(named: .aqua)
        label.textColor = dynamic
        label.setText("Theme", animated: false)

        XCTAssertEqual(
            try glyphColor(in: label),
            light.cgColor
        )

        label.appearance = NSAppearance(named: .darkAqua)
        label.viewDidChangeEffectiveAppearance()

        XCTAssertEqual(
            try glyphColor(in: label),
            dark.cgColor
        )
    }

    private func firstGlyphLayer(in label: MorphingLabel) throws -> CATextLayer {
        try XCTUnwrap(
            label.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first
        )
    }

    private func glyphColor(in label: MorphingLabel) throws -> CGColor {
        let layer = try firstGlyphLayer(in: label)
        let attributed = try XCTUnwrap(layer.string as? NSAttributedString)
        let color = try XCTUnwrap(
            attributed.attribute(
                NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                at: 0,
                effectiveRange: nil
            )
        )
        return color as! CGColor
    }
}
