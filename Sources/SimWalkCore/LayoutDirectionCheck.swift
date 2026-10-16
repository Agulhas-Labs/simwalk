//
// Copyright © Agulhas Labs
//

import Foundation

/// Which way a capture's accessibility tree says it was laid out, read from its horizontal runs of siblings.
///
/// **Tree order does not mirror; frames do.** Measured on an iOS 27 simulator with an HStack of three texts: under both right-to-left overrides the tree still lists them `First, Second, Third`, and their frames run from x 249 down to 120 — so a run's direction is how its frames move along its tree order. Without the overrides, or with either one alone, the same run went 120 → 243.
///
/// **What it cannot see, stated rather than passed:** a screen with no two siblings side by side on one line — a single column of text, a full-screen image — has nothing to judge by, and is `unjudged`, which the manifest records as the axis set and unverified. A run that mirrors under the app's own choice (a media control kept left to right) is why one run in the stated direction is enough to keep a capture: an unapplied override leaves every run the other way.
public struct LayoutDirectionCheck {
    /// The direction a tree's runs show: `.rtl` or `.ltr` when at least one run goes that way and none the other, the stated `direction` when runs go both ways and one of them agrees, and `nil` when no run could be judged.
    public static func judged(_ tree: AXNode, stated direction: Walkbook.LayoutDirection) -> Walkbook.LayoutDirection? {
        let directions = runs(in: tree).compactMap(direction(of:))
        guard !directions.isEmpty else { return nil }
        return directions.contains(direction) ? direction : directions[0]
    }

    /// Every run of two or more siblings sitting side by side on one line, in tree order: each node's children grouped by whether their frames share a line, keeping groups whose members do not overlap horizontally.
    public static func runs(in tree: AXNode) -> [[AXNode]] {
        tree.flattened.flatMap { node -> [[AXNode]] in
            var lines: [[AXNode]] = []
            for child in node.children where child.frame.width > 0 && child.frame.height > 0 {
                if let line = lines.firstIndex(where: { sharesLine($0[0].frame, child.frame) }) {
                    lines[line].append(child)
                } else {
                    lines.append([child])
                }
            }
            return lines.filter { $0.count > 1 && isSideBySide($0) }
        }
    }

    /// The direction a run's frames move in along its tree order, or `nil` when they do not move one way throughout.
    static func direction(of run: [AXNode]) -> Walkbook.LayoutDirection? {
        let steps = zip(run, run.dropFirst()).map { $1.frame.x - $0.frame.x }
        if steps.allSatisfy({ $0 > 0 }) {
            return .ltr
        }
        if steps.allSatisfy({ $0 < 0 }) {
            return .rtl
        }
        return nil
    }

    /// Whether two frames sit on one line: their vertical extents overlap by at least half the shorter one.
    private static func sharesLine(_ first: AXNode.Frame, _ second: AXNode.Frame) -> Bool {
        let overlap = min(first.maxY, second.maxY) - max(first.y, second.y)
        return overlap >= min(first.height, second.height) / 2
    }

    /// Whether no two members of a line overlap horizontally — a line of siblings stacked over one another is not a run.
    private static func isSideBySide(_ line: [AXNode]) -> Bool {
        let sorted = line.map(\.frame).sorted { $0.x < $1.x }
        return zip(sorted, sorted.dropFirst()).allSatisfy { $0.x + $0.width <= $1.x + 0.5 }
    }
}
