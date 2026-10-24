//
// Copyright © Agulhas Labs
//

import Foundation

/// The pages read of one scrolling list, joined into one reading in the first page's coordinates.
///
/// A lazy list builds only the rows near the screen, so `discover` drags it and reads again. Two pages join on the rows both show once, whose `y` on each gives how far the content moved; every later frame is moved by the sum of those shifts, so the rows and skips come out in content order. Pure: the pages are trees the caller read, and nothing here drags.
struct DiscoverListPages {
    /// What the labels of one row's subtree are joined with.
    private static var separator: String {
        "\u{1F}"
    }

    private let container: AXNode
    private let screenID: String
    /// Each kept page with how far its content sits below the first page's: the first page at 0.
    private var pages: [(tree: AXNode, offset: Double)]

    init(first: AXNode, container: AXNode, screenID: String) {
        self.container = container
        self.screenID = screenID
        pages = [(first, 0)]
    }

    /// Joins the page read after one drag down; the page is kept only when it moved.
    mutating func add(_ page: AXNode) -> Join {
        guard Self.list(in: page, like: container) != nil else { return .containerGone }
        guard let last = pages.last else { return .unjoined }
        guard let shift = Self.shift(from: last.tree, to: page, container: container) else {
            return Self.stayedPut(from: last.tree, to: page, container: container) ? .changedInPlace : .unjoined
        }
        guard abs(shift) >= 1 else { return .end }
        pages.append((page, last.offset + shift))
        return .moved
    }

    /// The merged reading: rows in content order and the skips, frames in the first page's coordinates.
    ///
    /// **A later page adds only what lies inside the list**: a navigation bar's buttons, a toolbar or a row above the list did not scroll, so they are read from the first page alone. Membership is by the container's subtree, not its frame, which on iOS usually spans the navigation bar too.
    ///
    /// **A row is the same row** as one already taken when its label matches and it sits within half the taken row's height of it. A label met at another position is not unique: `scrollTo` would stop at whichever it met first, so every row with it is left untapped and skipped at its own position. So is a label the classifier skipped as not unique on any one page: whichever page read it once, no row carrying it is tapped.
    func read() -> (rows: [DiscoverClassifier.Row], skipped: [DiscoverSkip]) {
        let first = DiscoverClassifier.read(pages[0].tree, screenID: screenID)
        var rows = first.rows
        var skipped = first.skipped
        var ambiguous = Self.notUnique(first.skipped)
        for (page, offset) in pages.dropFirst() {
            guard let list = Self.list(in: page, like: container) else { continue }
            let inside = list.flattened
            let read = DiscoverClassifier.read(page, screenID: screenID)
            for row in read.rows where inside.contains(row.node) {
                let moved = DiscoverClassifier.Row(label: row.label, node: Self.moved(row.node, by: offset), isOnScreen: false)
                if rows.contains(where: { $0.label == moved.label && Self.isSamePlace($0.node.frame, moved.node.frame) }) {
                    continue
                }
                if rows.contains(where: { $0.label == moved.label }) {
                    ambiguous.insert(moved.label)
                }
                rows.append(moved)
            }
            let entries = read.skipped.filter { entry in inside.contains { Self.isSkipped($0, as: entry) } }
            ambiguous.formUnion(Self.notUnique(entries))
            for entry in entries {
                let moved = DiscoverSkip(screenID: entry.screenID, type: entry.type, name: entry.name, reason: entry.reason, frame: Self.moved(entry.frame, by: offset))
                Self.append(moved, to: &skipped)
            }
        }
        for row in rows where ambiguous.contains(row.label) {
            Self.append(DiscoverSkip(screenID: screenID, type: row.node.type, name: row.node.label ?? row.node.identifier ?? "", reason: .labelNotUnique, frame: row.node.frame), to: &skipped)
        }
        return (rows.filter { !ambiguous.contains($0.label) }, skipped)
    }

