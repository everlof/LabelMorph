import Foundation

/// How a line that overruns the label's width is shortened.
///
/// `MorphingLabel` lays a whole line out with Core Text and positions every character from
/// the bounds' leading edge, so text longer than the view simply runs past it. A host that
/// clips its layer then cuts the line dead, mid-glyph, with nothing to say it was shortened
/// — so any label narrower than its own content wants `.tail`.
public enum MorphTruncation {

    /// Lay the whole line out, whatever its width.
    case none

    /// Keep the longest head that fits and end it with an ellipsis.
    ///
    /// The ellipsis becomes an ordinary character of the laid-out line, so it is diffed and
    /// morphed like any other — two long names that shorten to the same head animate only
    /// where they actually differ.
    case tail
}
