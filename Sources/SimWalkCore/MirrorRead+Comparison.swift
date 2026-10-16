//
// Copyright © Agulhas Labs
//

import Foundation

public extension MirrorRead {
    /// The top of the window, as a fraction of its height, that holds the phone's status bar: lines whose `centreY` is inside it are served but never compared.
    ///
    /// **Measured live on 2026-10-14** in the 383×843 pt Mirroring window: the status-bar clock centres at y 0.077–0.079 (`11:45` at .077, the battery `58` at .078) and the first app content line sits at 0.13 or lower (`6 Jul - 11 Oct` at .141, a large title at .132). The window's 38 pt transparent top border sits above the phone's screen, which the earlier 0.06 (the screen alone) left out, so the clock counted as a change on every read that crossed a minute.
    static let statusBandFraction = 0.105

    /// How far apart, as a fraction of the window, two reads may place the same line and still agree.
    ///
    /// 0.01 is about 14 px on a 1430 px capture: wider than the recogniser's jitter on an unmoved line (a box edge shifts a pixel or two between two captures), narrower than a scroll's momentum, which moves a line by a visible step and is the reason positions are compared at all — a scroll changes where lines are without changing what they say.
    static let positionTolerance = 0.01

    /// What `after` gained and lost against `before`.
    struct Change: Equatable, Sendable {
        /// Texts present in `after` more times than in `before`, one entry per extra occurrence.
        public let added: [String]
        /// Texts present in `before` more times than in `after`, one entry per missing occurrence.
        public let gone: [String]

        /// Whether nothing was added and nothing is gone.
        public var isEmpty: Bool {
            added.isEmpty && gone.isEmpty
        }
    }

    /// The lines that take part in a comparison: everything below the status bar that the recogniser was sure of.
    var comparableLines: [MirrorTextLine] {
        comparableIndexes.map { lines[$0] }
    }

    /// Whether `other` shows the same screen: the same texts in the same order outside the status band (equivalent per `MirrorTextLine.isSameText(as:)`), every pair of centres within `positionTolerance`.
    func agrees(with other: MirrorRead) -> Bool {
        let mine = comparableLines
        let theirs = other.comparableLines
        guard mine.count == theirs.count else { return false }
        return zip(mine, theirs).allSatisfy { a, b in
            a.isSameText(as: b)
                && abs(a.centreX - b.centreX) <= Self.positionTolerance
                && abs(a.centreY - b.centreY) <= Self.positionTolerance
        }
    }

    /// The text that appeared and the text that went between `before` and this read, compared as multisets of equivalent lines outside the status band.
    func change(from before: MirrorRead) -> Change {
        let unmatched = unmatchedLines(against: before)
        return Change(added: unmatched.added.map { lines[$0].text }, gone: unmatched.gone.map { before.lines[$0].text })
    }

    /// The indexes into `lines` of the comparable lines that have no equivalent in `before`: what `change` reports as added, and what the residue marks `+`.
    func addedIndexes(from before: MirrorRead) -> [Int] {
        unmatchedLines(against: before).added
    }

    private var comparableIndexes: [Int] {
        lines.indices.filter { lines[$0].centreY >= Self.statusBandFraction && lines[$0].isComparable }
    }

    /// A greedy match in reading order: each line here takes the first unclaimed equivalent line of `before`; what is left on either side is added or gone.
    private func unmatchedLines(against before: MirrorRead) -> (added: [Int], gone: [Int]) {
        var unclaimed = before.comparableIndexes
        var added: [Int] = []
        for index in comparableIndexes {
            if let hit = unclaimed.firstIndex(where: { before.lines[$0].isSameText(as: lines[index]) }) {
                unclaimed.remove(at: hit)
            } else {
                added.append(index)
            }
        }
        return (added, unclaimed)
    }
}
