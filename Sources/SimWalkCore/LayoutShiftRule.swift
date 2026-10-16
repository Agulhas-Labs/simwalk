//
// Copyright © Agulhas Labs
//

import Foundation

/// Which elements of a screen were displaced while a capture's watch looked at it, decided from the watch's reads alone (SimWalk#67, M2).
///
/// **A pure function over the reads, in the core, for the reason `SettleTracker` is**: the runner only reads the tree, and a rule written there is a rule `swift test` never runs. Fixture sequences of trees replay it here.
///
/// **Two consecutive reads decide it, and a move is a shift only when the tree shows what displaced it.** An element that kept its identity and whose box moved by at least `threshold` is reported when, in the same pair of reads, another element was inserted, removed or resized on its line of motion: grown or inserted *behind* it, on the side it moved away from — a banner above a list pushing the rows down — or shrunk or removed *in front of* it, on the side it moved towards. The displacing element must clear the moved one along that line (it ends where the moved box starts, within `threshold`) and share its column, for a vertical move, or its row, for a horizontal one; the nearest such element is named as the likely cause. That condition, with the scroll rule below, is what keeps out motion that is not a shift:
/// - **A push's slide is the step, not a shift.** The watch opens only once the route's last step has arrived, and a screen sliding in as one has nothing beside it that grew or arrived to push it.
/// - **A scroll is not a shift, whoever scrolled, but for the residuals named here.** Inside a scroll container (`SystemSheetScope.scrollTypes`), when every matched element whose nearest scroll container it is, and that moved at all, moved by one offset (within `threshold`), measured against the container's own move, the content scrolled — a section header pinned in place while the rows scroll under it does not count against it — and none of it is reported, though a lazy list built rows at one edge and dropped them at the other, which looks like insertions and removals displacing their neighbours. That covers the app's own scrolls (a chat jumping to its latest message, scroll-to-today, a carousel advancing) as well as the walk's. **The exception is a change inside the container whose extent is that offset**: an inserted or removed box with the gap to the nearest matched element beyond it in its column or row, in the read it is in, or a resize's growth, equal to the distance the content moved, within `threshold`; **or a replacement**: an insertion and a removal starting at one place in one column or row whose extents differ by that distance (a loading text become a taller header). Then the content was displaced, not scrolled (a banner arriving at the top of a list, under a title that stayed put or with nothing above it), and is reported like any other shift. **The residuals**: a displacement inside a scroll container that no single change or replacement has the extent of reads as a scroll and is missed; a pinned header handed over by the next section's header moves by its own offset, so that scroll is uneven and can read as a shift; and an app scrolling a lazy list of rows of one pitch by exactly a whole number of rows, building or dropping exactly those rows, matches their extent and is reported as their insertion or removal. That one exact displacement cannot be told from a banner or a deletion at the top of the list.
/// - **After a `scrollTo` or a `systemTap`'s drag the exclusion is wider** (`afterScroll`): the scroll the step asked for may still be decelerating, so an element inside a scroll container that moved by the offset most of that container's contents moved by is the scroll's, whatever changed beside it.
/// - **A `systemTap`'s sheet is excluded, as the system's motion and not the app's** (the plan's default). A sheet arrives *over* the screen: its box overlaps what it covers, so it never clears an element along a line of motion and is never a cause, and its own rise has nothing behind it that grew. Nothing names sheets; the geometry excludes them.
///
/// **What it cannot see**: a displacement whose cause the tree does not hold — an unlabelled image decoding into a taller frame — is not reported, the same blind spot `axTreeSettled` documents. And a move that comes and goes between two reads is never seen at all. Anonymous siblings that begin with the same name and hold the same names throughout are left out, and so is such a row whose own text changed, since which became which is not known; a row whose *first* name changed (an icon circle become a checkmark.circle) is read as a removal and an insertion. An insertion read at its final box while what it pushes is still part way along (30 of 72 pt) has no change of that extent, so inside a scroll container the move reads as a scroll and is never reported; not seen in practice: in two live walks of the banner fixture the rows were always read at their final position after the push, never mid-slide, which suggests accessibility frames are the model layer's, so the insertion and the move land in one read.
///
/// **Known limit, kept: keyboard avoidance is reported.** A keyboard rising shrinks the scroll container above it (a `ScrollView` going from 780 to 444 pt), and a control pinned below the content, a `Continue` button, moves up with cause "resized ScrollView". It fires on a screen that focuses a field on its own and on a route ending in a tap on a text field. It is not excluded in M2: the cause is named, so a reader recognises it, and M3's diff compares a shift's presence across bundles, so a keyboard shift that happens on every walk does not flag.
///
/// **Matching an element across two reads.** An insertion changes the tree paths of everything after it, so a path cannot be the key. The two trees are paired top-down: the roots, always one element, then the children of each pair, so an element is only ever matched under its parent's match. Among one pair's children an element is keyed by its type, identifier and label; one with neither a label nor an identifier — an anonymous cell or container — by its type and the first label or identifier it holds, so each row's anonymous cell carries its row's name and the `More` button inside it is that row's, never the n-th `More` on the screen. **A key that does not pair one-to-one is not guessed at**: where two siblings share a key in either read, that group and everything under it is left out, neither moved nor a cause, since which is which is not known. An anonymous sibling whose first name changed, because something was inserted or removed at its top, is still paired with the one sibling of its type that holds its old first name, or whose first name it holds, so a banner arriving at the top of a list leaves the list's container, and the rows in it, matched. Anonymous siblings that share a first name (rows that all begin with one icon) are told apart by every name each holds, in tree order; any left over in both reads are left out, never paired with each other. And an anonymous sibling that is the only one of its type in both reads, the window under the application above all, is paired with its counterpart whatever it holds, so replacing the screen's first label does not leave the whole screen unpaired. An element whose label changed is a removal and an insertion, never a move.
///
/// **What is reported.** Each shift names the element by type, identifier, label and its tree path in the later read (a cause's path is in the read it is in: the earlier one for a removal), with its box in each read and the later read's time. Only an element with a label or an identifier is reported, since an anonymous box names nothing a reader can find; and one that moved by the same offset as an ancestor reported in the same pair is that ancestor's shift, not another. An element that only appears or only disappears is never a shift itself: it is the cause.
public struct LayoutShiftRule {
    /// The smallest move, or change in size, that counts, in points: under it is the sub-point jitter remote content shows between reads.
    ///
    /// Whether it should scale with Dynamic Type is left open in the Brief, to be calibrated on a live walk.
    public static let threshold: Double = 1

