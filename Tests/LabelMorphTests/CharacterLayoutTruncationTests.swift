import AppKit
import XCTest
@testable import LabelMorph

@MainActor
final class CharacterLayoutTruncationTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 13)

    private func width(_ text: String) -> CGFloat {
        CharacterLayout.measure(text, font: font).width
    }

    // MARK: - The fit

    func testTextThatFitsIsReturnedUnchanged() {
        let text = "Skalman"
        XCTAssertEqual(
            CharacterLayout.tailTruncated(text, font: font, width: width(text) + 10),
            text
        )
    }

    /// The point of the whole exercise: the result must be *narrower* than the space it was
    /// given, not merely shorter than the original. A truncation that still overruns is the
    /// hard clip it was meant to replace.
    func testTruncatedTextFitsTheGivenWidth() {
        let text = "Land what the last sessions built but never committed"

        for available in stride(from: 20.0, through: width(text), by: 7.0) {
            let result = CharacterLayout.tailTruncated(text, font: font, width: available)
            XCTAssertLessThanOrEqual(
                width(result),
                available,
                "«\(result)» overruns \(available)"
            )
        }
    }

    func testTruncatedTextEndsWithAnEllipsisAndKeepsItsHead() {
        let text = "Land what the last sessions built but never committed"
        let result = CharacterLayout.tailTruncated(text, font: font, width: 120)

        XCTAssertTrue(result.hasSuffix(CharacterLayout.ellipsis))
        XCTAssertTrue(text.hasPrefix(result.dropLast()))
        XCTAssertLessThan(result.count, text.count)
    }

    /// Wider is never shorter — the property the label's relayout depends on, since it
    /// treats an unchanged slot count as an unchanged line.
    func testKeptLengthGrowsWithAvailableWidth() {
        let text = "Spin an accent-tinted orb beside the working status"
        var previous = 0

        for available in stride(from: 30.0, through: 400.0, by: 10.0) {
            let kept = CharacterLayout.tailTruncated(text, font: font, width: available).count
            XCTAssertGreaterThanOrEqual(kept, previous)
            previous = kept
        }
    }

    // MARK: - Edges

    func testWidthTooNarrowForTheEllipsisYieldsNothing() {
        XCTAssertEqual(CharacterLayout.tailTruncated("Session", font: font, width: 1), "")
        XCTAssertEqual(CharacterLayout.tailTruncated("Session", font: font, width: 0), "")
    }

    /// A cut that lands inside a surrogate pair or between a base and its combining mark
    /// would produce a broken scalar, so the walk steps by composed character.
    func testCutNeverSplitsAComposedCharacter() {
        let text = "👩‍💻 é🇸🇪 shipping the thing"

        for available in stride(from: 12.0, through: width(text), by: 3.0) {
            let result = CharacterLayout.tailTruncated(text, font: font, width: available)
            guard result != CharacterLayout.ellipsis, !result.isEmpty else { continue }

            let head = String(result.dropLast())
            XCTAssertTrue(
                text.hasPrefix(head),
                "«\(head)» is not a whole-character head of the original"
            )
        }
    }

    func testTrailingSpaceIsNotLeftBeforeTheEllipsis() {
        let text = "Skalman needs a much longer name than this"
        let target = "Skalman "

        let result = CharacterLayout.tailTruncated(
            text,
            font: font,
            width: width(target) + width(CharacterLayout.ellipsis)
        )
        XCTAssertFalse(result.dropLast().hasSuffix(" "))
    }

    func testEmptyTextIsUnchanged() {
        XCTAssertEqual(CharacterLayout.tailTruncated("", font: font, width: 100), "")
    }

    // MARK: - The label

    func testLabelLaysOutOnlyTheGlyphsThatFitWhenTruncating() {
        let text = "Land what the last sessions built but never committed"
        let label = MorphingLabel(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
        label.font = font
        label.truncation = .tail
        label.setText(text, animated: false)

        let laidOut = label.layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
        XCTAssertFalse(laidOut.isEmpty)

        // Every glyph inside the label's own bounds — the hard-clip case is a layer whose
        // frame runs off the trailing edge.
        for glyph in laidOut {
            XCTAssertLessThanOrEqual(glyph.frame.maxX, label.bounds.maxX + 0.5)
        }
    }

    func testLabelReportsTheWholeTextsWidthAsItsIntrinsicSize() {
        let text = "Land what the last sessions built but never committed"
        let label = MorphingLabel(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
        label.font = font
        label.truncation = .tail
        label.setText(text, animated: false)

        // Truncation says what the label does when squeezed; it must not also tell Auto
        // Layout that a squeezed width is the width it wanted.
        XCTAssertEqual(label.intrinsicContentSize.width, ceil(width(text)), accuracy: 1)
    }

    func testUntruncatedLabelStillOverrunsItsBounds() {
        let text = "Land what the last sessions built but never committed"
        let label = MorphingLabel(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
        label.font = font
        label.setText(text, animated: false)

        let laidOut = label.layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
        XCTAssertTrue(laidOut.contains { $0.frame.maxX > label.bounds.maxX })
    }
}
