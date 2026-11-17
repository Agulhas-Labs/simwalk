//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a `tap` route step landed, decided here so a test holds it (SimWalk#125, #95).
///
/// A tap after which the screen's structure changed has landed, and so has one that left the screen in place but the tapped element itself lastingly selected or enabled, or the reverse (SimWalk#251, ``SameScreenChange/tappedTraitChange(from:to:tapped:)``); a change anywhere else on the screen does not land it. One after which nothing changed has landed too when three things say the step's destination was already on screen: the element was selected, both in the snapshot the tap bound and read live just before it; it was hittable then; and the tree read just before the tap holds a navigation bar naming the step's label (``destinationTitled(label:in:tapped:)``). iPad Settings opens with the sidebar row General selected and General's detail showing under a bar titled General, where the tap changes nothing a `ScreenIdentity` hashes (#125). A selected element that is not hittable is not landed on, because a modal over the app leaves the selection true and landing on it would prove nothing about the app being in front (#95). The title is required because a selected row says nothing about what its detail shows: an earlier step may have pushed the detail deeper, and reselecting the row does not pop it (a `NavigationSplitView` keeps the detail's path), so the screen in front carries the deeper screen's title and is refused rather than filed under the row's screen id. Something selected that has no bar of its own, such as an already-active segment of a segmented control or a filter pill, is refused as before: narrower than it could be, and honest. Unlike a `tab` (``TabStepAction``), the tap is still made.
public enum TapLanding: Equatable, Sendable {
    /// The screen changed after the tap, or the tapped element stayed selected or became enabled (or the reverse).
    case landed
    /// Nothing changed, and the element tapped was selected and hittable under a navigation bar naming it: the step's destination was already on screen.
    case alreadySelected
    /// Nothing changed, and nothing says the destination was already on screen.
    case notLanded

    /// Whether a `tap` that must change nothing did (SimWalk#268), read once the step's whole budget has run.
    ///
    /// It lands when no element appeared or went (``ScreenStructureChange``, which an identifier filling in on a tab bar's buttons does not satisfy) and the tapped element's own selection and enablement did not change (``SameScreenChange/tappedTraitChange(from:to:tapped:)``, as ``decide(arrived:tappedTraitChanged:wasSelected:hittable:titled:)`` reads it); anything else, a changed element elsewhere on the screen included, is not the tap's doing and does not refuse it. A refusal for a changed screen names what changed (``ScreenStructureChange/clause``).
    /// - Parameters:
    ///   - screenChange: the first change in the screen's structure a read within the budget found; `nil` when none did.
    ///   - tappedTraitChange: on a screen the tap did not change, the tapped element's own change of selection or enablement; `nil` when it has none.
    ///   - tapped: the tapped element as a refusal names it.
    public static func decideUnchanged(screenChange: ScreenStructureChange?, tappedTraitChange: SameScreenChange.TraitChange?, tapped: String) -> UnchangedLanding {
        let prefix = "tapped \(tapped) expecting nothing to change, but "
        if let screenChange {
            return .refused(reason: prefix + "the screen changed: \(screenChange.clause)")
        }
        guard let change = tappedTraitChange else { return .landed }
        let became = [
            change.selected.map { $0 ? "selected" : "deselected" },
            change.enabled.map { $0 ? "enabled" : "disabled" },
        ].compactMap(\.self).joined(separator: " and ")
        return .refused(reason: prefix + "it became \(became)")
    }

    /// Why a `tap` that must change nothing is refused when its target is a keyboard key (SimWalk#268, ``TypedTextLanding/isKey(_:in:)``), before it is tapped.
    ///
    /// A key is tapped to type, which changes the field it types into, so a tap on one cannot be held to changing nothing.
    /// - Parameter label: the key's label as the walkbook spells it.
    public static func unchangedKeyRefusal(label: String) -> String {
        "'\(label)' is a keyboard key: a key is tapped to type, so a tap on one cannot be held to changing nothing — use a plain tap"
    }

