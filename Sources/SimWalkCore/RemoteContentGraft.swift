//
// Copyright © Agulhas Labs
//

import Foundation

/// Puts a remote sheet's content into an app tree read that stops where the sheet is hosted, found element by element in the live hierarchy (SimWalk#48).
///
/// **The trigger is the app's launch, not the test session.** With the sheet's host process alive — HealthKit's is `com.apple.HealthPrivacyService` — the first launch of the app after the host started gets the sheet's content in `app.snapshot()`; after a terminate and relaunch, with the host the same process, the snapshot ends in a childless anonymous `Other` where the sheet is hosted, while the live query still reaches every control on it. Measured on iOS 27.0: 15 tree nodes against 500 live descendants.
///
/// **The live hierarchy is not the snapshot's shape, so nothing here binds a tree node to a live element.** Live, the window holds copies of the host chain the snapshot has, the app's own screen underneath (absent from the snapshot even on a first launch, and never grafted), and *placeholders*: elements whose own snapshot is one childless node but which have live children. The remote root is the content under a placeholder — its own `snapshot()` holds the whole sheet, in the sheet's coordinates, which is the space a first launch's `app.snapshot()` uses too, so nothing is translated and `SystemSheetScope.admits` compares like with like. So the walk goes by live index paths, depth first from the windows, passing only through placeholders and host chains, and asks the runner one element at a time: a live element bound by a snapshot node's index path is a different element, or none, and XCUITest records "No matches found" as a test failure.
///
/// **Grafted only where the tree has room for it.** A tree that already holds most of the root's fixed labelled nodes, by label and identifier, with at least one at the root's own box (SimWalk#58, #61) — the first launch — is left as it is, so the sheet is never there twice, not even inside itself; otherwise the root replaces the tree's frontmost on-screen childless anonymous leaf of its own type and frame. The off-screen leaf the host also leaves is a placeholder for another copy of the host chain, and its frame is not the root's. A candidate with no place in the tree — a copy of the sheet in other coordinates, or content that is not the sheet — is passed over and the walk goes on, within its read limit; only content under a placeholder is ever a candidate, so the app's own hidden screen is never grafted.
///
/// **What it costs is bounded and paid only on a screen that can need it.** Each live read is 50–110 ms, so the walk starts only when the tree has an on-screen childless anonymous leaf *and* the app has more live descendants than the tree has nodes — a plain screen has leaves like that and fewer descendants — and stops once it has cost `readLimit` live queries. What the walk came to comes back with the tree as a `Recall`, for the caller to pass in again: the root's path, read first and alone, or that a tree of this shape was walked for nothing, which a read of the same shape is not walked again for (SimWalk#56). A walk that reached a host placeholder with zero live children, since content can still arrive there, is remembered with the app's live descendant count instead, and a read of the same shape asks that one count again in place of the walk: the same count is the same empty placeholder, any other is walked again, and every `rewalkEvery`-th read is walked again whatever the count (SimWalk#84). A walk that passed over a candidate, met an element it could not read, or was cut short by the read limit with something left to visit is not remembered at all: the host can move content it never placed under the on-screen site without changing the tree's shape or the app's count, and a walk cut short never reached what lies past its limit (SimWalk#86).
///
/// **In the core because the runner's side of it is not tested.** The runner answers each `Step` with a live read and this decides the next, the shape `SettleTracker` set, so a scripted hierarchy replays the whole walk under `swift test`.
public struct RemoteContentGraft {
    private let tree: AXNode
    private let readLimit: Int
    private var recall: Recall
    private var phase = Phase.starting
    private var pending: [Visit] = []
    private var reads = 0
    /// Whether this walk found a host placeholder with zero live children: content HealthKit has not put there yet, so a walk that otherwise finds nothing is remembered as `Recall.emptyPlaceholder` — its live count asked again next read — where a walk that ran to its end and found nothing for any other reason is `Recall.noRoot` (SimWalk#56, #84).
    private var sawEmptyLivePlaceholder = false
    /// Whether this walk passed over a remote root with no place in the tree — a copy in other coordinates, or content whose frame matches no site yet.
    ///
    /// The host can move that content under the on-screen site without changing the tree's shape or the app's live count, so a walk that did is `Recall.unknown`, walked again next read, never `Recall.emptyPlaceholder` (SimWalk#84) or `Recall.noRoot` (SimWalk#86).
    private var passedOverCandidate = false
    /// Whether a read this walk asked for came back `Answer.unreadable`: an element gone since its parent's count, or one whose snapshot failed mid-transition.
    ///
    /// The walk never saw what is under it, which can be the sheet's content, and the next read can find it there with the tree's shape and the app's live count unchanged, so a walk that met one is `Recall.unknown`, like one that passed over a candidate (SimWalk#86).
    private var metUnreadableElement = false
    /// The app's live descendant count the gate let this walk through on: what an empty placeholder's walk is remembered by (SimWalk#84).
    private var descendants = 0