    /// Every shift between consecutive `reads`, in read order and then tree order.
    ///
    /// - Parameter afterScroll: Whether the route's last step asked for a scroll (`MotionWatch.afterScroll`), whose motion inside a scroll container is excluded.
    public static func shifts(in reads: [Read], afterScroll: Bool) -> [CaptureManifest.Motion.Shift] {
        var fold = Fold(afterScroll: afterScroll)
        for read in reads {
            fold.add(read)
        }
        return fold.shifts
    }
}

public extension LayoutShiftRule {
    /// One read of the watch: the app's tree, and how far into the watch it was read.
    struct Read: Equatable, Sendable {
        public let elapsed: TimeInterval
        public let tree: AXNode

        public init(elapsed: TimeInterval, tree: AXNode) {
            self.elapsed = elapsed
            self.tree = tree
        }
    }

    /// The shifts between reads as they arrive, holding only the previous read: a watch is tens of trees, and only ever two are compared (SimWalk#96).
    struct Fold: Sendable {
        /// Every shift between the reads added so far, in read order and then tree order.
        public private(set) var shifts: [CaptureManifest.Motion.Shift] = []
        /// How long passed between each read added and the one before it, in read order.
        public private(set) var gaps: [TimeInterval] = []
        private var previous: Read?
        private let afterScroll: Bool

        /// How many earlier reads are kept for the next to be compared with: none before the first, then one.
        var retainedReads: Int {
            previous == nil ? 0 : 1
        }

