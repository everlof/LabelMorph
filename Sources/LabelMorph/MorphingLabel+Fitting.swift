import AppKit

public extension MorphingLabel {

    /// The width of the line this label would actually **draw** in a slot `available` points
    /// wide — the whole text where it fits, or the ellipsized head `.tail` shortens it to.
    ///
    /// This is the counterpart to `intrinsicContentSize`, which reports the width the label
    /// *wants*. The two differ by more than the obvious amount whenever truncation is in play,
    /// because tail truncation lands on a character boundary: the head that fits is up to one
    /// character narrower than the room it was offered, and the remainder is dead space inside
    /// the slot. A host that caps its own width — a tab, a chip — has to size itself to the
    /// line that lands rather than to the slot it handed over, or that remainder shows up as
    /// space between the title and whatever follows it, varying with the title.
    ///
    /// `.none` reports the full line whatever the slot: an untruncated label draws past its
    /// bounds rather than shortening, so that *is* what it draws.
    func width(fitting available: CGFloat) -> CGFloat {
        let full = CharacterLayout.measure(text, font: font).width
        guard truncation == .tail, available > 0, full > available else { return full }
        let shortened = CharacterLayout.tailTruncated(text, font: font, width: available)
        return CharacterLayout.measure(shortened, font: font).width
    }

    /// What `intrinsicContentSize` would report for a string this label does not hold yet.
    ///
    /// For a host that has to resize **before** a morph rather than because of one. A morph is
    /// built against the bounds the text will settle in, so a host holding several of these —
    /// a block of lines sharing one width — has to know where they are all going before the
    /// first one starts moving. Measured after the fact, the width arrives mid-animation and
    /// every line re-lays out under its own glyphs.
    func naturalWidth(of candidate: String) -> CGFloat {
        ceil(CharacterLayout.measure(candidate, font: font).width)
    }
}