    /// How many reads of a remembered `Recall.emptyPlaceholder` there are to each full walk: the k-th is walked again even where the count is unchanged (SimWalk#84).
    ///
    /// The count is over the whole app, so content arriving just as as many of the app's own elements go leaves it equal; this bounds how long that can hide the content. Four keeps that to three cached reads, about 1 s at a poll's 250 ms sleep plus a one-count read, a tenth of a lookup's 10 s timeout, while a read costs (10 + 3) / 4 ≈ 3.3 live queries on average against the walk's 10.
    static let rewalkEvery = 4

    /// - Parameters:
    ///   - tree: The app's tree as `app.snapshot()` read it.
    ///   - recall: What the previous tree read's walk came to: a root's live path is read first, and a tree of the shape a walk found nothing in is not walked.
    ///   - readLimit: How many live queries the walk may cost before it leaves the tree as it is — each `Step` charged what the runner's answer to it queries (`queries(for:)`), not one a request (SimWalk#57).
    public init(tree: AXNode, recall: Recall = .unknown, readLimit: Int = 40) {
        self.tree = tree
        self.recall = recall
        self.readLimit = readLimit
    }

    /// The first live read to make, or the tree as it is where it has nowhere to graft to.
    public mutating func start() -> Step {
        guard Self.hasGraftSite(in: tree) else { return .done(tree, recall: recall) }
        switch recall {
        case let .root(path):
            phase = .cached(path)
            return request(.read(path, known: true))
        case let .noRoot(shape) where shape == Shape(of: tree):
            // Walked for nothing already: a screen that passes the gate with no remote root would pay the whole walk on every settle and dismissal poll.
            return .done(tree, recall: recall)
        case let .emptyPlaceholder(shape, descendants, held) where shape == Shape(of: tree):
            phase = .recounting(descendants, held: held)
            return request(.countDescendants)
        case .unknown, .noRoot, .emptyPlaceholder:
            phase = .gate
            return request(.countDescendants)
        }
    }

    /// The next live read, given the answer to the last one.
    public mutating func next(_ answer: Answer) -> Step {
        switch phase {
        case .starting:
            return start()
        case .gate:
            return gate(answer)
        case let .recounting(descendants, held):
            // The walk of this shape ended at an empty placeholder (SimWalk#84). Content arriving under it, or anywhere
            // else in the app, raises the live count, so the same count is the same empty placeholder and nothing is
            // walked; any other count is walked again as at the gate, and so is every `rewalkEvery`-th read, since a
            // count that stayed equal while content arrived would otherwise hide it for the rest of the step. The
            // placeholder's own child count is not asked instead: a live element inserted ahead of it re-points its
            // index path at other content or at none, which the runner answers as zero, and the snapshot's shape
            // need not change when that happens.
            if answer == .count(descendants), held + 1 < Self.rewalkEvery {
                return finish(.emptyPlaceholder(Shape(of: tree), descendants: descendants, held: held + 1))
            }
            return gate(answer)
        case let .cached(path):
            // Its snapshot alone: nothing is walked from a known root, so its live children are never counted. Kept only
            // where it still has a place in the tree — held there, or a site of its type and frame (SimWalk#56): whether
            // it is under a placeholder cannot be asked again without that count, and after a live reshuffle the same
            // index path can name other content, which goes back to the gate like a root that has gone.
            if case let .element(snapshot) = answer, Self.isRemoteRoot(snapshot), let placed = placing(snapshot) {
                phase = .starting
                return .done(placed, recall: .root(path))
            }
            recall = .unknown
            phase = .gate
            return request(.countDescendants)
        case let .visiting(visit):
            return visited(visit, answer)
        case let .counting(path, children):
            if case let .count(count) = answer {
                push(children: count, of: path, as: children)
            }
            return walk()
        }
    }

