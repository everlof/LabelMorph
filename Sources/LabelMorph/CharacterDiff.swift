/// Matches characters between the old and new text so unchanged characters
/// can fly to their new position instead of fading out and back in.
enum CharacterDiff {

    struct Result {
        var moves: [(from: Int, to: Int)] = []
        var removals: [Int] = []
        var insertions: [Int] = []
    }

    /// Greedy matching: each new character claims the nearest unused old
    /// character with the same value. `matchDistanceLimit` caps how far apart
    /// (in character indices) a match may be; pass `nil` for unlimited and
    /// `0` to only keep characters that stay at the same index.
    static func compute(old: [String], new: [String], matchDistanceLimit: Int? = nil) -> Result {
        var result = Result()
        var usedOld = [Bool](repeating: false, count: old.count)

        for (newIndex, character) in new.enumerated() {
            var best: Int?
            for (oldIndex, oldCharacter) in old.enumerated()
            where !usedOld[oldIndex] && oldCharacter == character {
                if let limit = matchDistanceLimit, abs(oldIndex - newIndex) > limit { continue }
                if let current = best {
                    if abs(oldIndex - newIndex) < abs(current - newIndex) { best = oldIndex }
                } else {
                    best = oldIndex
                }
            }
            if let match = best {
                usedOld[match] = true
                result.moves.append((from: match, to: newIndex))
            } else {
                result.insertions.append(newIndex)
            }
        }

        result.removals = old.indices.filter { !usedOld[$0] }
        return result
    }
}
