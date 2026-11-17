//
// Copyright © Agulhas Labs
//

import Foundation

/// What a tap changed on a screen it did not leave, read from the tree before the tap and one after it (SimWalk#251, #253).
///
/// **Only between two reads of one screen.** Both questions pair the trees node for node by place in the flattened tree, which holds only when the two reads have the same ``ScreenIdentity``: the same types, labels and nesting, so the n-th node of one is the n-th of the other. When the identities differ the pairing means nothing, and both answer that nothing changed; a screen that was left needs neither answer.
///
/// **Landing is not screen identity.** `ScreenIdentity` leaves `isSelected` and `isEnabled` out on purpose, so a highlight under a finger cannot pass for a push. Whether a tap *did something* is a different question, and a tile that stays selected after the tap is the tap's effect; ``TapLanding`` counts it when it is the tapped element's own (``tappedTraitChange(from:to:tapped:)``), from a read taken once the step's budget has run, by which time a highlight has gone.
public struct SameScreenChange {
    /// The nodes whose `isSelected` or `isEnabled` differ from `before` to `after`, in `after`'s tree order; none when the two are not reads of one screen.
    public static func traitChanges(from before: AXNode, to after: AXNode) -> [TraitChange] {
        guard ScreenIdentity.of(before) == ScreenIdentity.of(after) else { return [] }
        return zip(before.flattened, after.flattened).compactMap(traitChange)
    }

    /// The tapped element's own change of `isSelected` or `isEnabled` from `before` to `after`; `nil` when it has none, or the two are not reads of one screen.
    ///
    /// **Only the tapped element lands a tap.** A tap that does nothing while something else on the screen changes is still a tap that did nothing: a form's debounced validation enabling Submit during the tap's budget, after a `type` step filled a field, is the form's doing, and crediting it to the tap would pass a dead control as landed. The tile a picker's tap selects is the tapped element itself (SimWalk#251), so nothing that case needs is lost; changes elsewhere still show as `~` lines in a session's delta (``traitChanges(from:to:)``).
    ///
    /// `tapped` is found as ``scroll(from:to:tapped:)`` finds it.
    public static func tappedTraitChange(from before: AXNode, to after: AXNode, tapped: AXNode) -> TraitChange? {
        guard let place = place(of: tapped, from: before, to: after) else { return nil }
        return traitChange(before.flattened[place], after.flattened[place])
    }

    /// How the tapped element moved from `before` to `after`, when the two are reads of one screen and its frame there is not steady (``AXNode/Frame/isSteady(with:)``); `nil` otherwise, so a pulsing element is not called scrolled.
    ///
    /// `tapped` comes from the snapshot the step bound, which may be a read older than `before`, so it is found in `before` by what `ScreenIdentity` compares (type and label) and, among several, by the nearest centre, rather than by equality a pulse would defeat.
    public static func scroll(from before: AXNode, to after: AXNode, tapped: AXNode) -> Scroll? {
        guard let place = place(of: tapped, from: before, to: after) else { return nil }
        let (from, to) = (before.flattened[place].frame, after.flattened[place].frame)
        return from.isSteady(with: to) ? nil : Scroll(from: from, to: to)
    }

    /// Where `tapped` sits in `before`'s flattened tree, and so in `after`'s, when the two are reads of one screen; `nil` otherwise, or when `before` holds nothing of its type and label.
    private static func place(of tapped: AXNode, from before: AXNode, to after: AXNode) -> Int? {
        guard ScreenIdentity.of(before) == ScreenIdentity.of(after) else { return nil }
        let nodes = before.flattened
        return nodes.indices
            .filter { nodes[$0].type == tapped.type && nodes[$0].label == tapped.label }
            .min { distance(nodes[$0].frame, tapped.frame) < distance(nodes[$1].frame, tapped.frame) }
    }

    private static func traitChange(_ old: AXNode, _ new: AXNode) -> TraitChange? {
        let selected = old.isSelected == new.isSelected ? nil : new.isSelected
        let enabled = old.isEnabled == new.isEnabled ? nil : new.isEnabled
        return selected == nil && enabled == nil ? nil : TraitChange(node: new, selected: selected, enabled: enabled)
    }

    private static func distance(_ lhs: AXNode.Frame, _ rhs: AXNode.Frame) -> Double {
        hypot((lhs.x + lhs.width / 2) - (rhs.x + rhs.width / 2), (lhs.y + lhs.height / 2) - (rhs.y + rhs.height / 2))
    }
}

public extension SameScreenChange {
    /// A node whose selection or enablement differs between the two reads, as it reads after them.
    struct TraitChange: Equatable, Sendable {
        /// The node as the read after the tap has it.
        public let node: AXNode
        /// Its selection after the tap, when that changed; `nil` when it did not.
        public let selected: Bool?
        /// Its enablement after the tap, when that changed; `nil` when it did not.
        public let enabled: Bool?

        /// What changed, in the words a step's `~` delta line ends with: `selected` or `not selected`, `enabled` or `disabled`, both joined by a comma when both changed.
        public var words: String {
            [selected.map { $0 ? "selected" : "not selected" }, enabled.map { $0 ? "enabled" : "disabled" }]
                .compactMap(\.self)
                .joined(separator: ", ")
        }
    }

    /// A tapped element that moved while its screen stayed the same one: the tap scrolled the screen rather than acting (SimWalk#253).
    struct Scroll: Equatable, Sendable {
        /// The element's frame in the read before the tap.
        public let from: AXNode.Frame
        /// Its frame in the read after.
        public let to: AXNode.Frame

        /// Why the tap did not land, for the refusal a walk's UNREACHABLE and a session's `blocked:` line both carry.
        ///
        /// "The screen did not change" would be false here, and would send its reader to the walkbook's label rather than to the scroll that took the touch.
        ///
        /// - Parameter description: the tapped element as a refusal names it (``RouteTarget/Candidate/description``).
        public func reason(tapped description: String) -> String {
            "tapped \(description), but the screen only scrolled: it moved from \(BundleScreenQuery.positionText(from)) to \(BundleScreenQuery.positionText(to))"
        }
    }
}
