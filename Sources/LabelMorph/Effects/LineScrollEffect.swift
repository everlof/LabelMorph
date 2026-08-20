import QuartzCore

/// The complete old line scrolls and fades out while the complete new line
/// scrolls and fades in from the opposite edge.
///
/// Every glyph receives the same animations with the same start time. The
/// glyphs therefore retain their spacing and read as one moving line rather
/// than as a character cascade.
public final class LineScrollEffect: WholeLineMorphEffect {

    public enum Direction {
        case up, down
    }

    public var direction: Direction

    /// Travel distance as a multiple of the font point size.
    public var distanceFactor: CGFloat

    public init(direction: Direction = .up, distanceFactor: CGFloat = 1) {
        self.direction = direction
        self.distanceFactor = distanceFactor
    }

    public var settleMargin: CFTimeInterval { 0 }

    public func animateLineTransition(from outgoing: [CATextLayer],
                                      to incoming: [CATextLayer],
                                      in container: CALayer,
                                      context: MorphContext) {
        let distance = context.font.pointSize * distanceFactor
        let incomingOffset: CGFloat = direction == .up ? -distance : distance
        let outgoingOffset = -incomingOffset
        let beginTime = CACurrentMediaTime()

        let incomingMove = context.animation(
            "transform.translation",
            from: morphSizeValue(CGSize(width: 0, height: incomingOffset)),
            to: morphSizeValue(.zero),
            delay: 0
        )
        let incomingFade = context.animation("opacity", from: 0, to: 1, delay: 0)
        incomingMove.beginTime = beginTime
        incomingFade.beginTime = beginTime
        for layer in incoming {
            layer.add(incomingMove, forKey: "morph.line.in.translation")
            layer.add(incomingFade, forKey: "morph.line.in.opacity")
        }

        let outgoingMove = context.animation(
            "transform.translation",
            from: morphSizeValue(.zero),
            to: morphSizeValue(CGSize(width: 0, height: outgoingOffset)),
            delay: 0
        )
        let outgoingFade = context.animation("opacity", from: 1, to: 0, delay: 0)
        outgoingMove.beginTime = beginTime
        outgoingFade.beginTime = beginTime
        for layer in outgoing {
            layer.add(outgoingMove, forKey: "morph.line.out.translation")
            layer.add(outgoingFade, forKey: "morph.line.out.opacity")
        }
    }
}
