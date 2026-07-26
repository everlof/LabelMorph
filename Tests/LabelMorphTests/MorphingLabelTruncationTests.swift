import AppKit
import XCTest
@testable import LabelMorph

/// Truncation as the *label* applies it across bounds changes — `CharacterLayoutTruncationTests`
/// pins the pure function; these pin that the layers on screen follow it.
@MainActor
final class MorphingLabelTruncationTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 13)

    private func makeLabel(_ text: String, width: CGFloat) -> MorphingLabel {
        let label = MorphingLabel()
        label.font = font
        label.truncation = .tail
        label.frame = NSRect(x: 0, y: 0, width: width, height: 20)
        label.text = text
        label.layout()
        return label
    }

    /// The regression that motivated the character-comparison guard in `relayoutCurrent`.
    ///
    /// Tail truncation that drops exactly one trailing character replaces it with the
    /// ellipsis, so the truncated line and the full line have the *same* slot count — and a
    /// rebuild guard comparing counts repositioned the stale "…" where the dropped character
    /// belonged, no matter how wide the label later grew. A session named "hi ❤️ nice 😂"
    /// read "hi ❤️ nice …" in a sidebar with room to spare.
    func testWideningRestoresACharacterTheEllipsisReplaced() {
        let text = "hi ❤️ nice 😂"
        let fullWidth = ceil(CharacterLayout.measure(text, font: font).width)

        // A point short of the full line: exactly the one-character truncation whose slot
        // count matches the full text's.
        let label = makeLabel(text, width: fullWidth - 1)
        XCTAssertEqual(
            label.displayedCharacters.last, CharacterLayout.ellipsis,
            "a point short of the line should truncate"
        )
        XCTAssertEqual(
            label.displayedCharacters.count,
            CharacterLayout.visibleSlots(
                for: text,
                font: font,
                bounds: label.bounds,
                alignment: label.alignment
            ).count,
            "the regression needs the truncated and full lines to agree about the count"
        )

        label.frame = NSRect(x: 0, y: 0, width: fullWidth, height: 20)
        label.layout()

        XCTAssertEqual(
            label.displayedCharacters.last, "😂",
            "given its full width back, the label must lay the dropped character out again"
        )
    }

    func testNarrowingTruncatesWhatFitBefore() {
        let text = "hi ❤️ nice 😂"
        let fullWidth = ceil(CharacterLayout.measure(text, font: font).width)

        let label = makeLabel(text, width: fullWidth)
        XCTAssertEqual(label.displayedCharacters.last, "😂")

        label.frame = NSRect(x: 0, y: 0, width: fullWidth - 1, height: 20)
        label.layout()

        XCTAssertEqual(label.displayedCharacters.last, CharacterLayout.ellipsis)
    }
}