    /// The walk from the app's live children, given its live descendant count: made only where the app has more of them than the tree has nodes.
    private mutating func gate(_ answer: Answer) -> Step {
        guard case let .count(count) = answer, count > tree.flattened.count else { return finish(.unknown) }
        descendants = count
        pending = [Visit(path: [], kind: .container)]
        sawEmptyLivePlaceholder = false
        passedOverCandidate = false
        metUnreadableElement = false
        return walk()
    }

    private mutating func visited(_ visit: Visit, _ answer: Answer) -> Step {
        guard case let .element(underPlaceholder) = visit.kind else { return walk() }
        guard case let .element(snapshot) = answer else {
            // Never seen, so whatever is under it was never ruled out: passed over, and the walk is not remembered (SimWalk#86).
            metUnreadableElement = true
            return walk()
        }
        if snapshot.children.isEmpty {
            return count(visit.path, as: .element(underPlaceholder: true))
        }
        if underPlaceholder, Self.isRemoteRoot(snapshot) {
            if let placed = placing(snapshot) {
                phase = .starting
                return .done(placed, recall: .root(visit.path))
            }
            // A copy in other coordinates, or content that is not the sheet: passed over, and the walk goes on.
            passedOverCandidate = true
        } else if Self.isHostChain(snapshot) {
            return count(visit.path, as: .element(underPlaceholder: false))
        }
        return walk()
    }

    private mutating func walk() -> Step {
        guard let visit = pending.popLast() else {
            // Nothing left to visit: the walk ran to its end, through every placeholder and host chain the tree
            // offered, even where its last query spent the whole limit. A candidate it passed over, or an element it
            // could not read, can be moved by the host under the on-screen site with the tree's shape and the app's
            // count unchanged, so that walk is not remembered at all (SimWalk#84, #86). A placeholder with zero live
            // children is not a dead end — content may still arrive under it — so that outcome is remembered with the
            // live count that the content's arrival would change, never as a shape walked for nothing.
            guard !passedOverCandidate, !metUnreadableElement else { return finish(.unknown) }
            let shape = Shape(of: tree)
            return finish(sawEmptyLivePlaceholder ? .emptyPlaceholder(shape, descendants: descendants, held: 0) : .noRoot(shape))
        }
        // Cut short by the read limit with something left to visit: what lies past it was never read, so nothing is
        // remembered (SimWalk#86).
        guard reads < readLimit else { return finish(.unknown) }
        guard visit.kind == .container else {
            phase = .visiting(visit)
            return request(.read(visit.path, known: false))
        }
        return count(visit.path, as: visit.path.isEmpty ? .container : .element(underPlaceholder: false))
    }

    /// Asks for the live children of the element at `path`, to be visited as `kind`: only a container's, a placeholder's and a host-chain link's are ever counted.
    private mutating func count(_ path: [Int], as kind: Visit.Kind) -> Step {
        guard reads + Self.queries(for: .countChildren(path)) <= readLimit else { return finish(.unknown) }
        phase = .counting(path, children: kind)
        return request(.countChildren(path))
    }

    private mutating func push(children count: Int, of path: [Int], as kind: Visit.Kind) {
        if count == 0, kind == .element(underPlaceholder: true) {
            sawEmptyLivePlaceholder = true
        }
        // Reversed, so the first child is the next popped: tree order, depth first.
        pending += (0 ..< count).reversed().map { Visit(path: path + [$0], kind: kind) }
    }

    private mutating func request(_ step: Step) -> Step {
        reads += Self.queries(for: step)
        return step
    }

