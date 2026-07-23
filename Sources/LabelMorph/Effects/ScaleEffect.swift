import AppKit
import QuartzCore

/// New characters zoom in from small while old characters blow up and fade.
public final class ScaleEffect: TextMorphEffect {

    public var inFromScale: CGFloat
    public var outToScale: CGFloat

    public init(inFromScale: CGFloat = 0.3, outToScale: CGFloat = 1.6) {
        self.inFromScale = inFromScale
        self.outToScale = outToScale
    }

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("transform.scale", from: inFromScale, to: 1), forKey: "morph.in.scale")
        layer.add(context.animation("opacity", from: 0, to: 1), forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        layer.add(context.animation("transform.scale", from: 1, to: outToScale), forKey: "morph.out.scale")
        layer.add(context.animation("opacity", from: 1, to: 0), forKey: "morph.out.opacity")
    }
}