    /// - Parameters:
    ///   - arrived: whether the hierarchy's structure left the screen the tap was made on, within the step's budget.
    ///   - tappedTraitChanged: whether, on a screen the tap did not leave, a read taken once the budget ran out has the tapped element's own selection or enablement differing from the read before the tap (``SameScreenChange/tappedTraitChange(from:to:tapped:)``). A tile that becomes selected is the tap's whole effect on a picker, and a structure-only rule refused that tap as not landed (SimWalk#251); a highlight under the finger is gone by the time this read is taken, so only a lasting change counts. The tapped element's, not any node's: a form's validation enabling Submit while a dead control's tap waits out its budget is not the tap's doing.
    ///   - wasSelected: whether the element was selected both in the snapshot the tap bound and in a live read just before the tap.
    ///   - hittable: whether the live element was hittable just before the tap.
    ///   - titled: whether the tree read just before the tap held a navigation bar naming the step's label (``destinationTitled(label:in:tapped:)``).
    public static func decide(arrived: Bool, tappedTraitChanged: Bool, wasSelected: Bool, hittable: Bool, titled: Bool) -> TapLanding {
        if arrived || tappedTraitChanged {
            return .landed
        }
        return wasSelected && hittable && titled ? .alreadySelected : .notLanded
    }

    /// Whether the navigation bar the tap's destination is drawn under names `label`: its identifier or label is `label`, or a `StaticText` inside it, and not inside a button, has exactly that label (whitespace and `{n}` aside, see ``RouteTarget/namesWhole(_:_:)``).
    ///
    /// A selected sidebar button carrying the label is not a navigation bar, nor is a `StaticText` outside one, so neither satisfies it alone; a screen pushed deeper carries its own title in the bar and fails it. Text inside a button is passed over because a back button carries the title of the screen it returns to: under a push from General to About, the bar's back button reads General, and it names the screen behind, never the one in front.
    ///
    /// **One bar is asked, not any** (SimWalk#126): in a three-column layout the middle column's bar can read the label while the detail has been pushed deeper, and any-bar would call that landed. The bars over the tapped element's own columns title the list it sits in, not where it leads, so they are passed over (a bar containing it is one of them); the destination's is the nearest of the rest, by the gap to the tapped element, the later in the tree on a tie, and the last bar in the tree when none is left.
    ///
    /// - Parameters:
    ///   - label: the step's label.
    ///   - tree: the tree read just before the tap.
    ///   - tapped: the element the tap was made on, in `tree`.
    public static func destinationTitled(label: String, in tree: AXNode, tapped: AXNode) -> Bool {
        guard let bar = destinationBar(for: tapped, in: tree) else { return false }
        return bar.identifier.map { RouteTarget.namesWhole(label, $0) } == true
            || bar.label.map { RouteTarget.namesWhole(label, $0) } == true
            || holdsTitle(label, under: bar)
    }

    private static func destinationBar(for tapped: AXNode, in tree: AXNode) -> AXNode? {
        let bars = tree.flattened.filter { $0.type == "NavigationBar" }
        let tappedSpan = tapped.frame.x ... (tapped.frame.x + tapped.frame.width)
        let beyond = bars.enumerated().filter { _, bar in
            let barSpan = bar.frame.x ... (bar.frame.x + bar.frame.width)
            return !barSpan.overlaps(tappedSpan) && !bar.flattened.contains(tapped)
        }
        let nearest = beyond.min { lhs, rhs in
            let (left, right) = (gap(from: tapped, to: lhs.element), gap(from: tapped, to: rhs.element))
            return left == right ? lhs.offset > rhs.offset : left < right
        }
        return nearest?.element ?? bars.last
    }

    /// The horizontal distance between `node`'s frame and `bar`'s; both spans are disjoint here, so it is positive.
    private static func gap(from node: AXNode, to bar: AXNode) -> Double {
        max(bar.frame.x - (node.frame.x + node.frame.width), node.frame.x - (bar.frame.x + bar.frame.width))
    }

    /// A `StaticText` naming `label` among `node`'s descendants, not descending into a button.
    private static func holdsTitle(_ label: String, under node: AXNode) -> Bool {
        node.children.contains { child in
            child.type != "Button" && ((child.type == "StaticText" && child.label.map { RouteTarget.namesWhole(label, $0) } == true) || holdsTitle(label, under: child))
        }
    }
}

public extension TapLanding {
    /// What a tap that must change nothing came to (``decideUnchanged(screenChange:tappedTraitChange:tapped:)``).
    enum UnchangedLanding: Equatable, Sendable {
        /// No element appeared or went (``ScreenStructureChange``) and the tapped element's selection and enablement did not change.
        case landed
        /// Something changed; `reason` says what, for the UNREACHABLE that reports it.
        case refused(reason: String)
    }
}
