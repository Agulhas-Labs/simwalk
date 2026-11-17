//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a screen's captures show the values its walkbook `expectValues`, judged by the nodes' `label`, `identifier` and `value` in each tree (SimWalk#259).
///
/// **Why a value needs its own check.** Route steps and `expect` read labels and identifiers, never values, so a walkbook that saves a lesson and returns home to prove its node now reads `Done` could not say so: `scrollTo` found the node before the save and after it. A value is what the app tells VoiceOver about an element's state, and the runner already records it, so the check is read off the captured trees here, where `swift test` holds the whole decision.
///
/// **Some node so named reads it, matched whole.** An entry passes when any node whose `label` or `identifier` equals the entry's `label` has a `value` equal to the entry's `value` — a heading and its button may share a label, and either reading the value is enough. Like `expect` and `expectMenu` nothing is matched by a leading component or with `{n}`; the author is pinning what the node reads. A node with no value reads as none, so it never passes.
///
/// **Every capture is checked**, for the reason `ExpectedScreenCheck` checks every one: a value right under `light` and wrong under a larger text size must not pass by averaging.
public struct ExpectedValueCheck {
    /// The outcome a screen must be recorded under given the trees its captures actually produced, or `intended` when the screen states no values or every tree shows them.
    ///
    /// `found` is each mismatched capture's path of screen identifiers exactly as `ExpectedScreenCheck` computes it (`ScreenIdentifierRule.foundPath(of:)`), distinct and in order. The `reason` names each entry the first mismatched capture fails, joined by `; `.
    ///
    /// **Composition mirrors `ExpectedMenuCheck.outcome`** and is exhaustive for the same reason. An `intended` that is already an `.unexpectedScreen` keeps its expected and found and gains the value clause in its reason.
    public static func outcome(for trees: [AXNode], expectValues: [Walkbook.ExpectedValue]?, instead intended: ScreenOutcome) -> ScreenOutcome {
        guard let expectValues, !expectValues.isEmpty else { return intended }
        let misses = trees.compactMap { tree -> (tree: AXNode, failures: [String])? in
            let failures = expectValues.compactMap { failure(of: $0, in: tree) }
            return failures.isEmpty ? nil : (tree, failures)
        }
        guard let first = misses.first else { return intended }
        let clause = first.failures.joined(separator: "; ")
        let expected = "values: \(expectValues.map { "\($0.label) = \($0.value)" }.joined(separator: ", "))"
        let found = distinct(misses.map { ScreenIdentifierRule.foundPath(of: $0.tree) })
        return switch intended {
        case .captured:
            .unexpectedScreen(expected: expected, found: found, reason: clause)
        case let .captureFailed(failure):
            .unexpectedScreen(expected: expected, found: found, reason: "\(clause). The screen also failed mid-capture: \(failure)")
        case let .stateNotApplied(existing):
            .unexpectedScreen(expected: expected, found: found, reason: "\(clause). \(existing)")
        case let .unexpectedScreen(priorExpected, priorFound, existing):
            .unexpectedScreen(expected: priorExpected, found: priorFound, reason: existing.map { $0.hasSuffix(clause) ? $0 : "\($0). \(clause)" } ?? clause)
        case .unreachable, .buildMismatch:
            // Verdicts that file nothing: a tree handed in beside one is not evidence this screen holds.
            intended
        }
    }

    /// The sentence saying why `tree` does not hold `entry`, or `nil` when some node so named reads the value.
    private static func failure(of entry: Walkbook.ExpectedValue, in tree: AXNode) -> String? {
        let named = tree.flattened.filter { $0.label == entry.label || $0.identifier == entry.label }
        guard !named.isEmpty else {
            return "nothing labelled or identified '\(entry.label)' is in the capture — a lazy list holds only the rows on screen, so end the route by scrolling to it"
        }
        if named.contains(where: { $0.value == entry.value }) {
            return nil
        }
        let reads = distinct(named.map(\.value)).compactMap(\.self).map { "'\($0)'" }
        guard !reads.isEmpty else { return "'\(entry.label)' has no value, not '\(entry.value)'" }
        let joined = reads.count == 1 ? reads[0] : "\(reads.dropLast().joined(separator: ", ")) and \(reads[reads.count - 1])"
        return "'\(entry.label)' reads \(joined), not '\(entry.value)'"
    }

    /// The values in the order they were found, each kept once.
    private static func distinct(_ values: [String?]) -> [String?] {
        var seen: [String?] = []
        for value in values where !seen.contains(value) {
            seen.append(value)
        }
        return seen
    }
}
