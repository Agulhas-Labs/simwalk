//
// Copyright © Agulhas Labs
//

import Foundation

/// Cuts a screen into sections from its accessibility tree alone — what any app offers, with no design system's help (Brief §7.2).
///
/// **The rule, in three parts.** (1) The bars — navigation, tab, tool — are sections of their own, marked by ``ScreenSection/Role``. (2) The content is the first element, descending from the root through unlabelled wrappers, with more than one child that carries text: the *stack* — a SwiftUI scroll view's content, a table's or a collection view's cells. (3) The stack's items are grouped in order: a new section starts at every *heading*, and between two cells separated by a gap (a grouped table's sections, which the tree draws no other boundary for).
///
/// **A heading is read from shape, because the tree carries no header trait** (`XCUIElementSnapshot` exposes none). It is an item that is text rather than a control; whose title — its own text, or its first run where it is a header row of title and detail on one line (`Power` … `121 W avg`; a row's title over its subtitle is not one) — has no number in it and at most five words; that starts at the stack's leading edge; and that nothing else in the stack sits beside. **A heading that directly follows a heading joins its section** instead of opening one, but only when it is an axis row — two runs or more, none with a number (`start` … `finish`); a one-run heading, or one with a count (`Worth a look` … `2`), opens its own section, so an empty section does not swallow the next one's key. That is what keeps a chart card's axis row (`start` … `finish`, the shape of a header row) with its card when the plot between them draws nothing the tree can see — a field round's power chart card.
///
/// **Where it is weak**, measured on a real app's and Settings' bundles (Brief §8, 2026-09-29): a card with no heading joins the section before it (the tree has no card boundary to find); a heading that carries data other than a number (a workout's type) keys by that value; a heading indented past the leading edge, or with a control beside it, is read as a row.
public struct AXSegmenter: Segmenter {
    public init() {}

    public func sections(of tree: AXNode) -> [ScreenSection] {
        let viewport = tree.frame
        let bars = Self.bars(in: tree).map { Self.barSection($0.node, role: $0.role, viewport: viewport) }
        let stack = Self.stack(from: tree)
        let content = Self.groups(in: stack).map { Self.contentSection($0, viewport: viewport) }
        let ordered = bars.filter { $0.role == .navigationBar }
            + content
            + bars.filter { $0.role == .toolbar }
            + bars.filter { $0.role == .tabBar }
        return Self.uniquelyKeyed(ordered)
    }
}

extension AXSegmenter {
    /// A run of the stack's items that forms one section, led by its heading when it has one.
    struct Group {
        var heading: AXNode?
        var items: [AXNode]
    }

    /// Element types that are bars, and the role each one's section takes.
    static let barRoles: [String: ScreenSection.Role] = [
        "NavigationBar": .navigationBar,
        "TabBar": .tabBar,
        "Toolbar": .toolbar,
    ]

    /// Element types a heading can be — text, or a plain element that combines text, never a control.
    static let headingTypes: Set<String> = ["StaticText", "Other"]

    /// The most words a heading's title has; a longer line is prose.
    static var maxHeadingWords: Int {
        5
    }

    /// How far, in points, a heading's title may start from the stack's leading edge — the inset between a row's background and its text.
    static var leadingEdgeTolerance: Double {
        16
    }

    /// The least vertical gap, in points, between two cells that ends a grouped table's section; cells inside one section touch.
    static var cellGroupGap: Double {
        8
    }

    /// The bars under `node`, outermost first, in tree order.
    static func bars(in node: AXNode) -> [(node: AXNode, role: ScreenSection.Role)] {
        if let role = barRoles[node.type] {
            return [(node, role)]
        }
        return node.children.flatMap { bars(in: $0) }
    }

    /// The content's items: the children of the first element below `root`, through unlabelled wrappers, that has more than one child carrying text — bars and scroll indicators set aside.
    static func stack(from root: AXNode) -> [AXNode] {
        var node = root
        while true {
            let items = node.children.filter(isContent)
            guard items.count == 1, let only = items.first, only.label?.isEmpty ?? true else { return items }
            node = only
        }
    }

    /// Whether `node` is part of the content: not a bar, not a scroll indicator, and carrying text somewhere below it.
    static func isContent(_ node: AXNode) -> Bool {
        guard barRoles[node.type] == nil, !isScrollIndicator(node) else { return false }
        if !(node.label ?? "").isEmpty || !(node.value ?? "").isEmpty {
            return true
        }
        return node.children.contains(where: isContent)
    }