    /// How far the content moved between two pages of the list in `container`: 0 when the drag moved nothing, nil when the pages cannot be joined.
    ///
    /// Each shared anchor's shift is its `y` before less its `y` after. **An anchor that moved under a point says nothing about the content** (a pinned section header, a scroll bar), so it is left out; of the rest, the shift most of them agree on to the nearest point wins, a tie going to the group whose first anchor comes first in the new page's visual order, and is that anchor's exact shift.
    ///
    /// **When the shared anchors all stayed put the drag moved nothing only if every row of the list did**: the same number of rows, each within a point of its frame before, paired in visual order. Otherwise the pages cannot be joined, which is nil as it is when they share no anchor. Which of two things that was is `stayedPut`'s to say (SimWalk#208): the list changed in place when its rows and anchors are where they were, and content scrolled under a pinned row when some are not.
    static func shift(from previous: AXNode, to next: AXNode, container: AXNode) -> Double? {
        guard let before = list(in: previous, like: container), let after = list(in: next, like: container) else { return nil }
        let earlier = anchors(of: before)
        let later = anchors(of: after)
        let ordered = DiscoverClassifier.visualOrder(DiscoverClassifier.rows(of: after), frame: \.frame)
        let shifts = ordered.compactMap { row -> Double? in
            let text = text(of: row)
            guard let there = later[text], let here = earlier[text] else { return nil }
            return here.frame.y - there.frame.y
        }
        guard !shifts.isEmpty else { return nil }
        let moved = shifts.filter { !Self.isWithinAPoint($0, of: 0) }
        let counts = moved.reduce(into: [Double: Int]()) { $0[$1.rounded(), default: 0] += 1 }
        let most = counts.values.max()
        // The first moved anchor whose group is largest is the first anchor of the group that wins a tie.
        if let shift = moved.first(where: { counts[$0.rounded()] == most }) {
            return shift
        }
        let rowsBefore = DiscoverClassifier.visualOrder(DiscoverClassifier.rows(of: before), frame: \.frame)
        let rowsAfter = ordered
        let unchanged = rowsBefore.count == rowsAfter.count && zip(rowsBefore, rowsAfter).allSatisfy { Self.isWithinAPoint($0.frame, of: $1.frame) }
        return unchanged ? 0 : nil
    }

    /// Whether the list **stayed put** between two pages: every row of the earlier page is on the later one at the same place by its top edge, **and** every anchor of the earlier page is on the later one within a point in `y` of where it was (SimWalk#208).
    ///
    /// Rows are paired in visual order and match within a point (strictly under one) in `x` and `y`; a row may have changed height, and more rows may follow them. Only then did a drag move nothing while the list changed in place (its last row grew or wrapped, or a row was appended below).
    ///
    /// **Anchors alone are not enough**: under a pinned header ("Today") over rows with no label of their own, or one that repeats, the header is the only anchor and stays put while the content scrolls beneath it, so the rows are compared too.
    ///
    /// Known limits: a row with rows below it that grows moves the anchors below it, which reads as a move by the growth; a live row whose text changes as it grows loses its anchor, which reads as not joined.
    static func stayedPut(from previous: AXNode, to next: AXNode, container: AXNode) -> Bool {
        guard let before = list(in: previous, like: container), let after = list(in: next, like: container) else { return false }
        let rowsBefore = DiscoverClassifier.visualOrder(DiscoverClassifier.rows(of: before), frame: \.frame)
        let rowsAfter = DiscoverClassifier.visualOrder(DiscoverClassifier.rows(of: after), frame: \.frame)
        guard !rowsBefore.isEmpty, rowsAfter.count >= rowsBefore.count,
              zip(rowsBefore, rowsAfter).allSatisfy({ Self.isWithinAPoint($0.frame.x, of: $1.frame.x) && Self.isWithinAPoint($0.frame.y, of: $1.frame.y) })
        else { return false }
        let earlier = anchors(of: before)
        let later = anchors(of: after)
        guard !earlier.isEmpty else { return false }
        return earlier.allSatisfy { text, here in
            guard let there = later[text] else { return false }
            return Self.isWithinAPoint(here.frame.y, of: there.frame.y)
        }
    }

