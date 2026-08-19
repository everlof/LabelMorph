import Foundation
import CoreText

/// Extracts glyph outlines and prepares structurally identical path pairs so
/// Core Animation can interpolate one glyph's shape into another's.
///
/// CAShapeLayer only tweens paths with matching element structure, so both
/// sides are normalized: every contour is resampled to a fixed number of
/// points, contours are paired by size (missing ones collapse to a point at
/// their partner's centroid), windings are aligned, and each contour's start
/// point is rotated to minimize travel.
enum GlyphPath {

    /// Outline of `attributed` (a single glyph cluster) positioned inside
    /// `frame` — the character slot frame produced by `CharacterLayout`.
    static func path(for attributed: NSAttributedString, at frame: CGRect) -> CGPath? {
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let baseline: CGPoint
#if canImport(AppKit)
        baseline = CGPoint(x: frame.minX, y: frame.minY + descent)
#else
        // Core Text glyph outlines are y-up. UIKit layers are y-down, so their baseline is
        // measured from the slot's bottom and the outline is reflected across it.
        baseline = CGPoint(x: frame.minX, y: frame.maxY - descent)
#endif

        let result = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)

            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let anyFont = attributes[kCTFontAttributeName as String],
                  CFGetTypeID(anyFont as CFTypeRef) == CTFontGetTypeID() else { continue }
            let runFont = anyFont as! CTFont

            for index in 0..<glyphCount {
                guard let outline = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                let transform: CGAffineTransform
#if canImport(AppKit)
                transform = CGAffineTransform(
                    translationX: baseline.x + positions[index].x,
                    y: baseline.y + positions[index].y
                )
#else
                transform = CGAffineTransform(
                    a: 1,
                    b: 0,
                    c: 0,
                    d: -1,
                    tx: baseline.x + positions[index].x,
                    ty: baseline.y - positions[index].y
                )
#endif
                result.addPath(outline, transform: transform)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// Returns two paths with identical element structure that interpolate
    /// cleanly. A `nil` side produces contours collapsed to points, so glyphs
    /// grow from or shrink into dots.
    static func morphablePair(from source: CGPath?,
                              to target: CGPath?,
                              pointsPerContour: Int) -> (CGPath, CGPath) {
        var a = contours(of: source, pointsPerContour: pointsPerContour)
        var b = contours(of: target, pointsPerContour: pointsPerContour)

        a.sort { abs(signedArea($0)) > abs(signedArea($1)) }
        b.sort { abs(signedArea($0)) > abs(signedArea($1)) }

        let count = max(a.count, b.count)
        while a.count < count {
            a.append([CGPoint](repeating: centroid(b[a.count]), count: pointsPerContour))
        }
        while b.count < count {
            b.append([CGPoint](repeating: centroid(a[b.count]), count: pointsPerContour))
        }

        for index in 0..<count {
            var partner = b[index]
            // Same winding per pair; holes stay holes thanks to even-odd fill.
            if signedArea(partner) * signedArea(a[index]) < 0 {
                partner.reverse()
            }
            b[index] = rotated(partner, toAlignWith: a[index])
        }

        return (build(a), build(b))
    }

    // MARK: - Sampling

    private static func contours(of path: CGPath?, pointsPerContour: Int) -> [[CGPoint]] {
        guard let path else { return [] }
        var raw: [[CGPoint]] = []
        var current: [CGPoint] = []
        var lastPoint = CGPoint.zero
        let curveSamples = 12

        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                if current.count > 2 { raw.append(current) }
                current = [element.points[0]]
                lastPoint = element.points[0]
            case .addLineToPoint:
                current.append(element.points[0])
                lastPoint = element.points[0]
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                for step in 1...curveSamples {
                    let t = CGFloat(step) / CGFloat(curveSamples)
                    current.append(quadraticPoint(lastPoint, control, end, t))
                }
                lastPoint = end
            case .addCurveToPoint:
                let control1 = element.points[0]
                let control2 = element.points[1]
                let end = element.points[2]
                for step in 1...curveSamples {
                    let t = CGFloat(step) / CGFloat(curveSamples)
                    current.append(cubicPoint(lastPoint, control1, control2, end, t))
                }
                lastPoint = end
            case .closeSubpath:
                if current.count > 2 { raw.append(current) }
                if let first = current.first { lastPoint = first }
                current = []
            @unknown default:
                break
            }
        }
        if current.count > 2 { raw.append(current) }

        return raw.map { resample($0, to: pointsPerContour) }
    }

    /// Evenly redistributes a closed contour's points by arc length.
    private static func resample(_ points: [CGPoint], to count: Int) -> [CGPoint] {
        guard let first = points.first else { return [] }
        let closed = points + [first]
        var cumulative: [CGFloat] = [0]
        for index in 1..<closed.count {
            cumulative.append(cumulative[index - 1] + distance(closed[index - 1], closed[index]))
        }
        guard let total = cumulative.last, total > 0 else {
            return [CGPoint](repeating: first, count: count)
        }
        var result: [CGPoint] = []
        var segment = 0
        for index in 0..<count {
            let target = total * CGFloat(index) / CGFloat(count)
            while segment < closed.count - 2 && cumulative[segment + 1] < target { segment += 1 }
            let span = max(cumulative[segment + 1] - cumulative[segment], .ulpOfOne)
            let t = (target - cumulative[segment]) / span
            result.append(interpolate(closed[segment], closed[segment + 1], t))
        }
        return result
    }

    /// Rotates the contour's start index so points travel the least distance
    /// to their counterparts in `reference`.
    private static func rotated(_ contour: [CGPoint], toAlignWith reference: [CGPoint]) -> [CGPoint] {
        let count = reference.count
        guard contour.count == count, count > 0 else { return contour }
        var bestOffset = 0
        var bestScore = CGFloat.greatestFiniteMagnitude
        for offset in 0..<count {
            var score: CGFloat = 0
            for index in 0..<count {
                let p = reference[index]
                let q = contour[(index + offset) % count]
                let dx = p.x - q.x
                let dy = p.y - q.y
                score += dx * dx + dy * dy
                if score >= bestScore { break }
            }
            if score < bestScore {
                bestScore = score
                bestOffset = offset
            }
        }
        guard bestOffset != 0 else { return contour }
        return (0..<count).map { contour[($0 + bestOffset) % count] }
    }

    // MARK: - Geometry helpers

    private static func signedArea(_ contour: [CGPoint]) -> CGFloat {
        guard contour.count > 2 else { return 0 }
        var area: CGFloat = 0
        for index in 0..<contour.count {
            let p = contour[index]
            let q = contour[(index + 1) % contour.count]
            area += p.x * q.y - q.x * p.y
        }
        return area / 2
    }

    private static func centroid(_ contour: [CGPoint]) -> CGPoint {
        guard !contour.isEmpty else { return .zero }
        var sum = CGPoint.zero
        for point in contour {
            sum.x += point.x
            sum.y += point.y
        }
        return CGPoint(x: sum.x / CGFloat(contour.count), y: sum.y / CGFloat(contour.count))
    }

    private static func build(_ contours: [[CGPoint]]) -> CGPath {
        let path = CGMutablePath()
        for contour in contours {
            guard let first = contour.first else { continue }
            path.move(to: first)
            for point in contour.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func quadraticPoint(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x,
                       y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
    }

    private static func cubicPoint(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p1.x
        let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p1.y
        return CGPoint(x: x, y: y)
    }
}
