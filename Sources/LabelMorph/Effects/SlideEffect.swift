import QuartzCore

/// Characters slide in from one side and continue out the other, fading as
/// they go.
public final class SlideEffect: TextMorphEffect {

    public enum Direction {
        case up, down, left, right
    }

    public var direction: Direction

    /// Slide distance as a multiple of the font point size.
    public var distanceFactor: CGFloat

    public init(direction: Direction = .up, distanceFactor: CGFloat = 0.8) {
        self.direction = direction
        self.distanceFactor = distanceFactor
    }

    private func startOffset(for font: MorphFont) -> CGVector {
        let distance = font.pointSize * distanceFactor
        switch direction {
        case .up: return CGVector(dx: 0, dy: -distance)
        case .down: return CGVector(dx: 0, dy: distance)
        case .left: return CGVector(dx: distance, dy: 0)
        case .right: return CGVector(dx: -distance, dy: 0)
        }
    }

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        let offset = startOffset(for: context.font)
        layer.add(context.animation("transform.translation",
                                    from: morphSizeValue(CGSize(width: offset.dx, height: offset.dy)),
                                    to: morphSizeValue(.zero)),
                  forKey: "morph.in.translation")
        layer.add(context.animation("opacity", from: 0, to: 1), forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        let offset = startOffset(for: context.font)
        layer.add(context.animation("transform.translation",
                                    from: morphSizeValue(.zero),
                                    to: morphSizeValue(CGSize(width: -offset.dx, height: -offset.dy))),
                  forKey: "morph.out.translation")
        layer.add(context.animation("opacity", from: 1, to: 0), forKey: "morph.out.opacity")
    }
}
