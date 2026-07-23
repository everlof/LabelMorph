import AppKit
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

    private func startOffset(for font: NSFont) -> CGVector {
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
                                    from: NSValue(size: NSSize(width: offset.dx, height: offset.dy)),
                                    to: NSValue(size: .zero)),
                  forKey: "morph.in.translation")
        layer.add(context.animation("opacity", from: 0, to: 1), forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        let offset = startOffset(for: context.font)
        layer.add(context.animation("transform.translation",
                                    from: NSValue(size: .zero),
                                    to: NSValue(size: NSSize(width: -offset.dx, height: -offset.dy))),
                  forKey: "morph.out.translation")
        layer.add(context.animation("opacity", from: 1, to: 0), forKey: "morph.out.opacity")
    }
}
