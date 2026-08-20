import AppKit
import XCTest
@testable import LabelMorph

/// Opt-in microbenchmarks for the package-owned layer work that Threading used
/// to measure only through its complete sidebar launch trace.
///
/// Run with:
/// `LABELMORPH_BENCHMARKS=1 swift test --filter MorphingLabelPerformanceTests`
@MainActor
final class MorphingLabelPerformanceTests: XCTestCase {

    func testTravelingFadeSetupWhenEnabled() throws {
        try requireBenchmarks()
        let fixture = hostedLabel()
        fixture.label.fadeStyle = .traveling

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            fixture.label.playFade()
            fixture.label.stopFade()
        }
    }

    func testWholeLineHandoffSetupWhenEnabled() throws {
        try requireBenchmarks()
        let fixture = hostedLabel()
        fixture.label.effect = LineScrollEffect()
        let first = stressText(seed: "A")
        let second = stressText(seed: "B")
        fixture.label.setText(first, animated: false)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            fixture.label.setText(fixture.label.text == first ? second : first)
        }
    }

    private func requireBenchmarks() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LABELMORPH_BENCHMARKS"] == "1",
            "Set LABELMORPH_BENCHMARKS=1 to run LabelMorph microbenchmarks."
        )
    }

    private func hostedLabel() -> (label: MorphingLabel, window: NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_800, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let label = MorphingLabel(frame: window.contentView?.bounds ?? .zero)
        label.font = .systemFont(ofSize: 13)
        label.timing = MorphTiming(duration: 0.45, stagger: 0.02)
        window.contentView?.addSubview(label)
        label.setText(stressText(seed: "A"), animated: false)
        return (label, window)
    }

    /// Long enough to expose per-glyph setup costs while remaining a realistic
    /// single-line status/title workload rather than an artificial paragraph.
    private func stressText(seed: String) -> String {
        Array(repeating: "\(seed) LabelMorph status", count: 6).joined(separator: " · ")
    }
}
