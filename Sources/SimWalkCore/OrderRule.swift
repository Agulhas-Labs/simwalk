//
// Copyright © Agulhas Labs
//

import Foundation

/// Content sections drawn in a different relative order: among the sections both sides have, the ones that are not where the reference has them.
///
/// Bars are left out — they are pinned by the system, not ordered by the app — and so is a section on one side only, which is the presence rule's finding and does not make its neighbours move. The sections that stay put are the longest run the two orders share; the rest are flagged, so a card that moved is one flag rather than one for every card it passed.
public struct OrderRule: FormRule {
    public init() {}

    /// One flag per moved section, in the run's order.
    public func flags(reference: SegmentedCapture, run: SegmentedCapture) -> [FormFlag] {
        let referenceKeys = Set(reference.contentSections.map(\.key))
        let runKeys = Set(run.contentSections.map(\.key))
        let referenceShared = reference.contentSections.map(\.key).filter(runKeys.contains)
        let runShared = run.contentSections.map(\.key).filter(referenceKeys.contains)
        guard referenceShared != runShared else { return [] }
        let staying = Set(Self.longestCommonSubsequence(referenceShared, runShared))
        return runShared.enumerated().compactMap { runIndex, key in
            guard !staying.contains(key),
                  let referenceIndex = referenceShared.firstIndex(of: key),
                  let referenceSection = reference.section(keyed: key),
                  let runSection = run.section(keyed: key) else { return nil }
            return FormFlag(
                key: key,
                finding: .moved(referencePosition: referenceIndex + 1, runPosition: runIndex + 1, shared: runShared.count),
                crops: [reference.crop(of: referenceSection, side: .reference), run.crop(of: runSection, side: .run)]
            )
        }
    }

    /// The longest sequence of keys both orders hold in the same relative order; among equally long ones, the one found first from the front of both.
    static func longestCommonSubsequence(_ first: [String], _ second: [String]) -> [String] {
        guard !first.isEmpty, !second.isEmpty else { return [] }
        var lengths = Array(repeating: Array(repeating: 0, count: second.count + 1), count: first.count + 1)
        for row in stride(from: first.count - 1, through: 0, by: -1) {
            for column in stride(from: second.count - 1, through: 0, by: -1) {
                lengths[row][column] = first[row] == second[column]
                    ? lengths[row + 1][column + 1] + 1
                    : max(lengths[row + 1][column], lengths[row][column + 1])
            }
        }
        var common: [String] = []
        var row = 0
        var column = 0
        while row < first.count, column < second.count {
            if first[row] == second[column] {
                common.append(first[row])
                row += 1
                column += 1
            } else if lengths[row + 1][column] >= lengths[row][column + 1] {
                row += 1
            } else {
                column += 1
            }
        }
        return common
    }
}
