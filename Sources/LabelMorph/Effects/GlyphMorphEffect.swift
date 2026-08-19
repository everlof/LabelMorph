import CoreText
import QuartzCore

/// The old glyph's outline is broken into contours and morphed into the new
/// glyph's outline at the character's position. Added characters grow out of
/// points; removed characters collapse into them.
///
/// During the morph a `CAShapeLayer` stands in for the character; the crisp
/// `CATextLayer` takes over the instant the shape animation completes.
public final class GlyphMorphEffect: TextReplacementMorphEffect {

    /// Sampling resolution per contour. Higher is smoother but heavier.
    public var pointsPerContour: Int

    public init(pointsPerContour: Int = 72) {
        self.pointsPerContour = max(16, pointsPerContour)
    }

    public var settleMargin: CFTimeInterval { 0.5 }

    // MARK: - TextReplacementMorphEffect

    public func animateReplace(from oldLayer: CATextLayer,
                               to newLayer: CATextLayer,
                               in container: CALayer,
                               context: MorphContext) {
        addShapeMorph(from: glyphPath(of: oldLayer),
                      to: glyphPath(of: newLayer),
                      styledAfter: newLayer,
                      in: container,
                      context: context,
                      fadesOut: false)
        conceal(newLayer, for: context.staggerDelay + context.timing.duration, context: context)
    }

    // MARK: - TextMorphEffect

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        guard let container = layer.superlayer, let target = glyphPath(of: layer) else {
            layer.add(context.animation("opacity", from: 0, to: 1), forKey: "morph.in")
            return
        }
        addShapeMorph(from: nil, to: target, styledAfter: layer,
                      in: container, context: context, fadesOut: false)
        conceal(layer, for: context.staggerDelay + context.timing.duration, context: context)
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        guard let container = layer.superlayer, let source = glyphPath(of: layer) else {
            layer.add(context.animation("opacity", from: 1, to: 0), forKey: "morph.out")
            return
        }
        // The label hides the outgoing text layer; the shape stands in for it
        // while collapsing.
        addShapeMorph(from: source, to: nil, styledAfter: layer,
                      in: container, context: context, fadesOut: true)
    }

    // MARK: - Internals

    private func glyphPath(of layer: CATextLayer) -> CGPath? {
        guard let attributed = layer.string as? NSAttributedString, attributed.length > 0 else {
            return nil
        }
        // A glyph layer's frame is padded for ink overhang and snapped to the
        // pixel grid, so it is a tile rather than a set of metrics. The outline
        // belongs in the box Core Text laid the glyph out in, which the slot
        // keeps alongside it.
        let box = (layer as? GlyphLayer)?.slot?.inkFrame ?? layer.frame
        return GlyphPath.path(for: attributed, at: box)
    }

    /// Hides a text layer until its stand-in shape finishes morphing.
    private func conceal(_ layer: CATextLayer, for interval: CFTimeInterval, context: MorphContext) {
        layer.add(context.animation("opacity", from: 0, to: 0, delay: 0, duration: interval),
                  forKey: "morph.conceal")
    }

    private func addShapeMorph(from source: CGPath?,
                               to target: CGPath?,
                               styledAfter textLayer: CATextLayer,
                               in container: CALayer,
                               context: MorphContext,
                               fadesOut: Bool) {
        guard source != nil || target != nil else { return }
        let (a, b) = GlyphPath.morphablePair(from: source, to: target,
                                             pointsPerContour: pointsPerContour)

        let shape = CAShapeLayer()
        shape.name = MorphTransientLayer.name
        shape.frame = container.bounds
        shape.contentsScale = textLayer.contentsScale
        shape.fillColor = fillColor(of: textLayer)
        shape.fillRule = .evenOdd
        shape.strokeColor = nil
        shape.actions = ["path": NSNull(), "opacity": NSNull(),
                         "position": NSNull(), "bounds": NSNull()]
        shape.path = b
        shape.opacity = 0
        container.addSublayer(shape)

        shape.add(context.animation("path", from: a, to: b), forKey: "morph.path")

        let visibleInterval = context.staggerDelay + context.timing.duration
        if fadesOut {
            shape.add(context.animation("opacity", from: 1, to: 0), forKey: "morph.visibility")
        } else {
            // Fully visible from the moment of commit until this character's
            // morph completes, then the model's opacity of 0 takes over and
            // the concealed text layer reappears in the same instant.
            shape.add(context.animation("opacity", from: 1, to: 1, delay: 0,
                                        duration: visibleInterval,
                                        timingFunction: CAMediaTimingFunction(name: .linear)),
                      forKey: "morph.visibility")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + visibleInterval + 0.4) { [weak shape] in
            shape?.removeFromSuperlayer()
        }
    }

    private func fillColor(of layer: CATextLayer) -> CGColor {
        if let attributed = layer.string as? NSAttributedString, attributed.length > 0,
           let color = attributed.attribute(
               NSAttributedString.Key(kCTForegroundColorAttributeName as String),
               at: 0, effectiveRange: nil) {
            return color as! CGColor
        }
        return MorphColor.morphLabelColor.cgColor
    }
}
