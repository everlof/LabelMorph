import AppKit
import QuartzCore
import XCTest
@testable import LabelMorph

@MainActor
final class WholeLineMorphEffectTests: XCTestCase {

    func testEveryWholeLineGlyphMovesAndFadesInLockstep() throws {
        let fixture = hostedLabel(effect: LineScrollEffect(direction: .up, distanceFactor: 1))
        let outgoing = glyphLayers(in: fixture.label)
        XCTAssertEqual(outgoing.count, 4)

        fixture.label.setText("AAAB")
        fixture.window.layoutIfNeeded()

        let allGlyphs = glyphLayers(in: fixture.label)
        let outgoingIDs = Set(outgoing.map(ObjectIdentifier.init))
        let incoming = allGlyphs.filter { !outgoingIDs.contains(ObjectIdentifier($0)) }

        XCTAssertEqual(incoming.count, 4)
        XCTAssertTrue(incoming.allSatisfy { layer in
            outgoing.allSatisfy { $0 !== layer }
        }, "a whole-line transition reused matching characters")

        let incomingMoves = try incoming.map {
            try basicAnimation(on: $0, key: "morph.line.in.translation")
        }
        let outgoingMoves = try outgoing.map {
            try basicAnimation(on: $0, key: "morph.line.out.translation")
        }
        let fades = try (incoming + outgoing).map { layer in
            try basicAnimation(
                on: layer,
                key: outgoingIDs.contains(ObjectIdentifier(layer))
                    ? "morph.line.out.opacity"
                    : "morph.line.in.opacity"
            )
        }

        XCTAssertEqual(
            Set((incomingMoves + outgoingMoves + fades).map(\.beginTime)).count,
            1,
            "the old and new line did not begin as one coordinated handoff"
        )
        XCTAssertTrue(incoming.allSatisfy {
            $0.animation(forKey: "morph.line.in.opacity") != nil
        })
        XCTAssertTrue(outgoing.allSatisfy {
            $0.animation(forKey: "morph.line.out.opacity") != nil
        })

        let incomingOffset = try sizeValue(incomingMoves[0].fromValue).height
        let outgoingOffset = try sizeValue(outgoingMoves[0].toValue).height
        XCTAssertLessThan(incomingOffset, 0)
        XCTAssertGreaterThan(outgoingOffset, 0)
    }

    func testLineScrollDownReversesBothCompleteLines() throws {
        let fixture = hostedLabel(effect: LineScrollEffect(direction: .down, distanceFactor: 1))
        let outgoing = glyphLayers(in: fixture.label)

        fixture.label.setText("NEXT")
        fixture.window.layoutIfNeeded()

        let outgoingIDs = Set(outgoing.map(ObjectIdentifier.init))
        let incoming = glyphLayers(in: fixture.label).filter {
            !outgoingIDs.contains(ObjectIdentifier($0))
        }
        let incomingMove = try basicAnimation(
            on: try XCTUnwrap(incoming.first),
            key: "morph.line.in.translation"
        )
        let outgoingMove = try basicAnimation(
            on: try XCTUnwrap(outgoing.first),
            key: "morph.line.out.translation"
        )

        XCTAssertGreaterThan(try sizeValue(incomingMove.fromValue).height, 0)
        XCTAssertLessThan(try sizeValue(outgoingMove.toValue).height, 0)
    }

    func testLineScrollPresetsHaveNoCharacterStagger() {
        for preset in [MorphPreset.lineScrollUp, .lineScrollDown] {
            XCTAssertTrue(preset.makeEffect() is WholeLineMorphEffect)
            XCTAssertEqual(preset.scope, .wholeLine)
            XCTAssertEqual(preset.recommendedTiming.stagger, 0)
        }

        XCTAssertTrue(
            MorphPreset.allCases
                .filter { ![MorphPreset.lineScrollUp, .lineScrollDown].contains($0) }
                .allSatisfy { $0.scope == .singleCharacter }
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
        label.timing = MorphTiming(duration: 0.45, stagger: 0)
        window.contentView?.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: window.contentView!.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 360),
            label.heightAnchor.constraint(equalToConstant: 60),
        ])
        window.layoutIfNeeded()
        label.setText("AAAA", animated: false)
        return (label, window)
    }

    private func glyphLayers(in label: MorphingLabel) -> [GlyphLayer] {
        descendants(of: label.layer).compactMap { $0 as? GlyphLayer }
    }

    private func descendants(of layer: CALayer?) -> [CALayer] {
        guard let children = layer?.sublayers else { return [] }
        return children + children.flatMap { descendants(of: $0) }
    }

    private func basicAnimation(on layer: CALayer, key: String) throws -> CABasicAnimation {
        try XCTUnwrap(layer.animation(forKey: key) as? CABasicAnimation)
    }

    private func sizeValue(_ value: Any?) throws -> CGSize {
        try XCTUnwrap(value as? NSValue).sizeValue
    }
}
