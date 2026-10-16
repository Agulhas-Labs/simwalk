//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a `tap` route step landed, decided here so a test holds it (SimWalk#125, #95).
///
/// A tap after which the screen's structure changed has landed. One after which nothing changed has landed too when three things say the step's destination was already on screen: the element was selected, both in the snapshot the tap bound and read live just before it; it was hittable then; and the tree read just before the tap holds a navigation bar naming the step's label (``destinationTitled(label:in:tapped:)``). iPad Settings opens with the sidebar row General selected and General's detail showing under a bar titled General, where the tap changes nothing a `ScreenIdentity` hashes (#125). A selected element that is not hittable is not landed on, because a modal over the app leaves the selection true and landing on it would prove nothing about the app being in front (#95). The title is required because a selected row says nothing about what its detail shows: an earlier step may have pushed the detail deeper, and reselecting the row does not pop it (a `NavigationSplitView` keeps the detail's path), so the screen in front carries the deeper screen's title and is refused rather than filed under the row's screen id. Something selected that has no bar of its own, such as an already-active segment of a segmented control or a filter pill, is refused as before: narrower than it could be, and honest. Unlike a `tab` (``TabStepAction``), the tap is still made.
public enum TapLanding: Equatable, Sendable {
    /// The screen changed after the tap.
    case landed
    /// Nothing changed, and the element tapped was selected and hittable under a navigation bar naming it: the step's destination was already on screen.
    case alreadySelected
    /// Nothing changed, and nothing says the destination was already on screen.
    case notLanded

    /// - Parameters:
    ///   - arrived: whether the hierarchy's structure left the screen the tap was made on, within the step's budget.
    ///   - wasSelected: whether the element was selected both in the snapshot the tap bound and in a live read just before the tap.
    ///   - hittable: whether the live element was hittable just before the tap.
    ///   - titled: whether the tree read just before the tap held a navigation bar naming the step's label (``destinationTitled(label:in:tapped:)``).
    public static func decide(arrived: Bool, wasSelected: Bool, hittable: Bool, titled: Bool) -> TapLanding {
        if arrived {
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