    private static func isWithinAPoint(_ a: AXNode.Frame, of b: AXNode.Frame) -> Bool {
        isWithinAPoint(a.x, of: b.x) && isWithinAPoint(a.y, of: b.y) && isWithinAPoint(a.width, of: b.width) && isWithinAPoint(a.height, of: b.height)
    }

    /// "Within a point" is one thing everywhere in this file: strictly under a point apart, so a distance of exactly one point is a move (SimWalk#210).
    private static func isWithinAPoint(_ a: Double, of b: Double) -> Bool {
        abs(a - b) < 1
    }

    /// The node on `page` framed and typed as `container` was on the first page.
    static func list(in page: AXNode, like container: AXNode) -> AXNode? {
        page.flattened.first { $0.type == container.type && $0.frame == container.frame }
    }

    /// The rows of `list` whose text no other row of it shares, by that text.
    private static func anchors(of list: AXNode) -> [String: AXNode] {
        let rows = DiscoverClassifier.rows(of: list)
        let counts = rows.reduce(into: [String: Int]()) { $0[text(of: $1), default: 0] += 1 }
        var found: [String: AXNode] = [:]
        for row in rows where counts[text(of: row)] == 1 && !text(of: row).isEmpty {
            found[text(of: row)] = row
        }
        return found
    }

    /// The labels in a row's subtree, in tree order.
    private static func text(of row: AXNode) -> String {
        row.flattened.compactMap(\.label).filter { !$0.isEmpty }.joined(separator: separator)
    }

    /// The labels the classifier skipped as not unique among `skipped`, as a row's label reads: the name's leading component.
    private static func notUnique(_ skipped: [DiscoverSkip]) -> Set<String> {
        Set(skipped.filter { $0.reason == .labelNotUnique }.map { $0.name.components(separatedBy: ", ")[0] })
    }

    /// Whether `entry` is the classifier's skip of `node`: the same type and frame, and named as the classifier names it, by its first non-empty label or identifier.
    private static func isSkipped(_ node: AXNode, as entry: DiscoverSkip) -> Bool {
        let name = [node.label, node.identifier].compactMap(\.self).first { !$0.isEmpty } ?? ""
        return node.type == entry.type && node.frame == entry.frame && name == entry.name
    }

    private static func isSamePlace(_ taken: AXNode.Frame, _ other: AXNode.Frame) -> Bool {
        abs(taken.y - other.y) <= taken.height / 2
    }

    private static func moved(_ frame: AXNode.Frame, by offset: Double) -> AXNode.Frame {
        var frame = frame
        frame.y += offset
        return frame
    }

    /// `node` with its own frame moved; its subtree stays where the page drew it, since only the row's frame is read afterwards.
    private static func moved(_ node: AXNode, by offset: Double) -> AXNode {
        var node = node
        node.frame = moved(node.frame, by: offset)
        return node
    }

    /// Adds `skip` unless one of the same type, name and reason is already at that place.
    private static func append(_ skip: DiscoverSkip, to skipped: inout [DiscoverSkip]) {
        let seen = skipped.contains { $0.type == skip.type && $0.name == skip.name && $0.reason == skip.reason && isSamePlace($0.frame, skip.frame) }
        if !seen {
            skipped.append(skip)
        }
    }
}

extension DiscoverListPages {
    /// What adding a page came to.
    enum Join: Equatable {
        /// The page joined the one before and moved: it is kept.
        case moved
        /// The drag moved nothing, so the list ended: the page is not kept.
        case end
        /// The pages cannot be joined: no row of the container is an anchor on both pages, or they share only fixed anchors and some earlier row or anchor moved away.
        case unjoined
        /// The drag moved nothing but the list changed in place (SimWalk#208), as its last row grew or wrapped, or a row was appended below: the page is not kept.
        case changedInPlace
        /// The page has no container framed as the list was.
        case containerGone
    }
}
