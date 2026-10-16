//
// Copyright © Agulhas Labs
//

import Foundation

/// Where a `tab` step's button is on screen, read off the tree (SimWalk#109).
///
/// The runner used to look only in `app.tabBars`. On iPad a `TabView` in `.sidebarAdaptable` style at regular width draws a floating bar that has no `TabBar` node at all, so every tab step was UNREACHABLE and said nothing about what it had seen. The decision of where a tab is lives here, in the core, so a test holds it and the runner only binds the live element to the answer.
///
/// **The floating bar is recognised by its shape, never by a localised string** such as "Toggle sidebar": a node that is not itself a bar or a segmented control, whose direct children include at least two buttons on one row of which exactly one is selected. That is a group of tabs, because a tab bar is the one row of buttons that always has a selection. A real `TabBar` wins over it.
public struct TabTarget {}

extension TabTarget {
    /// Which kind of bar a tab was sought in.
    public enum Bar: Equatable, Sendable {
        case tabBar
        case floating
    }

    /// The answer: the button, or the labels of the tabs that were seen instead.
    public enum Location: Equatable, Sendable {
        case found(AXNode, bar: Bar)
        case missing(tabs: [String], bar: Bar?)
    }

    /// Finds the button for the tab named `label`, matched by label or, as the runner's lookup always allowed, by identifier.
    public static func locate(_ label: String, in tree: AXNode) -> Location {
        let bars = tabBars(in: tree)
        let tabBarButtons = bars.flatMap { descendantButtons(of: $0) }
        if let hit = tabBarButtons.first(where: { matches($0, label) }) {
            return .found(hit, bar: .tabBar)
        }
        if !bars.isEmpty {
            return .missing(tabs: tabBarButtons.map { $0.label ?? "" }, bar: .tabBar)
        }
        guard let group = floatingGroup(in: tree) else {
            return .missing(tabs: [], bar: nil)
        }
        if let hit = group.first(where: { matches($0, label) }) {
            return .found(hit, bar: .floating)
        }
        return .missing(tabs: group.map { $0.label ?? "" }, bar: .floating)
    }

    private static func matches(_ node: AXNode, _ label: String) -> Bool {
        node.label == label || node.identifier == label
    }

    private static func tabBars(in node: AXNode) -> [AXNode] {
        node.type == "TabBar" ? [node] : node.children.flatMap { tabBars(in: $0) }
    }

    private static func descendantButtons(of node: AXNode) -> [AXNode] {
        node.children.flatMap { $0.type == "Button" ? [$0] : descendantButtons(of: $0) }
    }

    /// The topmost group of tabs: the direct-child buttons of one row, in tree order.
    private static func floatingGroup(in tree: AXNode) -> [AXNode]? {
        var groups: [[AXNode]] = []
        collect(tree, into: &groups)
        return groups.min { ($0.first?.frame.y ?? 0) < ($1.first?.frame.y ?? 0) }
    }

    private static func collect(_ node: AXNode, into groups: inout [[AXNode]]) {
        if !RouteTarget.barTypes.contains(node.type), node.type != "SegmentedControl" {
            let buttons = node.children.filter { $0.type == "Button" && !isSidebarToggle($0) }
            for button in buttons {
                let row = buttons.filter { sameRow($0, button) }
                // Only the row's first button reports it, so a row is one group.
                if row.first == button, row.count >= 2, row.filter(\.isSelected).count == 1 {
                    groups.append(row)
                }
            }
        }
        for child in node.children {
            collect(child, into: &groups)
        }
    }

    /// The iPad's sidebar toggle, a button on the floating bar's row that switches nothing: it is no tab, so a refusal does not list it and `tab` does not tap it (SimWalk#119).
    ///
    /// Named by its label, the one thing the tree gives it; it is the single localised string this file reads, and only to leave a button out, so a build in another language lists it as before.
    private static func isSidebarToggle(_ node: AXNode) -> Bool {
        node.label == "Toggle sidebar"
    }

    private static func sameRow(_ lhs: AXNode, _ rhs: AXNode) -> Bool {
        abs(lhs.frame.y - rhs.frame.y) <= 1 && abs(lhs.frame.height - rhs.frame.height) <= 1
    }
}