        public init(afterScroll: Bool) {
            self.afterScroll = afterScroll
        }

        public mutating func add(_ read: Read) {
            if let before = previous {
                gaps.append(read.elapsed - before.elapsed)
                if before.tree != read.tree {
                    shifts += Pair(before: before.tree, after: read.tree).shifts(at: read.elapsed, afterScroll: afterScroll)
                }
            }
            previous = read
        }
    }
}

private extension LayoutShiftRule {
    /// An element's own key: what it is and what it says, without where it sits.
    struct Key: Hashable {
        let type: String
        let identifier: String?
        let label: String?
        /// For an element with neither a label nor an identifier, the first one it holds.
        let holding: String?
    }

    /// One element of one read, flattened, with what matching and reporting need.
    struct Placed {
        let node: AXNode
        let path: [Int]
        /// The positions of its ancestors in the same flattened read, the root first.
        let ancestors: [Int]
        /// The positions of its children in the same flattened read, in tree order.
        var children: [Int]
        let key: Key

        var isNamed: Bool {
            node.label != nil || node.identifier != nil
        }

        /// The element as a cause or shift names it: its own type, path and name.
        ///
        /// An anonymous one also records its nearest named ancestor's name in `within` (found in `placed`, its read's flattened elements, the Application root not counting as one) and keeps its own name empty, so a cause reads "inserted Cell in 'Groceries'" and not as a cell labelled Groceries.
        func element(in placed: [Placed]) -> CaptureManifest.Motion.Element {
            let holder = isNamed ? nil : ancestors.reversed().map { placed[$0] }.first { $0.isNamed && $0.node.type != "Application" }
            return CaptureManifest.Motion.Element(type: node.type, identifier: node.identifier, label: node.label, path: path, within: holder.flatMap { $0.node.label ?? $0.node.identifier })
        }
    }

    /// Every element of `tree` in tree order, the root first.
    static func flatten(_ tree: AXNode) -> [Placed] {
        var placed: [Placed] = []
        func visit(_ node: AXNode, path: [Int], ancestors: [Int]) {
            let named = node.label != nil || node.identifier != nil
            let key = Key(type: node.type, identifier: node.identifier, label: node.label, holding: named ? nil : firstName(in: node))
            let index = placed.count
            placed.append(Placed(node: node, path: path, ancestors: ancestors, children: [], key: key))
            for (offset, child) in node.children.enumerated() {
                placed[index].children.append(placed.count)
                visit(child, path: path + [offset], ancestors: ancestors + [index])
            }
        }
        visit(tree, path: [], ancestors: [])
        return placed
    }

    /// The first label or identifier under `node`, in tree order.
    static func firstName(in node: AXNode) -> String? {
        for child in node.children {
            if let name = child.label ?? child.identifier ?? firstName(in: child) {
                return name
            }
        }
        return nil
    }

    /// Every label and identifier under `node`, in tree order.
    static func names(in node: AXNode) -> [String] {
        node.flattened.dropFirst().flatMap { [$0.label, $0.identifier].compactMap(\.self) }
    }

    /// Which elements of two reads are one element, paired top-down: an element is paired only under its parent's pair, so a key need not carry its ancestors.
    struct Pairing {
        /// For each element of the later read, its pair in the earlier.
        private(set) var matched: [Int: Int] = [:]
        /// The elements of the earlier read in a sibling group that did not pair one-to-one, with everything under them: neither moved nor changed, since which is which is not known.
        private(set) var unsureOld: Set<Int> = []
        /// The same, in the later read.
        private(set) var unsureNew: Set<Int> = []

        /// The roots are one element, whatever they hold; their children are paired under them.
        init(old: [Placed], new: [Placed]) {
            matched[0] = 0
            pair(old, new, olds: old[0].children, news: new[0].children)
        }

