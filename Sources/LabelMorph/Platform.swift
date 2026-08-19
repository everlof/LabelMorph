#if canImport(AppKit)
import AppKit

public typealias MorphFont = NSFont
public typealias MorphColor = NSColor
public typealias MorphView = NSView

extension MorphColor {
    static var morphLabelColor: MorphColor { .labelColor }
}

func morphSizeValue(_ size: CGSize) -> NSValue {
    NSValue(size: size)
}
#elseif canImport(UIKit)
import UIKit

public typealias MorphFont = UIFont
public typealias MorphColor = UIColor
public typealias MorphView = UIView

extension MorphColor {
    static var morphLabelColor: MorphColor { .label }
}

func morphSizeValue(_ size: CGSize) -> NSValue {
    NSValue(cgSize: size)
}
#endif
