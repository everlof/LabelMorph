import QuartzCore

/// Characters cycle through random glyphs before settling on the final text,
/// like a hacker-movie decoder or an airport departures board.
public final class ScrambleEffect: TextMorphEffect {

    /// Pool of characters used while scrambling.
    public var characters: [Character]

    /// Time between glyph swaps.
    public var tickInterval: TimeInterval

    public init(characters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#$%&?!"),
                tickInterval: TimeInterval = 1.0 / 24.0) {
        self.characters = characters
        self.tickInterval = tickInterval
    }

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 0, to: 1,
                                    duration: min(0.12, context.timing.duration)),
                  forKey: "morph.in.opacity")
        let start = CACurrentMediaTime() + context.staggerDelay
        scramble(layer, from: start, until: start + context.timing.duration, settles: true)
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 1, to: 0,
                                    duration: context.timing.duration * 0.6),
                  forKey: "morph.out.opacity")
        let start = CACurrentMediaTime() + context.staggerDelay
        scramble(layer, from: start, until: start + context.timing.duration * 0.5, settles: false)
    }

    private func scramble(_ layer: CATextLayer,
                          from start: CFTimeInterval,
                          until end: CFTimeInterval,
                          settles: Bool) {
        let pool = characters
        guard !pool.isEmpty else { return }
        ScrambleTicker.shared.add(ScrambleTicker.Entry(
            layer: layer,
            start: start,
            end: end,
            pool: pool,
            settles: settles,
            interval: tickInterval
        ))
    }
}

/// Drives every scrambling glyph from one timer.
///
/// A timer per glyph layer was the first shape, and a forty-character rename ran eighty of them
/// on the main run loop for the length of its stagger, each ticking idle until its own start. One
/// ticker per process does the same work in one callback and stops itself when the last glyph
/// settles, so the cost is bounded by the glyphs mid-scramble rather than by the timers alive.
///
/// The swap is drawn, not merely assigned. The label's characters are `GlyphLayer`s that raster
/// their slot's character themselves — setting `string` on one changed nothing on screen, so the
/// decoder only ever faded — and a glyph layer is handed a transient character to draw instead.
/// A plain `CATextLayer` still gets its `string` swapped.
final class ScrambleTicker {

    struct Entry {
        weak var layer: CATextLayer?
        let start: CFTimeInterval
        let end: CFTimeInterval
        let pool: [Character]
        /// Whether the layer returns to its own character at the end (an incoming glyph) or is
        /// left mid-scramble to fade out (an outgoing one).
        let settles: Bool
        let interval: TimeInterval
        /// The plain-text layer's own string, restored when it settles.
        var original: Any?
    }

    /// Main-thread only, like every layer it touches.
    static let shared = ScrambleTicker()

    private var entries: [Entry] = []
    private var timer: Timer?

    /// How many glyphs are mid-scramble — the bound on one tick's work.
    var activeCount: Int { entries.count }

    /// Whether a timer is scheduled; false once every glyph has settled.
    var isRunning: Bool { timer != nil }

    func add(_ entry: Entry) {
        var entry = entry
        if !(entry.layer is GlyphLayer) {
            entry.original = entry.layer?.string
        }
        entries.append(entry)
        startIfNeeded(interval: entry.interval)
    }

    private func startIfNeeded(interval: TimeInterval) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One pass over the glyphs mid-scramble; also the test seam.
    func tick(now: CFTimeInterval = CACurrentMediaTime()) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        entries.removeAll { entry in
            guard let layer = entry.layer, layer.superlayer != nil else { return true }
            guard now >= entry.start else { return false }
            if now >= entry.end {
                if entry.settles { Self.show(nil, on: layer, original: entry.original) }
                return true
            }
            let glyph = entry.pool.randomElement().map(String.init)
            Self.show(glyph, on: layer, original: entry.original)
            return false
        }
        CATransaction.commit()
        if entries.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Draws `glyph` in the layer's place, or its own character again when nil.
    private static func show(_ glyph: String?, on layer: CATextLayer, original: Any?) {
        if let glyphLayer = layer as? GlyphLayer {
            glyphLayer.transientCharacter = glyph
        } else if let glyph,
                  let current = layer.string as? NSAttributedString, current.length > 0 {
            let attributes = current.attributes(at: 0, effectiveRange: nil)
            layer.string = NSAttributedString(string: glyph, attributes: attributes)
        } else if glyph == nil, let original {
            layer.string = original
        }
    }
}