        /// Pairs siblings `olds` of the earlier read with siblings `news` of the later by key, then their children under each pair.
        private mutating func pair(_ old: [Placed], _ new: [Placed], olds: [Int], news: [Int]) {
            let oldGroups = Dictionary(grouping: olds) { old[$0].key }
            let newGroups = Dictionary(grouping: news) { new[$0].key }
            var pairs: [(Int, Int)] = []
            var spareOld: [Int] = []
            var spareNew: [Int] = []
            for key in Set(oldGroups.keys).union(newGroups.keys) {
                let was = oldGroups[key] ?? []
                let now = newGroups[key] ?? []
                if was.count == 1, now.count == 1 {
                    pairs.append((was[0], now[0]))
                } else if was.isEmpty || now.isEmpty {
                    spareOld += was
                    spareNew += now
                } else if key.label == nil, key.identifier == nil {
                    pairs += distinguished(old, new, was: was, now: now)
                } else {
                    markUnsure(old, new, was: was, now: now)
                }
            }
            pairs += Self.renamed(old, new, olds: spareOld.filter { !old[$0].isNamed }, news: spareNew.filter { !new[$0].isNamed })
            let pairedOld = Set(pairs.map(\.0))
            let pairedNew = Set(pairs.map(\.1))
            pairs += Self.lone(old, new, olds: olds, news: news).filter { !pairedOld.contains($0.0) && !pairedNew.contains($0.1) }
            let takenOld = Set(pairs.map(\.0))
            let takenNew = Set(pairs.map(\.1))
            let leftOld = olds.filter { !old[$0].isNamed && !takenOld.contains($0) && !unsureOld.contains($0) }
            let leftNew = news.filter { !new[$0].isNamed && !takenNew.contains($0) && !unsureNew.contains($0) }
            pairs += Self.positional(old, new, olds: leftOld, news: leftNew)
            for (earlier, later) in pairs {
                matched[later] = earlier
                pair(old, new, olds: old[earlier].children, news: new[later].children)
            }
        }

        /// Anonymous siblings left unpaired because their first name changed — content inserted or removed at their top — paired where they are of one type and one still holds the other's first name, and only one-to-one.
        private static func renamed(_ old: [Placed], _ new: [Placed], olds: [Int], news: [Int]) -> [(Int, Int)] {
            func related(_ earlier: Int, _ later: Int) -> Bool {
                guard old[earlier].node.type == new[later].node.type else { return false }
                let kept = old[earlier].key.holding.map { names(in: new[later].node).contains($0) } ?? false
                let still = new[later].key.holding.map { names(in: old[earlier].node).contains($0) } ?? false
                return kept || still
            }
            return olds.compactMap { earlier in
                let candidates = news.filter { related(earlier, $0) }
                guard candidates.count == 1, let later = candidates.first, olds.count(where: { related($0, later) }) == 1 else { return nil }
                return (earlier, later)
            }
        }

        /// Anonymous siblings still unpaired — a row whose first name changed (an icon become a checkmark) shares no name with its earlier self — paired where they are of one type at one position among their siblings, so the row resizes rather than one row being removed and another inserted.
        private static func positional(_ old: [Placed], _ new: [Placed], olds: [Int], news: [Int]) -> [(Int, Int)] {
            olds.compactMap { earlier in
                guard let later = news.first(where: { new[$0].node.type == old[earlier].node.type && new[$0].path.last == old[earlier].path.last }) else { return nil }
                return (earlier, later)
            }
        }

        /// Anonymous siblings sharing their first name — rows that all begin with one icon — told apart by every name each holds, in tree order.
        ///
        /// Those that pair one-to-one are paired. Where some are left in both reads, a row whose own text changed cannot be told from a row replaced, so they are unsure, never paired; where some are left in one read only, they were inserted or removed.
        private mutating func distinguished(_ old: [Placed], _ new: [Placed], was: [Int], now: [Int]) -> [(Int, Int)] {
            let oldGroups = Dictionary(grouping: was) { LayoutShiftRule.names(in: old[$0].node) }
            let newGroups = Dictionary(grouping: now) { LayoutShiftRule.names(in: new[$0].node) }
            var pairs: [(Int, Int)] = []
            var leftOld: [Int] = []
            var leftNew: [Int] = []
            for names in Set(oldGroups.keys).union(newGroups.keys) {
                let earlier = oldGroups[names] ?? []
                let later = newGroups[names] ?? []
                if earlier.count == 1, later.count == 1 {
                    pairs.append((earlier[0], later[0]))
                } else {
                    leftOld += earlier
                    leftNew += later
                }
            }
            if !leftOld.isEmpty, !leftNew.isEmpty {
                markUnsure(old, new, was: leftOld, now: leftNew)
            }
            return pairs
        }