    /// A scroll view's indicator, which the tree carries as a labelled element whose value is a percentage.
    static func isScrollIndicator(_ node: AXNode) -> Bool {
        node.type == "Other" && node.value?.hasSuffix("%") == true
    }

    /// The stack's items grouped into sections, in order.
    static func groups(in stack: [AXNode]) -> [Group] {
        let leadingEdge = stack.map(\.frame.x).filter { $0 >= 0 }.min() ?? 0
        var groups: [Group] = []
        for (index, item) in stack.enumerated() {
            let previous = index > 0 ? stack[index - 1] : nil
            if isHeading(at: index, in: stack, leadingEdge: leadingEdge) {
                if let last = groups.last, last.heading != nil, last.items.isEmpty, isAxisRow(item) {
                    groups[groups.count - 1].items.append(item)
                } else {
                    groups.append(Group(heading: item, items: []))
                }
            } else if groups.isEmpty || previous.map({ startsCellGroup(item, after: $0) }) == true {
                groups.append(Group(heading: nil, items: [item]))
            } else {
                groups[groups.count - 1].items.append(item)
            }
        }
        return groups
    }

    /// Whether the stack's item at `index` reads as a heading: text on one line whose title has no number and few words, at the leading edge, with nothing beside it.
    static func isHeading(at index: Int, in stack: [AXNode], leadingEdge: Double) -> Bool {
        let item = stack[index]
        guard headingTypes.contains(item.type), let title = titleRun(of: item), let text = title.label else { return false }
        guard !TextShape.hasNumber(text), text.split(whereSeparator: \.isWhitespace).count <= maxHeadingWords else { return false }
        guard abs(title.frame.x - leadingEdge) <= leadingEdgeTolerance else { return false }
        guard textLeaves(of: item).allSatisfy({ overlapsVertically($0.frame, title.frame) }) else { return false }
        return !stack.indices.contains { other in
            other != index && overlapsVertically(stack[other].frame, item.frame)
        }
    }

    /// Whether `item` is a chart's axis row: two runs or more on a line, none with a number in it (`start` … `finish`).
    ///
    /// A heading with one run, or with a count (`Worth a look` … `2`), is not.
    static func isAxisRow(_ item: AXNode) -> Bool {
        let leaves = textLeaves(of: item)
        return leaves.count >= 2 && !leaves.contains { TextShape.hasNumber($0.label ?? "") }
    }

    /// The run a heading is titled by: the item itself when it is one run, else its first — a header row's title, before its detail.
    static func titleRun(of item: AXNode) -> AXNode? {
        guard item.children.isEmpty else { return textLeaves(of: item).first }
        return item
    }

    /// Whether `item` is a cell opening a new group of cells, a gap below the cell before it.
    static func startsCellGroup(_ item: AXNode, after previous: AXNode) -> Bool {
        item.type == "Cell" && previous.type == "Cell" && item.frame.y - previous.frame.maxY >= cellGroupGap
    }

    /// Whether two frames share more than a point of height — two things drawn on one line.
    static func overlapsVertically(_ first: AXNode.Frame, _ second: AXNode.Frame) -> Bool {
        min(first.maxY, second.maxY) - max(first.y, second.y) > 1
    }

    /// The runs of text under `node` that nothing below them restates — a combined element's parts rather than their join, and never an image.
    static func textLeaves(of node: AXNode) -> [AXNode] {
        guard node.type != "Image" else { return [] }
        let inner = node.children.flatMap(textLeaves)
        if !inner.isEmpty {
            return inner
        }
        return (node.label ?? "").isEmpty ? [] : [node]
    }
}

extension AXSegmenter {
    /// The section a bar makes: keyed by what it is, since a bar's title is the screen's and changes with the language.
    static func barSection(_ bar: AXNode, role: ScreenSection.Role, viewport: AXNode.Frame) -> ScreenSection {
        ScreenSection(
            key: barKeys[role] ?? role.rawValue,
            role: role,
            frame: bar.frame,
            placement: placement(of: bar.frame, in: viewport),
            textRuns: textLeaves(of: bar).map(textRun)
        )
    }