    /// The live queries the runner's answer to `step` makes (SimWalk#57): an `exists` ahead of a count below the app and of a known root's snapshot, so each of those costs two; the app's own count and a walk's read of an element just counted cost one.
    private static func queries(for step: Step) -> Int {
        switch step {
        case let .countChildren(path): path.isEmpty ? 1 : 2
        case let .read(_, known): known ? 2 : 1
        case .countDescendants: 1
        case .done: 0
        }
    }

    private mutating func finish(_ recall: Recall) -> Step {
        phase = .starting
        return .done(tree, recall: recall)
    }

    /// Where `content` goes: the tree as it is where it already holds it — the first launch — else the tree with `content` in place of the frontmost graft site of its type and frame, else `nil`, the content having no place in this tree.
    ///
    /// The held check comes first because a first launch's sheet can itself hold a site: a childless anonymous `Other` at the sheet's own box, into which the sheet would be grafted again, every control on it twice.
    private func placing(_ content: AXNode) -> AXNode? {
        if Self.holds(content, in: tree) {
            return tree
        }
        var site: [Int]?
        Self.visit(tree, at: []) { node, nodePath in
            if Self.isGraftSite(node, on: tree.frame), node.type == content.type, Self.isSameBox(node.frame, content.frame) {
                // The last in tree order: of two sites at one box, the one drawn in front.
                site = nodePath
            }
        }
        guard let site else { return nil }
        var grafted = tree
        Self.replace(at: site[...], in: &grafted, with: content)
        return grafted
    }

    /// Whether `tree` already holds `content`: every labelled or identified node in it outside a scrolling container is found in the tree by label and identifier (most of its nodes, where it has none outside one), and one thing in it that does not move — such a node, or a scrolling container that is not inside another — is found at its own box.
    ///
    /// Judged by what the content holds rather than by its box (SimWalk#57): a sheet that fills the screen — a full-screen presentation, or a page sheet in compact height — shares its box with the host screen, a branching anonymous `Other` in every relaunch tree, which would read as the sheet already there and leave it ungrafted. Content with nothing labelled or identified in it is never held: nothing in it could say so, and it goes to a graft site like any other.
    ///
    /// **A node is found by its label and identifier; its type and frame are not compared** (SimWalk#58). On a first launch the tree and the root's own snapshot are read hundreds of milliseconds apart, and a sheet whose table is still decelerating changes in exactly those two between the reads: its rows move, and below-the-fold rows turn from `StaticText` into `Button`s (SimWalk#47). Requiring either failed the check on a sheet the tree held, and the content went into the in-sheet site `placing` guards against, every control on it twice.
    ///
    /// **The rows are not judged where the content has a node outside its table** (SimWalk#58, #61 item 2): the same scroll can take a row out of the tree between the two reads, and one decelerating far brings rows into the snapshot that the tree never read, so rows scrolling in and out are no evidence either way. Content that is all table has nothing else to judge, and is held when most of its rows are found.
    ///
    /// **Every node outside a scrolling container is found** (SimWalk#78 item 1): those nodes do not scroll out of a read, so one the tree lacks is evidence the sheet is not there. A majority of them was too weak a test on a sheet the size of HealthKit's, with three: an app primer whose `Allow` and `Don't Allow` sit at the sheet's own boxes matched two of them, both at their boxes, and read as held on a relaunch.
    ///
    /// **And something that does not move is at its own box** (SimWalk#61 item 1, #78): labels alone are no evidence of the sheet, because an app primer under it can carry every one of them — its title, its buttons and its rows — at its own boxes, not the sheet's. The snapshot and the tree share the sheet's coordinates, so what the scroll does not move sits at the same box in both reads: a node outside the table, or the table itself, matched by type and box, whose box stays put while its rows scroll. One is enough, because a node outside the table can still move between the reads: a large title collapses as the table scrolls, and where that title is the sheet's only such node, the table's box is all that holds still.
    ///
    /// **Residual risks.** A node outside the table whose label changes between a first launch's two reads grafts the sheet into itself, every control twice; the old majority tolerated one, and gave the primer above its two of three. Any app scroll container at the sheet's container box, over an app screen that also carries every one of the sheet's fixed labels, reads as held (SimWalk#91): the scroller anchor matches any node in the tree by type and box, so the sheet is not grafted. A full-screen sheet over an app container that fills the screen is the likeliest case, since a container's box is distinctive only where it is not the screen's, but a `Table` at exactly the sheet's table box on a relaunch is enough.
    private static func holds(_ content: AXNode, in tree: AXNode) -> Bool {
        let nodes = tree.flattened
        let marks = marks(in: content, scrolling: false)
        let fixed = marks.filter { !$0.scrolls }
        let isFound = { (mark: Mark) in nodes.contains { isSameMark($0, as: mark.node) } }
        let labelled = fixed.isEmpty ? marks.count(where: isFound) * 2 > marks.count : fixed.allSatisfy(isFound)
        guard labelled else {
            return false
        }
        let anchoredByNode = fixed.contains { mark in
            nodes.contains { isSameMark($0, as: mark.node) && isSameBox($0.frame, mark.node.frame) }
        }
        return anchoredByNode || scrollers(in: content).contains { scroller in
            nodes.contains { $0.type == scroller.type && isSameBox($0.frame, scroller.frame) }
        }
    }