        /// Leaves siblings `was` and `now`, and everything under them, out: neither moved nor a cause.
        private mutating func markUnsure(_ old: [Placed], _ new: [Placed], was: [Int], now: [Int]) {
            unsureOld.formUnion(was.flatMap { Self.subtree($0, in: old) })
            unsureNew.formUnion(now.flatMap { Self.subtree($0, in: new) })
        }

        /// Each anonymous sibling that is the only anonymous one of its type in both reads — the window under the application — paired with its counterpart whatever names they hold, since a replaced first label (a loading text become a header) otherwise leaves the whole screen unpaired.
        private static func lone(_ old: [Placed], _ new: [Placed], olds: [Int], news: [Int]) -> [(Int, Int)] {
            olds.compactMap { earlier in
                let type = old[earlier].node.type
                let alike = olds.filter { !old[$0].isNamed && old[$0].node.type == type }
                let later = news.filter { !new[$0].isNamed && new[$0].node.type == type }
                guard !old[earlier].isNamed, alike.count == 1, later.count == 1 else { return nil }
                return (earlier, later[0])
            }
        }

        private static func subtree(_ index: Int, in placed: [Placed]) -> [Int] {
            [index] + placed[index].children.flatMap { subtree($0, in: placed) }
        }
    }

    /// Two consecutive reads, matched element for element.
    struct Pair {
        let old: [Placed]
        let new: [Placed]
        /// For each element of `new`, its match in `old`.
        let matched: [Int: Int]
        let changes: [Change]

        init(before: AXNode, after: AXNode) {
            let old = LayoutShiftRule.flatten(before)
            let new = LayoutShiftRule.flatten(after)
            let pairing = Pairing(old: old, new: new)
            let matched = pairing.matched
            let kept = Set(matched.values)
            var changes = new.indices.filter { matched[$0] == nil && !pairing.unsureNew.contains($0) }.map { Change(kind: .inserted, before: nil, after: new[$0].node.frame, element: new[$0].element(in: new), oldIndex: nil, newIndex: $0) }
            changes += old.indices.filter { !kept.contains($0) && !pairing.unsureOld.contains($0) }.map { Change(kind: .removed, before: old[$0].node.frame, after: nil, element: old[$0].element(in: old), oldIndex: $0, newIndex: nil) }
            changes += new.indices.compactMap { index in
                guard let earlier = matched[index] else { return nil }
                let was = old[earlier].node.frame
                let now = new[index].node.frame
                guard max(abs(now.width - was.width), abs(now.height - was.height)) >= threshold else { return nil }
                return Change(kind: .resized, before: was, after: now, element: new[index].element(in: new), oldIndex: earlier, newIndex: index)
            }
            self.old = old
            self.new = new
            self.matched = matched
            self.changes = changes
        }

        func shifts(at elapsed: TimeInterval, afterScroll: Bool) -> [CaptureManifest.Motion.Shift] {
            let scrolled = scrolls()
            let contents = scrollContents()
            var reported: [Int: Offset] = [:]
            var shifts: [CaptureManifest.Motion.Shift] = []
            for index in new.indices {
                guard let earlier = matched[index], new[index].isNamed else { continue }
                let before = old[earlier].node.frame
                let after = new[index].node.frame
                let offset = Offset(from: before, to: after)
                guard offset.magnitude >= threshold else { continue }
                if new[index].ancestors.contains(where: { reported[$0]?.matches(offset) == true }) {
                    continue
                }
                if afterScroll, isScrolling(index, by: offset, in: contents) {
                    continue
                }
                if isCarried(index, by: offset, in: scrolled) {
                    continue
                }
                guard let cause = cause(moving: before, to: after, by: offset) else { continue }
                reported[index] = offset
                shifts.append(CaptureManifest.Motion.Shift(
                    element: new[index].element(in: new),
                    before: before,
                    after: after,
                    movedAtMilliseconds: Int((elapsed * 1000).rounded()),
                    cause: CaptureManifest.Motion.Cause(change: cause.kind, element: cause.element)
                ))
            }
            return shifts
        }