    /// The section a group of content items makes, keyed by its heading or, without one, by the first identifier its items carry.
    static func contentSection(_ group: Group, viewport: AXNode.Frame) -> ScreenSection {
        let members = (group.heading.map { [$0] } ?? []) + group.items
        let frame = union(members.map(\.frame))
        let containers = members.filter(isContainer)
        return ScreenSection(
            key: key(of: group),
            role: .content,
            frame: frame,
            placement: placement(of: frame, in: viewport),
            textRuns: members.flatMap(textLeaves).map(textRun),
            containerFrame: containers.isEmpty ? nil : union(containers.map(\.frame))
        )
    }

    /// Whether `member`'s frame is set by the layout rather than by its text: it holds no text, or it reaches past its text on some edge by more than ``BoxRule/defaultTolerance`` — a row's background, a card, a callout — where a label, or an element combining labels, ends where its words do.
    ///
    /// In the real trees (two walks of one build, 2026-09-29) the ranked rows on a summary screen (a 374 pt button around 320 pt of text) and the sessions under a comparison heading are containers; a detail screen's lead paragraph, its figures and every header row are not — a longer figure widens them.
    static func isContainer(_ member: AXNode) -> Bool {
        let leaves = textLeaves(of: member)
        guard !leaves.isEmpty else { return true }
        let text = union(leaves.map(\.frame))
        let frame = member.frame
        let tolerance = BoxRule.defaultTolerance
        return abs(frame.minX - text.minX) > tolerance || abs(frame.minY - text.minY) > tolerance
            || abs(frame.maxX - text.maxX) > tolerance || abs(frame.maxY - text.maxY) > tolerance
    }

    /// Bar sections' keys, by role.
    static let barKeys: [ScreenSection.Role: String] = [
        .navigationBar: "navigation bar",
        .tabBar: "tab bar",
        .toolbar: "toolbar",
    ]

    /// What an untitled section with no identifier is keyed by.
    static var untitledKey: String {
        "untitled"
    }

    /// A group's key: its heading's identifier, else its heading's title by shape, else the first identifier on an element of its items, else ``untitledKey``.
    static func key(of group: Group) -> String {
        if let heading = group.heading {
            if let identifier = heading.identifier, !identifier.isEmpty {
                return identifier
            }
            return TextShape.of(titleRun(of: heading)?.label ?? "")
        }
        let identifiers = group.items.flatMap(\.flattened).filter { $0.type != "Image" }.compactMap(\.identifier)
        return identifiers.first { !$0.isEmpty } ?? untitledKey
    }

    /// `sections` with a repeated key suffixed by its occurrence: ` #2`, ` #3`.
    static func uniquelyKeyed(_ sections: [ScreenSection]) -> [ScreenSection] {
        var seen: [String: Int] = [:]
        return sections.map { section in
            let count = (seen[section.key] ?? 0) + 1
            seen[section.key] = count
            var keyed = section
            if count > 1 {
                keyed.key = "\(section.key) #\(count)"
            }
            return keyed
        }
    }

    /// A text leaf as a run: its shape and its frame.
    static func textRun(_ node: AXNode) -> ScreenSection.TextRun {
        ScreenSection.TextRun(shape: TextShape.of(node.label ?? ""), frame: node.frame)
    }

    /// Where `frame` sits against `viewport`.
    static func placement(of frame: AXNode.Frame, in viewport: AXNode.Frame) -> ScreenSection.Placement {
        let overlapWidth = min(frame.x + frame.width, viewport.x + viewport.width) - max(frame.x, viewport.x)
        let overlapHeight = min(frame.maxY, viewport.maxY) - max(frame.y, viewport.y)
        guard overlapWidth > 0, overlapHeight > 0 else { return .offScreen }
        let inside = frame.y >= viewport.y && frame.maxY <= viewport.maxY
            && frame.x >= viewport.x && frame.x + frame.width <= viewport.x + viewport.width
        return inside ? .onScreen : .partlyOffScreen
    }

    /// The smallest frame holding every one of `frames`.
    static func union(_ frames: [AXNode.Frame]) -> AXNode.Frame {
        guard let first = frames.first else { return AXNode.Frame(x: 0, y: 0, width: 0, height: 0) }
        let minX = frames.map(\.x).min() ?? first.x
        let minY = frames.map(\.y).min() ?? first.y
        let maxX = frames.map { $0.x + $0.width }.max() ?? first.x
        let maxY = frames.map(\.maxY).max() ?? first.maxY
        return AXNode.Frame(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