    /// The scrolling containers in `node` that no other holds: the boxes that stay put while their rows scroll.
    private static func scrollers(in node: AXNode) -> [AXNode] {
        SystemSheetScope.scrollTypes.contains(node.type) ? [node] : node.children.flatMap(scrollers(in:))
    }

    /// The labelled or identified nodes in `node`, each with whether it lies inside a scrolling container — one that moves it between two reads.
    private static func marks(in node: AXNode, scrolling: Bool) -> [Mark] {
        let own = node.label != nil || node.identifier != nil ? [Mark(node: node, scrolls: scrolling)] : []
        let inside = scrolling || SystemSheetScope.scrollTypes.contains(node.type)
        return own + node.children.flatMap { marks(in: $0, scrolling: inside) }
    }

    private static func isSameMark(_ node: AXNode, as mark: AXNode) -> Bool {
        node.label == mark.label && node.identifier == mark.identifier
    }

    /// A branching snapshot: the content a placeholder hosts, as opposed to one more link of a host chain.
    private static func isRemoteRoot(_ snapshot: AXNode) -> Bool {
        !snapshot.children.isEmpty && !isHostChain(snapshot)
    }

    /// An anonymous `Other` whose own snapshot is a chain — no node in it with more than one child — which is how the host nests the sheet.
    private static func isHostChain(_ snapshot: AXNode) -> Bool {
        isAnonymousOther(snapshot) && snapshot.flattened.allSatisfy { $0.children.count <= 1 }
    }

    private static func hasGraftSite(in tree: AXNode) -> Bool {
        tree.flattened.contains { isGraftSite($0, on: tree.frame) }
    }

    /// A childless anonymous `Other` lying on `screen` with an area: where a remote sheet's content can be missing from the tree.
    private static func isGraftSite(_ node: AXNode, on screen: AXNode.Frame) -> Bool {
        let frame = node.frame
        return node.children.isEmpty && isAnonymousOther(node)
            && frame.width > 0 && frame.height > 0
            && frame.x >= screen.x - 0.5 && frame.y >= screen.y - 0.5
            && frame.x + frame.width <= screen.x + screen.width + 0.5
            && frame.maxY <= screen.maxY + 0.5
    }

    private static func isAnonymousOther(_ node: AXNode) -> Bool {
        node.type == "Other" && node.label == nil && node.identifier == nil
    }

    private static func isSameBox(_ lhs: AXNode.Frame, _ rhs: AXNode.Frame) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5 && abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    private static func visit(_ node: AXNode, at path: [Int], _ body: (AXNode, [Int]) -> Void) {
        body(node, path)
        for (index, child) in node.children.enumerated() {
            visit(child, at: path + [index], body)
        }
    }

    private static func replace(at path: ArraySlice<Int>, in node: inout AXNode, with content: AXNode) {
        guard let index = path.first else {
            node = content
            return
        }
        replace(at: path.dropFirst(), in: &node.children[index], with: content)
    }
}

