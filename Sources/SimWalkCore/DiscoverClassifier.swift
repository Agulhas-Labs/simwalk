//
// Copyright © Agulhas Labs
//

import Foundation

/// Sorts one screen's controls into the few `discover` taps and the rest, each with the reason it is left alone.
///
/// **Only navigation affordances are tapped**: a tab bar's buttons, a row ``DisclosureAffordanceAudit`` recognises as a disclosure row, and the back button (``DiscoverBackButton``). Never a plain button — a destructive one looks like any other — a switch, a field, or anything on an alert. Every other enabled control is named in the skipped list, so what the crawl did not do is as visible as what it did.
public struct DiscoverClassifier {
    /// The element types listed as controls: what `bundle coverage` counts as reachable, and the fields.
    static let controlTypes = ControlCoverage.reachableTypes.union(RouteTarget.textEntryTypes)

    /// The tabs of the tree's tab bar in visual order, as labels a `tab` step selects by, and the tab buttons that cannot be selected by label.
    static func tabs(in tree: AXNode) -> (labels: [String], skipped: [DiscoverSkip]) {
        var found: [AXNode] = []
        func visit(_ node: AXNode, insideTabBar: Bool) {
            if (insideTabBar && node.type == "Button") || node.type == "Tab", node.isEnabled, name(of: node) != nil {
                found.append(node)
            }
            for child in node.children {
                visit(child, insideTabBar: insideTabBar || node.type == "TabBar")
            }
        }
        visit(tree, insideTabBar: false)
        let ordered = visualOrder(found, frame: \.frame)
        let names = ordered.compactMap { $0.label?.isEmpty == false ? $0.label : nil }
        var labels: [String] = []
        var skipped: [DiscoverSkip] = []
        for node in ordered {
            guard let label = node.label, !label.isEmpty, names.count(where: { $0 == label }) == 1 else {
                skipped.append(skip(node, on: "launch", .labelNotUnique))
                continue
            }
            labels.append(label)
        }
        return (labels, skipped)
    }

    /// The disclosure rows a route can name, in visual order, and every other control on the screen with the reason it is not tapped.
    ///
    /// Tab bar items are left out of both: they are tapped from the launch screen, as roots. So is the back button, which is how the crawl returns. A scroll bar, which the tree carries as a labelled control, is neither a row nor a skip (``AXSegmenter/isScrollIndicator(_:in:)``). **So is a control a row's own tap lands on**: a cell and the button inside it carrying its label are one target (`RouteTarget.choose`), so the one that is not the row is the row, not a second control left alone.
    static func read(_ tree: AXNode, screenID: String) -> (rows: [Row], skipped: [DiscoverSkip]) {
        let back = DiscoverBackButton.of(tree)
        let viewport = visibleFrame(of: tree)
        var rows: [Row] = []
        var skipped: [(path: [Int], entry: DiscoverSkip)] = []
        var rowTargets: Set<[Int]> = []
        func visit(_ node: AXNode, in parent: AXNode, at path: [Int], insideTabBar: Bool, insideAlert: Bool) {
            if AXSegmenter.isScrollIndicator(node, in: parent) {
                return
            }
            let isTabItem = (insideTabBar && node.type == "Button") || node.type == "Tab"
            if node.isEnabled, !isTabItem, node != back, let name = name(of: node) {
                if insideAlert, controlTypes.contains(node.type) {
                    skipped.append((path, skip(node, on: screenID, .alertButton)))
                } else if !insideAlert, DisclosureAffordanceAudit.isDisclosureRow(node) {
                    let label = name.components(separatedBy: ", ")[0]
                    if let targets = tapTargets(at: path, by: label, in: tree) {
                        rows.append(Row(label: label, node: node, isOnScreen: viewport.contains(node.frame)))
                        rowTargets.formUnion(targets)
                    } else {
                        skipped.append((path, skip(node, on: screenID, .labelNotUnique)))
                    }
                } else if controlTypes.contains(node.type) {
                    skipped.append((path, skip(node, on: screenID, reason(for: node))))
                }
            }
            for (position, child) in node.children.enumerated() {
                visit(child, in: node, at: path + [position], insideTabBar: insideTabBar || node.type == "TabBar", insideAlert: insideAlert || node.type == "Alert")
            }
        }
        for (position, child) in tree.children.enumerated() {
            visit(child, in: tree, at: [position], insideTabBar: tree.type == "TabBar", insideAlert: tree.type == "Alert")
        }
        return (visualOrder(rows, frame: \.node.frame), skipped.filter { !rowTargets.contains($0.path) }.map(\.entry))
    }

    /// Whether an alert covers the screen, which ends a branch rather than being crawled.
    static func hasAlert(_ tree: AXNode) -> Bool {
        tree.flattened.contains { $0.type == "Alert" }
    }