        /// How far each matched element under a scroll container of `new` moved, per container, at any depth — worked out once per read, since every moved element asks.
        func scrollContents() -> [Int: [Offset]] {
            var contents: [Int: [Offset]] = [:]
            for index in new.indices {
                guard let moved = offset(of: index) else { continue }
                for container in new[index].ancestors where SystemSheetScope.scrollTypes.contains(new[container].node.type) {
                    contents[container, default: []].append(moved)
                }
            }
            return contents
        }

        /// Whether the element at `index` of `new` moved by the offset most of its nearest scroll container's contents (`contents`) moved by.
        func isScrolling(_ index: Int, by offset: Offset, in contents: [Int: [Offset]]) -> Bool {
            guard let container = new[index].ancestors.last(where: { SystemSheetScope.scrollTypes.contains(new[$0].node.type) }) else { return false }
            let offsets = contents[container] ?? []
            let sharing = offsets.count { $0.matches(offset) }
            return sharing * 2 > offsets.count
        }

        /// How far the element at `index` of `new` moved, when it is matched.
        func offset(of index: Int) -> Offset? {
            matched[index].map { Offset(from: old[$0].node.frame, to: new[index].node.frame) }
        }

        /// The scroll containers of `new` whose content scrolled, each with how far its content moved within it.
        ///
        /// A container's content is every matched element whose nearest scroll container it is, and it scrolled when all of it that moved, measured against the container's own move, moved by one offset — a section header pinned in place while the rows scroll under it is no exception — and no change inside the container `accounts(for:in:_:)` that offset, nor a replacement `isReplaced(accounting:in:)`.
        func scrolls() -> [Int: Offset] {
            var contents: [Int: [Offset]] = [:]
            for index in new.indices {
                guard let container = new[index].ancestors.last(where: { SystemSheetScope.scrollTypes.contains(new[$0].node.type) }),
                      let own = offset(of: index), let base = offset(of: container) else { continue }
                contents[container, default: []].append(own.relative(to: base))
            }
            var scrolled: [Int: Offset] = [:]
            for (container, offsets) in contents {
                let moved = offsets.filter { $0.magnitude >= threshold }
                guard let first = moved.first, moved.allSatisfy({ $0.matches(first) }),
                      !changes.contains(where: { accounts(for: first, in: container, $0) }), !isReplaced(accounting: first, in: container) else { continue }
                scrolled[container] = first
            }
            return scrolled
        }

        /// Whether the element at `index` of `new` moved with the content of a scroll container that scrolled, measured against the container's own move.
        func isCarried(_ index: Int, by offset: Offset, in scrolled: [Int: Offset]) -> Bool {
            new[index].ancestors.contains { container in
                guard let content = scrolled[container], let base = self.offset(of: container) else { return false }
                return offset.relative(to: base).matches(content)
            }
        }

