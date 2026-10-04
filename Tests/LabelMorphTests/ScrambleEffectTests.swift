import QuartzCore
import XCTest
@testable import LabelMorph

@MainActor
final class ScrambleEffectTests: XCTestCase {

    /// The glyph a scramble shows is drawn, not merely assigned: a `GlyphLayer` rasters its own
    /// slot's character, so the decoder used to change nothing on screen and only fade.
    func testAScramblingGlyphDrawsThePoolThenItsOwnCharacter() {
        let host = CALayer()
        let glyph = GlyphLayer()
        host.addSublayer(glyph)
        let ticker = ScrambleTicker()
        let pool: [Character] = Array("ｱｲｳ")

        ticker.add(.init(layer: glyph, start: 10, end: 11, pool: pool, settles: true, interval: 1))
        ticker.tick(now: 9)
        XCTAssertNil(glyph.transientCharacter, "nothing scrambles before its stagger")

        ticker.tick(now: 10.5)
        let shown = try? XCTUnwrap(glyph.transientCharacter)
        XCTAssertTrue(shown.map { pool.map(String.init).contains($0) } ?? false)

        ticker.tick(now: 11)
        XCTAssertNil(glyph.transientCharacter, "an incoming glyph settles on its own character")
        XCTAssertEqual(ticker.activeCount, 0)
        XCTAssertFalse(ticker.isRunning, "the ticker stops with its last glyph")
    }

    func testOneTickerDrivesEveryGlyphAndDropsDetachedOnes() {
        let host = CALayer()
        let ticker = ScrambleTicker()
        let glyphs = (0..<40).map { _ in GlyphLayer() }
        glyphs.forEach(host.addSublayer)
        for glyph in glyphs {
            ticker.add(.init(layer: glyph, start: 0, end: 5, pool: ["#"], settles: false, interval: 1))
        }
        XCTAssertEqual(ticker.activeCount, 40)
        XCTAssertTrue(ticker.isRunning)

        glyphs[0].removeFromSuperlayer()
        ticker.tick(now: 1)
        XCTAssertEqual(ticker.activeCount, 39, "a glyph that left the line is forgotten")
        XCTAssertEqual(glyphs[1].transientCharacter, "#")

        ticker.tick(now: 6)
        XCTAssertEqual(glyphs[1].transientCharacter, "#", "an outgoing glyph fades mid-scramble")
        XCTAssertEqual(ticker.activeCount, 0)
        XCTAssertFalse(ticker.isRunning)
    }
}