    /// Whether a list on the screen may run on below the rows the app loaded: a scrolling container whose lowest loaded row reaches the bottom of the visible frame.
    ///
    /// **A lazy list builds no rows below the fold**, so a row there is in no tree the crawl reads until the list is dragged. The crawl drags a list on a screen whose rows it will tap (``DiscoverCrawl``); elsewhere, and where paging stops short of the end, it says the list may continue instead, which a list whose last row ends above the bottom cannot.
    static func listMayContinue(_ tree: AXNode) -> Bool {
        continuingList(tree) != nil
    }

    /// The list ``listMayContinue(_:)`` finds: the first container, in tree order, that scrolls and whose lowest loaded row reaches the bottom of the visible frame.
    static func continuingList(_ tree: AXNode) -> AXNode? {
        let bottom = visibleFrame(of: tree).maxY
        return tree.flattened.first { container in
            guard SystemSheetScope.scrollTypes.contains(container.type) else { return false }
            let lowest = rows(of: container).filter(\.frame.hasArea).map(\.frame.maxY).max()
            return lowest.map { $0 >= bottom } ?? false
        }
    }

    /// A list's rows: its cells where it has any, because a table's or collection view's other children are backgrounds that span the whole list whatever it holds (a two-row list's run 912 and 3,772 points tall); otherwise every content child but those framed exactly as the container, which are a scroll view's backgrounds.
    static func rows(of container: AXNode) -> [AXNode] {
        let children = AXSegmenter.contentChildren(of: container)
        let cells = children.filter { $0.type == "Cell" }
        return cells.isEmpty ? children.filter { $0.frame != container.frame } : cells
    }

    /// A label a route can start an app without tabs by: its first disclosure row's, else its first labelled element's, in visual order.
    static func anchor(in tree: AXNode) -> String? {
        if let row = read(tree, screenID: "").rows.first {
            return row.label
        }
        let labelled = tree.flattened.dropFirst().filter { $0.label?.isEmpty == false && !RouteTarget.chromeTypes.contains($0.type) }
        return visualOrder(labelled, frame: \.frame).first?.label?.components(separatedBy: ", ")[0]
    }

    /// `items` top to bottom, then leading to trailing, tree order breaking a tie — so one app state always gives one order.
    static func visualOrder<Item>(_ items: [Item], frame: (Item) -> AXNode.Frame) -> [Item] {
        items.enumerated().sorted { lhs, rhs in
            let left = frame(lhs.element)
            let right = frame(rhs.element)
            if left.y != right.y {
                return left.y < right.y
            }
            if left.x != right.x {
                return left.x < right.x
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Where a `tap` labelled `label` would land when it would land on the row at `path` and on nothing else — every element the runner's lookup matches in its best tier, each the row, inside it, or around it — or `nil` when it would not.
    private static func tapTargets(at path: [Int], by label: String, in tree: AXNode) -> [[Int]]? {
        guard case let .chosen(_, among) = RouteTarget.choose(labelled: label, in: tree, reaching: .control) else { return nil }
        let isOnPath = among.allSatisfy { candidate in
            candidate.path.starts(with: path) || path.starts(with: candidate.path)
        }
        return isOnPath ? among.map(\.path) : nil
    }

    /// The part of the screen a row can be tapped in without scrolling: the screen's bounds, above any bar along its bottom.
    private static func visibleFrame(of tree: AXNode) -> AXNode.Frame {
        let screen = tree.screenBounds
        let bottomBars = tree.flattened.filter { ["TabBar", "Toolbar"].contains($0.type) && $0.frame.hasArea && $0.frame.y > screen.y + screen.height / 2 }
        let bottom = bottomBars.map(\.frame.y).min() ?? screen.maxY
        return AXNode.Frame(x: screen.x, y: screen.y, width: screen.width, height: bottom - screen.y)
    }

    private static func reason(for node: AXNode) -> DiscoverSkip.Reason {
        if ["Switch", "Toggle"].contains(node.type) {
            return .isSwitch
        }
        return RouteTarget.textEntryTypes.contains(node.type) ? .textField : .notNavigation
    }

    private static func name(of node: AXNode) -> String? {
        [node.label, node.identifier].compactMap(\.self).first { !$0.isEmpty }
    }

    private static func skip(_ node: AXNode, on screenID: String, _ reason: DiscoverSkip.Reason) -> DiscoverSkip {
        DiscoverSkip(screenID: screenID, type: node.type, name: name(of: node) ?? "", reason: reason, frame: node.frame)
    }
}

extension DiscoverClassifier {
    /// A disclosure row the crawl may tap, by the label its step names it with.
    struct Row: Equatable {
        /// Its leading component — what `tap` names it by, as `bundle coverage` suggests one.
        let label: String
        let node: AXNode
        /// Whether it is drawn wholly in the visible part of the screen; a row that is not is scrolled to first.
        let isOnScreen: Bool
    }
}
