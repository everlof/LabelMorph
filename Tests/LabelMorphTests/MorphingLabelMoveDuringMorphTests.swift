import AppKit
import XCTest
@testable import LabelMorph

/// A morph is built against the position the line settles in, but the glyphs on screen are
/// kept where the eye last saw them, so a label that moves in its window between the text
/// change and the layout pass that animates it starts every old glyph from the old spot. That
/// keeps the line from jumping first and morphing second — and it must hold for the character
/// the morph *keeps* as much as for the ones it replaces.
@MainActor
final class MorphingLabelMoveDuringMorphTests: XCTestCase {

    private let font = NSFont.systemFont(ofSize: 13)

    /// A label in an unshown window, pinned by a top constraint the test can move. The
    /// package refuses to animate a label without a window, and only a window gives
    /// `convert(_:to: nil)` — the reading the morph's shift is taken from — anything to say.
    private func hostedLabel(_ text: String) -> (MorphingLabel, NSLayoutConstraint, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let label = MorphingLabel()
        label.font = font
        label.alignment = .left
        label.effect = GlyphMorphEffect()
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(label)
        let top = label.topAnchor.constraint(equalTo: content.topAnchor, constant: 30)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            label.widthAnchor.constraint(equalToConstant: 200),
            label.heightAnchor.constraint(equalToConstant: 20),
            top
        ])
        label.setText(text, animated: false)
        window.layoutIfNeeded()
        return (label, top, window)
    }

    private func glyphs(of label: MorphingLabel) throws -> [GlyphLayer] {
        try XCTUnwrap(label.layer?.sublayers?.compactMap { $0 as? GlyphLayer })
    }

    /// The bug behind a sidebar row whose first letter sat half a line below the rest of its
    /// name and stayed there. A session called "Precis contrast" was renamed "PREVIEW" in the
    /// same pass that moved its row, so the title moved up in the window between the rename
    /// and the layout that morphed it. The old glyphs were shifted down to stay where
    /// they were seen; six of them were replaced, and the P — same character, same slot — was
    /// handed back a slot equal to the one it already held, which the layer took as nothing
    /// to do. Its frame kept the shift, no animation was asked to move it, and no later pass
    /// had a reason to touch a slot that already matched.
    func testACharacterTheMorphKeepsTravelsWithTheLineWhenTheLabelMoved() throws {
        let (label, top, window) = hostedLabel("Precis contrast")
        let settledFrames = try glyphs(of: label).map(\.frame)

        label.setText("PREVIEW", animated: true)
        // The host moves the label up before the layout pass that builds the morph, as a
        // sidebar row does when the list scrolls or a row above it changes.
        top.constant -= 8
        window.layoutIfNeeded()

        let morphed = try glyphs(of: label)
        let kept = try XCTUnwrap(
            morphed.first { $0.slot?.character == "P" && $0.opacity == 1 },
            "the P is in both names and should have been kept"
        )
        XCTAssertEqual(
            kept.frame, try XCTUnwrap(kept.slot).frame,
            "the kept glyph's layer sits where its slot says, not where the old line was"
        )
        XCTAssertEqual(
            kept.frame, try XCTUnwrap(settledFrames.first),
            "the label's own geometry did not change, so the P lands where it already was"
        )
        XCTAssertNotNil(
            kept.animation(forKey: "morph.move"),
            "the P moved in the window, so it travels to its slot rather than jumping"
        )

        // Every glyph on the line, kept or new, agrees with its slot.
        for glyph in morphed where glyph.opacity == 1 {
            XCTAssertEqual(glyph.frame, try XCTUnwrap(glyph.slot).frame,
                           "\(glyph.slot?.character ?? "?") is drawn off its slot")
        }
    }

    /// The shift is meant to be undone by the morph, not remembered by the layer: once the
    /// glyphs have travelled, a later layout pass that changes nothing must find nothing to
    /// correct — and, symmetrically, must not have been what corrected it.
    func testAKeptCharacterStaysOnItsSlotAcrossALaterUnchangedLayout() throws {
        let (label, top, window) = hostedLabel("Precis contrast")

        label.setText("PREVIEW", animated: true)
        top.constant -= 8
        window.layoutIfNeeded()
        label.layout()

        for glyph in try glyphs(of: label) where glyph.opacity == 1 {
            XCTAssertEqual(glyph.frame, try XCTUnwrap(glyph.slot).frame)
        }
    }

    /// The slot owns the frame in both directions. A frame written behind the slot's back —
    /// which is how the kept glyph went astray — is corrected by the next `apply`, even one
    /// that hands the layer the very slot it holds.
    func testApplyingTheSlotALayerAlreadyHoldsBringsAStrayedFrameBack() throws {
        let slot = try XCTUnwrap(
            CharacterLayout.visibleSlots(
                for: "P", font: font,
                bounds: CGRect(x: 0, y: 0, width: 40, height: 20),
                alignment: .left, scale: 2
            ).first
        )
        let layer = GlyphLayer()
        layer.apply(slot)
        XCTAssertEqual(layer.frame, slot.frame)

        layer.frame = layer.frame.offsetBy(dx: 0, dy: -8)
        layer.apply(slot)

        XCTAssertEqual(layer.frame, slot.frame, "the slot says where the layer is drawn")
    }

    /// The shift exists for the replaced characters too: the stand-in an effect draws for an
    /// outgoing glyph is positioned from the slot, so the slot has to move with the frame or
    /// the line jumps to its new place before the morph starts.
    func testAReplacedCharactersSlotMovesWithItsShiftedFrame() throws {
        let (label, top, window) = hostedLabel("Precis contrast")
        let before = try glyphs(of: label).first { $0.slot?.character == "r" }
        let frameBefore = try XCTUnwrap(before?.frame)
        let inkBefore = try XCTUnwrap(before?.slot?.inkFrame)

        label.setText("PREVIEW", animated: true)
        top.constant -= 8
        window.layoutIfNeeded()

        let leaving = try XCTUnwrap(
            try glyphs(of: label).first { $0.slot?.character == "r" && $0.opacity == 0 },
            "the lowercase r is replaced and should be on its way out"
        )
        XCTAssertEqual(leaving.frame, frameBefore.offsetBy(dx: 0, dy: -8))
        XCTAssertEqual(
            try XCTUnwrap(leaving.slot).inkFrame, inkBefore.offsetBy(dx: 0, dy: -8),
            "the outgoing glyph's ink box describes where it is drawn, shift included"
        )
    }
}
