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
        scramble(layer,
                 from: start,
                 until: start + context.timing.duration,
                 finalString: layer.string as? NSAttributedString)
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("opacity", from: 1, to: 0,
                                    duration: context.timing.duration * 0.6),
                  forKey: "morph.out.opacity")
        let start = CACurrentMediaTime() + context.staggerDelay
        scramble(layer,
                 from: start,
                 until: start + context.timing.duration * 0.5,
                 finalString: nil)
    }

    /// Swaps the layer's glyph for a random one until `end`, then restores
    /// `finalString` (if any). The timer dies with the layer.
    private func scramble(_ layer: CATextLayer,
                          from start: CFTimeInterval,
                          until end: CFTimeInterval,
                          finalString: NSAttributedString?) {
        guard let current = layer.string as? NSAttributedString, current.length > 0 else { return }
        let attributes = current.attributes(at: 0, effectiveRange: nil)
        let pool = characters

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak layer] timer in
            guard let layer, layer.superlayer != nil else {
                timer.invalidate()
                return
            }
            let now = CACurrentMediaTime()
            guard now >= start else { return }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if now >= end {
                if let finalString { layer.string = finalString }
                timer.invalidate()
            } else {
                let glyph = pool.randomElement().map(String.init) ?? "•"
                layer.string = NSAttributedString(string: glyph, attributes: attributes)
            }
            CATransaction.commit()
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
