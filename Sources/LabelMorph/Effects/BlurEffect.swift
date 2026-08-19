#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreImage
import QuartzCore

/// Characters sharpen into focus from a gaussian blur and dissolve back into
/// one on the way out. AppKit supplies the Core Image filter through
/// `layerUsesCoreImageFilters`; UIKit keeps the accompanying opacity transition.
public final class BlurEffect: TextMorphEffect {

    public var maxRadius: CGFloat

    public init(maxRadius: CGFloat = 18) {
        self.maxRadius = maxRadius
    }

    private func installFilter(on layer: CALayer, radius: CGFloat) {
#if canImport(AppKit)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.name = "blur"
        layer.filters = [filter]
#endif
    }

    public func animateIn(_ layer: CATextLayer, context: MorphContext) {
        installFilter(on: layer, radius: 0)
#if canImport(AppKit)
        layer.add(context.animation("filters.blur.inputRadius", from: maxRadius, to: 0),
                  forKey: "morph.in.blur")
#endif
        layer.add(context.animation("opacity", from: 0, to: 1), forKey: "morph.in.opacity")
    }

    public func animateOut(_ layer: CATextLayer, context: MorphContext) {
        installFilter(on: layer, radius: 0)
#if canImport(AppKit)
        layer.add(context.animation("filters.blur.inputRadius", from: 0, to: maxRadius),
                  forKey: "morph.out.blur")
#endif
        layer.add(context.animation("opacity", from: 1, to: 0), forKey: "morph.out.opacity")
    }
}