public extension RemoteContentGraft {
    /// The live read the runner is to make next, or the walk's result.
    enum Step: Equatable, Sendable {
        /// Count every live descendant of the app — answered with `Answer.count`.
        case countDescendants
        /// Count the live children of the element at this index path from the app — answered with `Answer.count`, `0` where it is gone; asked only of the app, a window, a placeholder or a host-chain link, never of a known root.
        case countChildren([Int])
        /// Take the own snapshot of the element at this index path from the app, and nothing more — answered with `Answer.element`, or `Answer.unreadable` where it is gone or its snapshot could not be taken.
        ///
        /// `known` marks a root an earlier tree read found, which may have gone since — the sheet dismissed — so the runner asks `exists` first: a snapshot of a gone element waits (2.2 s measured on the first read after a HealthKit sheet dismissed, SimWalk#48) before it throws. A walk's read is of an element just counted, and pays no extra query.
        case read([Int], known: Bool)
        /// The tree to judge by — with the remote content in place, or as it was read — and what the walk came to, to pass back in for the next read.
        case done(AXNode, recall: Recall)
    }

    /// What one tree read's walk leaves for the next in the same step.
    enum Recall: Equatable, Sendable {
        /// Nothing to go on: no walk yet, the gate found no more live descendants than tree nodes, a walk that found no remote root passed over a candidate (SimWalk#84, #86), or the read limit cut it short (SimWalk#86).
        case unknown
        /// The live path the remote root was found at, read first and alone by the next read.
        case root([Int])
        /// A walk of a tree of this shape ran to its end and found no remote root, without ever finding a host placeholder with zero live children or passing over a candidate (SimWalk#56, #86).
        case noRoot(Shape)
        /// A walk of a tree of this shape ran to its end and found no remote root, but a host placeholder with zero live children: content not there yet.
        ///
        /// A walk that also passed over a candidate is `unknown` instead.
        ///
        /// The next read of the same shape asks the app's live descendant count alone, and walks again only where it is not `descendants` or where it would be the `rewalkEvery`-th read since the walk; `held` is how many reads have been answered from this since (SimWalk#84).
        case emptyPlaceholder(Shape, descendants: Int, held: Int)
    }

    /// A tree's form: each node's type, identifier and frame, in tree order, without the labels, values and states a poll can see change while the screen stays what it was.
    ///
    /// The key a walk that found nothing is remembered by (SimWalk#56). A changed form — the host chain arriving, a sheet sliding in — is walked again; a read of the same form is not, so a screen that passes the gate with no remote root pays its walk once per step rather than on every poll.
    struct Shape: Equatable, Sendable {
        private let form: AXNode

        init(of tree: AXNode) {
            form = AXNode(type: tree.type, frame: tree.frame, identifier: tree.identifier, children: tree.children.map { Shape(of: $0).form })
        }
    }

    /// What a live read found.
    enum Answer: Equatable, Sendable {
        /// A live count.
        case count(Int)
        /// An element's own snapshot, with its subtree.
        case element(AXNode)
        /// An element whose snapshot could not be taken: gone since its parent was counted.
        case unreadable
    }
}

extension RemoteContentGraft {
    enum Phase {
        case starting
        case gate
        case cached([Int])
        /// Asking the app's live descendant count again for a remembered empty placeholder, walked again where it is not this one or where the reads held reach `rewalkEvery`.
        case recounting(Int, held: Int)
        case visiting(Visit)
        /// Counting the live children of the element at this path, to be visited as the kind given.
        case counting([Int], children: Visit.Kind)
    }

    /// An element still to read, and what its read is for.
    struct Visit {
        let path: [Int]
        let kind: Kind
    }

    /// A labelled or identified node of a sheet's content, and whether a scrolling container holds it.
    struct Mark {
        let node: AXNode
        let scrolls: Bool
    }
}

extension RemoteContentGraft.Visit {
    enum Kind: Equatable {
        /// The app or a window: only its live children are counted, and each is visited.
        case container
        /// An element below a window, whose own snapshot says whether to pass through it — its live children counted only then — and one under a placeholder may be the remote root.
        case element(underPlaceholder: Bool)
    }
}
