//
// Copyright © Agulhas Labs
//

import Foundation

/// What changed in a screen's structure between two reads, as a `tap` that must change nothing asks it (SimWalk#268): the elements that appeared and went, by type, label and nesting.
///
/// **Identifiers are left out, as ``ScreenIdentity`` leaves them out** (SimWalk#279). A tab bar's buttons are read for a moment after a tab switch with no identifier and then carry their symbol's name (`house`, `list.bullet`): the same buttons, at the same place, under the same labels. While `ScreenIdentity` hashed identifiers, a tap made in that moment read as having left the screen, and a `tap … unchanged` on a row that changes nothing was refused in half its walks. An identifier filling in or changing on an element whose type, label and place stay is that element described more fully, never a navigation, sheet, alert or menu: each of those brings elements of its own or takes some away. Frames, traits and values are left out as `ScreenIdentity` leaves them, for its reasons.
///
/// **What it adds to `ScreenIdentity` is the difference itself.** The identity answers whether the screen changed by this same view of it; this names what appeared and went, for the refusal of a tap that must change nothing.
public struct ScreenStructureChange: Equatable, Sendable {
    /// The elements in the later read that the earlier one did not have, in the later read's order.
    public let appeared: [AXNode]
    /// The elements in the earlier read that the later one does not have, in the earlier read's order.
    public let went: [AXNode]

    /// The change from `before` to `after`, or `nil` when the two have the same elements by type and label, nested alike.
    ///
    /// Each element is matched once, in order: one that moved to another parent went from its old place and appeared at its new one.
    public static func between(_ before: AXNode, _ after: AXNode) -> ScreenStructureChange? {
        let old = outline(of: before)
        let new = outline(of: after)
        guard old.map(\.line) != new.map(\.line) else { return nil }
        let difference = new.map(\.line).difference(from: old.map(\.line))
        return ScreenStructureChange(
            appeared: offsets(of: difference.insertions).map { new[$0].node },
            went: offsets(of: difference.removals).map { old[$0].node }
        )
    }

    /// The change in one short clause, for the refusal that reports it: `'Open details' appeared`, `'Press row' and 3 more went`.
    ///
    /// It names one element, chosen to be the news: a labelled one whose label is not also on the other side (an element that only moved to another parent went and appeared under one label), an element that appeared before one that went, and one with a label before one without. The count is of the named element's side.
    public var clause: String {
        let appearedLabels = Set(appeared.compactMap(\.spokenLabel))
        let wentLabels = Set(went.compactMap(\.spokenLabel))
        let candidates: [(node: AXNode, cameIn: Bool)?] = [
            appeared.first { $0.spokenLabel.map { !wentLabels.contains($0) } == true }.map { ($0, true) },
            went.first { $0.spokenLabel.map { !appearedLabels.contains($0) } == true }.map { ($0, false) },
            appeared.first { $0.spokenLabel != nil }.map { ($0, true) },
            went.first { $0.spokenLabel != nil }.map { ($0, false) },
            appeared.first.map { ($0, true) },
            went.first.map { ($0, false) },
        ]
        // `between` makes no change without an element on one side or the other, so the guard never answers.
        guard let (node, cameIn) = candidates.lazy.compactMap(\.self).first else { return "nothing changed" }
        let name = node.spokenLabel.map { "'\($0)'" } ?? "an unlabelled \(node.type)"
        let (count, verb) = cameIn ? (appeared.count, "appeared") : (went.count, "went")
        return count > 1 ? "\(name) and \(count - 1) more \(verb)" : "\(name) \(verb)"
    }

    /// The changes' offsets in ascending order: a difference lists its removals last-first.
    private static func offsets(of changes: [CollectionDifference<String>.Change]) -> [Int] {
        changes.map { change in
            switch change {
            case let .insert(offset, _, _), let .remove(offset, _, _): offset
            }
        }.sorted()
    }

    /// Each node of `tree` in pre-order with its line: its depth, type and label, which together give the nesting back.
    private static func outline(of tree: AXNode) -> [(line: String, node: AXNode)] {
        func walk(_ node: AXNode, depth: Int) -> [(line: String, node: AXNode)] {
            [("\(depth)|\(node.type)|\(node.label ?? "")", node)] + node.children.flatMap { walk($0, depth: depth + 1) }
        }
        return walk(tree, depth: 0)
    }
}

private extension AXNode {
    /// The label as a refusal names the element by, `nil` when it has none worth naming.
    var spokenLabel: String? {
        label.flatMap { $0.isEmpty ? nil : $0 }
    }
}