        /// Whether `change` lies inside `container` and its extent along the line of `offset` is that offset, within `threshold`: an inserted or removed box with the gap to the nearest matched element beyond it, in the read it is in — an inserted one also with the gap before it (a banner whose gap above is not the first row's) — or a resize's growth.
        ///
        /// Never the box alone: a scroll steps through every offset, so its move between two reads would match the height of some row, or some icon in a row, that a lazy list built meanwhile (#67 M2 review).
        func accounts(for offset: Offset, in container: Int, _ change: Change) -> Bool {
            let line = Line(offset: offset)
            let extents: [Double?]
            switch change.kind {
            case .inserted:
                guard let index = change.newIndex, new[index].ancestors.contains(container) else { return false }
                let beside = new.indices.filter { matched[$0] != nil && new[$0].ancestors.contains(container) }.map { new[$0].node.frame }
                let box = new[index].node.frame
                extents = [line.extent(of: box, behind: true, beside: beside), line.extent(of: box, behind: false, beside: beside)]
            case .removed:
                guard let index = change.oldIndex, let was = matched[container], old[index].ancestors.contains(was) else { return false }
                let kept = Set(matched.values)
                let beside = old.indices.filter { kept.contains($0) && old[$0].ancestors.contains(was) }.map { old[$0].node.frame }
                let box = old[index].node.frame
                extents = [line.extent(of: box, behind: false, beside: beside)]
            case .resized:
                guard let index = change.newIndex, new[index].ancestors.contains(container), let was = change.before, let now = change.after else { return false }
                extents = [line.growth(from: was, to: now)]
            }
            return extents.contains { $0.map { abs($0 - line.distance(offset)) < threshold } ?? false }
        }

        /// Whether an insertion and a removal inside `container` that start at one place on the line of `offset`, in one column or row — a loading text replaced by the header it became — differ in length along that line by that offset, within `threshold`: the boxes' own lengths, not their extents to a neighbour, since both would measure to the same moved row and differ by the scroll whatever it was.
        func isReplaced(accounting offset: Offset, in container: Int) -> Bool {
            guard let was = matched[container] else { return false }
            let line = Line(offset: offset)
            let onward = Line(vertical: line.vertical, forward: true)
            let inserted = changes.compactMap { change -> AXNode.Frame? in
                guard change.kind == .inserted, let index = change.newIndex, new[index].ancestors.contains(container) else { return nil }
                return change.after
            }
            let removed = changes.compactMap { change -> AXNode.Frame? in
                guard change.kind == .removed, let index = change.oldIndex, old[index].ancestors.contains(was) else { return nil }
                return change.before
            }
            let distance = line.vertical ? offset.dy : offset.dx
            return inserted.contains { box in
                removed.contains { onward.startsTogether(box, $0) && abs(onward.length(of: box) - onward.length(of: $0) - distance) < threshold }
            }
        }

        /// The nearest change that displaced an element moving from `before` to `after`, if one did.
        func cause(moving before: AXNode.Frame, to after: AXNode.Frame, by offset: Offset) -> Change? {
            let line = Line(offset: offset)
            let candidates = changes.compactMap { change -> (Change, Double)? in
                line.gap(displacing: before, to: after, by: change).map { (change, $0) }
            }
            return candidates.min { $0.1 < $1.1 }?.0
        }
    }

    /// An element inserted, removed or resized between two reads, with its box in each read it is in.
    struct Change {
        let kind: CaptureManifest.Motion.Cause.Change
        let before: AXNode.Frame?
        let after: AXNode.Frame?
        let element: CaptureManifest.Motion.Element
        /// Its position in the earlier read's flattened elements; `nil` for an insertion.
        let oldIndex: Int?
        /// Its position in the later read's; `nil` for a removal.
        let newIndex: Int?
    }

    /// How far a box's origin moved between two reads.
    struct Offset {
        let dx: Double
        let dy: Double

        init(from before: AXNode.Frame, to after: AXNode.Frame) {
            dx = after.x - before.x
            dy = after.y - before.y
        }

        private init(dx: Double, dy: Double) {
            self.dx = dx
            self.dy = dy
        }

        /// This move as seen from a box that itself moved by `base`.
        func relative(to base: Self) -> Self {
            Self(dx: dx - base.dx, dy: dy - base.dy)
        }

        var magnitude: Double {
            max(abs(dx), abs(dy))
        }

        func matches(_ other: Self) -> Bool {
            abs(dx - other.dx) < threshold && abs(dy - other.dy) < threshold
        }
    }

    /// A move's line: its dominant axis, and which way along it.
    struct Line {
        let vertical: Bool
        let forward: Bool

