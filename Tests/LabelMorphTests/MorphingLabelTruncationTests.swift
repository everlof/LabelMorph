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
                alignment: label.alignment,
                scale: 2
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

    /// A leading line's glyph positions do not depend on spare width. Re-invalidating every
    /// glyph raster while a sidebar divider moves is both expensive and visually redundant.
    func testLeadingLineKeepsItsGlyphRastersWhenOnlySpareWidthChanges() throws {
        let text = "A title that already fits"
        let fullWidth = ceil(CharacterLayout.measure(text, font: font).width)
        let label = makeLabel(text, width: fullWidth + 20)
        label.alignment = .left
        label.layout()

        let glyphs = try XCTUnwrap(label.layer?.sublayers?.compactMap { $0 as? GlyphLayer })
        glyphs.forEach { $0.displayIfNeeded() }
        XCTAssertTrue(glyphs.allSatisfy { !$0.needsDisplay() })

        label.frame.size.width += 40
        label.layout()

        XCTAssertTrue(
            glyphs.allSatisfy { !$0.needsDisplay() },
            "spare leading-line width invalidated glyphs whose pixels and positions did not move"
        )
    }

    /// Crossing a tail-truncation boundary changes only the suffix. Rebuilding the common
    /// prefix made every character in every visible sidebar title rerasterize per divider tick.
    func testTruncationChangeReusesTheUnchangedGlyphPrefix() throws {
        let text = "A title with a deliberately long tail"
        let label = makeLabel(text, width: 110)
        label.alignment = .left
        label.layout()
        let originalGlyphs = try XCTUnwrap(
            label.layer?.sublayers?.compactMap { $0 as? GlyphLayer }
        )
        let originalFirst = try XCTUnwrap(originalGlyphs.first)
        let originalCharacters = label.displayedCharacters

        label.frame.size.width += 12
        label.layout()

        let widenedGlyphs = try XCTUnwrap(
            label.layer?.sublayers?.compactMap { $0 as? GlyphLayer }
        )
        XCTAssertNotEqual(label.displayedCharacters, originalCharacters)
        XCTAssertTrue(
            widenedGlyphs.first === originalFirst,
            "a changed tail rebuilt the unchanged leading glyph"
        )
    }

    /// Width is presentation geometry for centered and trailing lines, so the leading-line
    /// optimization must not freeze either alignment in place.
    func testNonLeadingAlignmentStillMovesWithWidth() {
        for alignment in [NSTextAlignment.center, .right] {
            let label = makeLabel("Moving title", width: 180)
            label.alignment = alignment
            label.layout()
            let originalX = label.glyphInkFrames.first?.minX

            label.frame.size.width += 40
            label.layout()

            XCTAssertNotEqual(
                label.glyphInkFrames.first?.minX,
                originalX,
                "\(alignment) alignment did not follow its changed width"
            )
        }
    }

    /// Vertical centering is shared by every alignment; a height change still moves a leading
    /// line even though an ordinary sidebar-width change does not.
    func testLeadingLineStillMovesWithHeight() {
        let label = makeLabel("Moving title", width: 180)
        label.alignment = .left
        label.layout()
        let originalY = label.glyphInkFrames.first?.minY

        label.frame.size.height += 20
        label.layout()

        XCTAssertNotEqual(label.glyphInkFrames.first?.minY, originalY)
    }
}
