//
// Copyright © Agulhas Labs
//

import Foundation

/// `bundle screen --tree`: the nodes a query names, each with its identifier, frame, selected flag and the chain of containers it sits in (SimWalk#121).
///
/// The text answer lists what a reader sees; this lists what a tester needs to address — the identifier to tap, the frame to aim at, whether a tab is the selected one, which bar a button is under — so nobody reads `ax-tree.json` with a script. It lists only the nodes `match` or `bars` name: an unfiltered tree is `ax-tree.json` again.
struct ScreenTreeListing {
    /// The element types `--bars` lists.
    static let barTypes: Set<String> = ["TabBar", "Toolbar", "NavigationBar"]

    /// The listing's residue — a line per matched node in tree order, on-screen ones first, then (with `listingOffScreen`) the off-screen ones marked — and the verdict's clause saying how many matched.
    ///
    /// `match` selects a node whose label, value or identifier contains it (case-insensitively) or whose type equals it (case-insensitively); `bars` selects every ``barTypes`` node; both select the union. On screen is `BundleScreenQuery`'s own test: the node's frame intersects the tree's ``AXNode/screenBounds``.
    static func listing(of tree: AXNode, match: String?, bars: Bool, listingOffScreen: Bool) -> (residue: [String], clause: String) {
        let isOnScreen = BundleScreenQuery.onScreenTest(for: tree)
        var onScreen: [Hit] = []
        var offScreen: [Hit] = []
        for hit in hits(in: tree, ancestors: []).dropFirst() where selects(hit.node, match: match, bars: bars) {
            if isOnScreen(hit.node) {
                onScreen.append(hit)
            } else {
                offScreen.append(hit)
            }
        }

        var residue = onScreen.flatMap { lines(of: $0, offScreen: false) }
        if listingOffScreen {
            residue += offScreen.flatMap { lines(of: $0, offScreen: true) }
        }

        let count = onScreen.count
        let what = switch (match, bars) {
        case let (match?, true): "\(count) node\(count == 1 ? " matches" : "s match") '\(match)' or \(count == 1 ? "is a bar" : "are bars")"
        case let (match?, false): "\(count) node\(count == 1 ? " matches" : "s match") '\(match)'"
        default: "\(count) bar\(count == 1 ? "" : "s")"
        }
        let more = if offScreen.isEmpty {
            ""
        } else if listingOffScreen {
            "; \(offScreen.count) more off screen (listed)"
        } else {
            "; \(offScreen.count) more off screen; --all lists them"
        }
        return (residue, what + more)
    }

    /// Every node in tree order with its ancestors below the root; the root itself comes first, and ``listing(of:match:bars:listingOffScreen:)`` drops it, since the app's own label is its display name, not a node on the screen.
    private static func hits(in node: AXNode, ancestors: [AXNode]) -> [Hit] {
        [Hit(node: node, ancestors: ancestors)]
            + node.children.flatMap { hits(in: $0, ancestors: ancestors.isEmpty && node.type == "Application" ? [] : ancestors + [node]) }
    }

    private static func selects(_ node: AXNode, match: String?, bars: Bool) -> Bool {
        if bars, barTypes.contains(node.type) {
            return true
        }
        guard let match else { return false }
        return node.type.caseInsensitiveCompare(match) == .orderedSame
            || [node.label, node.value, node.identifier].contains { $0?.range(of: match, options: .caseInsensitive) != nil }
    }

    private static func lines(of hit: Hit, offScreen: Bool) -> [String] {
        let node = hit.node
        var line = "\(describe(node)) \(BundleScreenQuery.frameText(node.frame))"
        if let value = node.value, !value.isEmpty {
            line += " = '\(value)'"
        }
        if node.isSelected {
            line += " selected"
        }
        if !node.isEnabled {
            line += " disabled"
        }
        if offScreen {
            line += " (off screen)"
        }
        guard let parent = hit.ancestors.last else { return [line] }

        let parentText = "\(describe(parent)) \(BundleScreenQuery.frameText(parent.frame))"
        return [line, "    in: " + (collapsed(hit.ancestors.dropLast()) + [parentText]).joined(separator: " > ")]
    }

    /// `Type['label'][ [identifier]]`, the way a node is named without its frame.
    private static func describe(_ node: AXNode) -> String {
        var text = node.type
        if let label = node.label, !label.isEmpty {
            text += " '\(label)'"
        }
        if let identifier = node.identifier, !identifier.isEmpty {
            text += " [\(identifier)]"
        }
        return text
    }

    private static func isAnonymous(_ node: AXNode) -> Bool {
        (node.label ?? "").isEmpty && (node.identifier ?? "").isEmpty
    }

    /// The ancestors as names, a run of two or more anonymous ones of one type folded to `Type×N`.
    private static func collapsed(_ ancestors: ArraySlice<AXNode>) -> [String] {
        var names: [String] = []
        var index = ancestors.startIndex
        while index < ancestors.endIndex {
            let node = ancestors[index]
            var end = index + 1
            if isAnonymous(node) {
                while end < ancestors.endIndex, isAnonymous(ancestors[end]), ancestors[end].type == node.type {
                    end += 1
                }
            }
            names.append(end - index >= 2 ? "\(node.type)×\(end - index)" : describe(node))
            index = end
        }
        return names
    }
}

extension ScreenTreeListing {
    /// One node with the containers above it, as the walk down the tree met it.
    private struct Hit {
        let node: AXNode
        /// The containers from the root's child down to the node's parent; empty when the parent is the root (or the node is the root).
        let ancestors: [AXNode]
    }
}
