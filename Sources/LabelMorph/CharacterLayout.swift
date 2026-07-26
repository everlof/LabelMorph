import AppKit
import CoreText

/// The position of a single character (glyph cluster) within a laid-out line.
struct CharacterSlot {
    let character: String
    let frame: CGRect
    let isWhitespace: Bool
}

/// Lays out a single line of text with Core Text and returns per-character frames.
enum CharacterLayout {

    /// The single character an ellipsized line ends with. One glyph rather than three
    /// periods, so it occupies one slot and morphs as one thing.
    static let ellipsis = "\u{2026}"

    static func textAttributes(font: NSFont, color: CGColor? = nil) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .ligature: 0,
        ]
        if let color {
            attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
        }
        return attributes
    }

    static func measure(_ text: String, font: NSFont) -> CGSize {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        guard !text.isEmpty else {
            return CGSize(width: 0, height: font.ascender - font.descender)
        }
        let width = CGFloat(CTLineGetTypographicBounds(makeLine(text, font: font), &ascent, &descent, &leading))
        return CGSize(width: width, height: ascent + descent)
    }

    /// The longest head of `text` that fits `width` once an ellipsis is appended, or the
    /// text unchanged when it already fits.
    ///
    /// Core Text is asked which character sits at the budget offset rather than searched
    /// for it: one line, one index lookup, no repeated measuring per candidate length. That
    /// answer snaps to the nearest character boundary and knows nothing of the kerning
    /// against an ellipsis that is not in the line yet, so the candidate is measured and
    /// stepped back by whole composed characters until it genuinely fits — normally not at
    /// all, and never far.
    static func tailTruncated(_ text: String, font: NSFont, width: CGFloat) -> String {
        guard width > 0 else { return "" }
        guard measure(text, font: font).width > width else { return text }

        let ellipsisWidth = measure(ellipsis, font: font).width
        guard ellipsisWidth <= width else { return "" }

        let nsText = text as NSString
        var cut = CTLineGetStringIndexForPosition(
            makeLine(text, font: font),
            CGPoint(x: width - ellipsisWidth, y: 0)
        )
        if cut == kCFNotFound { cut = nsText.length }
        cut = max(0, min(cut, nsText.length))

        while cut > 0 {
            // A head ending in a space would set the ellipsis adrift from the word it
            // shortens, so the gap goes with the characters it separated.
            let head = nsText.substring(to: cut).replacingOccurrences(
                of: "\\s+$",
                with: "",
                options: .regularExpression
            )
            let candidate = head + ellipsis
            if measure(candidate, font: font).width <= width { return candidate }

            // Back up by a composed character sequence rather than a UTF-16 unit, or a cut
            // can land inside a surrogate pair or between a base and its combining mark.
            cut = nsText.rangeOfComposedCharacterSequence(at: cut - 1).location
        }
        return ellipsis
    }

    /// All slots except whitespace, in visual order. Whitespace still affects
    /// the position of surrounding characters but gets no layer of its own.
    static func visibleSlots(for text: String,
                             font: NSFont,
                             bounds: CGRect,
                             alignment: NSTextAlignment) -> [CharacterSlot] {
        allSlots(for: text, font: font, bounds: bounds, alignment: alignment).filter { !$0.isWhitespace }
    }

    static func allSlots(for text: String,
                         font: NSFont,
                         bounds: CGRect,
                         alignment: NSTextAlignment) -> [CharacterSlot] {
        guard !text.isEmpty else { return [] }

        let nsText = text as NSString
        let line = makeLine(text, font: font)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let lineHeight = ascent + descent

        let originX: CGFloat
        switch alignment {
        case .right:
            originX = bounds.maxX - lineWidth
        case .center:
            originX = bounds.minX + (bounds.width - lineWidth) / 2
        default:
            originX = bounds.minX
        }
        let originY = bounds.minY + (bounds.height - lineHeight) / 2

        var slots: [CharacterSlot] = []
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            CTRunGetAdvances(run, CFRange(location: 0, length: glyphCount), &advances)
            var indices = [CFIndex](repeating: 0, count: glyphCount)
            CTRunGetStringIndices(run, CFRange(location: 0, length: glyphCount), &indices)
            let stringRange = CTRunGetStringRange(run)

            for glyph in 0..<glyphCount {
                let start = indices[glyph]
                let end = glyph + 1 < glyphCount ? indices[glyph + 1] : stringRange.location + stringRange.length
                // Right-to-left runs produce descending indices; skip rather than crash.
                guard end > start else { continue }

                let character = nsText.substring(with: NSRange(location: start, length: end - start))
                let frame = CGRect(x: originX + positions[glyph].x,
                                   y: originY,
                                   width: advances[glyph].width,
                                   height: lineHeight)
                slots.append(CharacterSlot(
                    character: character,
                    frame: frame,
                    isWhitespace: character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ))
            }
        }
        return slots
    }

    private static func makeLine(_ text: String, font: NSFont) -> CTLine {
        let attributed = NSAttributedString(string: text, attributes: textAttributes(font: font))
        return CTLineCreateWithAttributedString(attributed)
    }
}