        init(offset: Offset) {
            vertical = abs(offset.dy) >= abs(offset.dx)
            forward = (vertical ? offset.dy : offset.dx) > 0
        }

        init(vertical: Bool, forward: Bool) {
            self.vertical = vertical
            self.forward = forward
        }

        /// How far `change` lies from the moved element along the line, when it is a change that pushed it — grown or inserted behind it — or pulled it — shrunk or removed in front of it; `nil` when it is neither.
        func gap(displacing before: AXNode.Frame, to after: AXNode.Frame, by change: Change) -> Double? {
            switch change.kind {
            case .inserted:
                return change.after.flatMap { behind(after, $0) }
            case .removed:
                return change.before.flatMap { ahead(before, $0) }
            case .resized:
                guard let was = change.before, let now = change.after else { return nil }
                // The edge facing the moved element, and how far it moved towards the side the element went.
                let facingBehind = forward ? end(now) - end(was) : start(was) - start(now)
                let facingAhead = forward ? start(now) - start(was) : end(was) - end(now)
                if facingBehind >= threshold, let gap = behind(after, now) {
                    return gap
                }
                if facingAhead >= threshold, let gap = ahead(before, was) {
                    return gap
                }
                return nil
            }
        }

        /// How far `box`, a change lying `behind` content (inserted or grown) or ahead of it (removed or shrunk), carried that content along this line: from the edge of `box` away from the content to the same edge of the nearest of `neighbours` beyond it in its column or row — its own length and the gap to its neighbour; `nil` with no neighbour.
        func extent(of box: AXNode.Frame, behind: Bool, beside neighbours: [AXNode.Frame]) -> Double? {
            let near = neighbours.filter { overlaps($0, box) }
            if behind == forward {
                return near.filter { start($0) >= end(box) - threshold }.map { start($0) - start(box) }.min()
            }
            return near.filter { end($0) <= start(box) + threshold }.map { end(box) - end($0) }.min()
        }

        /// How long `box` is along this line.
        func length(of box: AXNode.Frame) -> Double {
            end(box) - start(box)
        }

        /// How much a box resized from `was` to `now` grew or shrank along this line.
        func growth(from was: AXNode.Frame, to now: AXNode.Frame) -> Double {
            abs((end(now) - start(now)) - (end(was) - start(was)))
        }

        /// How far `offset` moved along this line.
        func distance(_ offset: Offset) -> Double {
            abs(vertical ? offset.dy : offset.dx)
        }

        /// Whether the two boxes start at one place on this line, within `threshold`, and share a column or row.
        func startsTogether(_ one: AXNode.Frame, _ other: AXNode.Frame) -> Bool {
            abs(start(one) - start(other)) < threshold && overlaps(one, other)
        }

        /// The gap from `box` to `moved` when `box` lies behind it on this line and shares its column or row.
        private func behind(_ moved: AXNode.Frame, _ box: AXNode.Frame) -> Double? {
            let gap = forward ? start(moved) - end(box) : start(box) - end(moved)
            return gap > -threshold && overlaps(moved, box) ? max(gap, 0) : nil
        }

        /// The gap from `moved` to `box` when `box` lies ahead of it on this line and shares its column or row.
        private func ahead(_ moved: AXNode.Frame, _ box: AXNode.Frame) -> Double? {
            let gap = forward ? start(box) - end(moved) : start(moved) - end(box)
            return gap > -threshold && overlaps(moved, box) ? max(gap, 0) : nil
        }

        private func start(_ box: AXNode.Frame) -> Double {
            vertical ? box.y : box.x
        }

        private func end(_ box: AXNode.Frame) -> Double {
            vertical ? box.y + box.height : box.x + box.width
        }

        /// Whether the two boxes share a column (a vertical line) or a row (a horizontal one).
        private func overlaps(_ one: AXNode.Frame, _ other: AXNode.Frame) -> Bool {
            vertical
                ? one.x < other.x + other.width && other.x < one.x + one.width
                : one.y < other.y + other.height && other.y < one.y + one.height
        }
    }
}
