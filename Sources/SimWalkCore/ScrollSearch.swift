//
// Copyright © Agulhas Labs
//

import Foundation

/// A `scrollTo` swiping towards an element it cannot reach yet, and why it stopped where it never did (SimWalk#74).
///
/// **Swipe, then resolve.** The step used to resolve its label first and swipe only towards an element it had found — but a lazy list builds no row below the fold, so on Apple Settings `scrollTo 'Privacy & Security'` found nothing, spent the lookup, never swiped, and answered a bare "did not land". So while the label resolves to nothing the runner swipes and reads again (`seek`), and once something carries it the step resolves it as before and swipes until the element it chose would take a tap (`reach`). One budget of swipes covers both halves, so the bound a step documents is the bound it has.
///
/// **Towards the element, not only up** (SimWalk#280). The seek swipes up, since a lazy list builds what is below the fold; but an element the tree holds above the visible part of its list (home left scrolled to its foot, the target under a pinned header) is never brought down by a swipe up, and the step used to stop at the list's end and call it out of reach. So once the label resolves, each swipe goes towards where the element was read: down, to reveal what is above, when it lies wholly above the visible top of its scroll container; otherwise up, as before.
///
/// **Two ways to stop, each named on the UNREACHABLE with the label and the swipes taken**: a swipe after which the screen read exactly as it did before — frames included, which is why this compares the whole tree where `ScreenIdentity` deliberately ignores geometry and would call every scroll a standstill — is the end of the list, or a screen with nothing to scroll; and the budget running out while the screen still moved. Whether the label ever resolved is said as well, because "nothing carries it" and "it is there and never came within reach" send a reader to different places — the walkbook, or the screen.
///
/// **A reason, not an `UnreachableCause`.** A cause names what the walk's verdict counts apart from a missing control: a fact about the walk's own reads (`snapshotBlind`). A row a scroll cannot reach is a fact about the app or the walkbook, which is exactly what `reason` carries — so no new cause, and nothing for an older binary's decoder to pass over.
///
/// A value that takes each read and returns the next move, as `RouteTargetTracker` is, so a test replays it against scripted trees; the runner keeps only the reads and the swipes.
public struct ScrollSearch: Sendable {
    /// What the step names.
    public let label: String
    /// The most swipes the step takes, both halves together.
    public let limit: Int
    /// How many swipes the step has taken so far, in either direction.
    public private(set) var swipes = 0
    /// How many of them were down, towards what is above (SimWalk#280).
    private var swipesDown = 0
    /// The direction of the last swipe, which says which end a standstill reached.
    private var lastDirection = Direction.up
    /// The tree the last swipe was taken from, which the read after it is judged against.
    private var swipedFrom: AXNode?
    /// The last tree the step read, which a miss lists the nearest labels of (SimWalk#273).
    private var lastTree: AXNode?
    /// What the step resolved and is swiping towards, once it resolved anything.
    private var target: RouteTarget.Candidate?

    public init(label: String, limit: Int) {
        self.label = label
        self.limit = limit
    }

    /// The next move having read `tree` while the step's label resolves to nothing: `.found` once anything carries it (resolve it then), otherwise a swipe, or the stop.
    public mutating func seek(in tree: AXNode) -> Move {
        next(tree, found: RouteTarget.choose(labelled: label, in: tree, reaching: .anything) != .none)
    }

    /// The next move when `seek` said `.found` over `tree` and the runner's own resolve, after its lookup, found nothing: the label was on that read and is gone from the last, so the step swipes on, and the swipe counts against the budget like any other — a found-then-none that cost nothing would repeat without limit.
    public mutating func lostAfterFound(in tree: AXNode) -> Move {
        next(tree, found: false)
    }

    /// The next move having read `tree` with `target` resolved and bound, its live frame `frame`: `.found` once `hittable` — a tap would land on it — otherwise a swipe towards it (``direction(towards:at:in:)``), or the stop.
    public mutating func reach(_ target: RouteTarget.Candidate, at frame: AXNode.Frame, in tree: AXNode, hittable: Bool) -> Move {
        self.target = target
        return next(tree, found: hittable, towards: Self.direction(towards: target.node, at: frame, in: tree))
    }

    /// Which way to swipe towards `element`, read live at `frame`, that a tap would not land on yet (SimWalk#280): down, revealing what is above, only when it lies wholly above the visible top of its scroll container (of the screen, where it sits in none); otherwise up.
    ///
    /// **Only on that evidence.** A table reports a row it has not laid out yet at its scroll view's top corner (SimWalk#241, a sheet's row below the fold read at `0,117`), so an element read inside the visible part is not known to be above: swiping down there would pull a sheet at its start down, or fire a refresh, where the swipe up that reaches the row has always worked.
    public static func direction(towards element: AXNode, at frame: AXNode.Frame, in tree: AXNode) -> Direction {
        var live = element
        live.frame = frame
        let screen = tree.screenBounds
        let container = ScrollPlacement.containerFrame(of: live, in: tree) ?? screen
        return frame.maxY <= max(container.minY, screen.minY) ? .down : .up
    }

    /// Resolves a label, swiping up and reading again while nothing carries it (SimWalk#74, #104).
    ///
    /// The one seek `tap` and `scrollTo` share, so a lazy list's unbuilt row is searched for the same way by both. Only `.none` seeks, and only a `reach` that `seeksWhenAbsent`: an `.ambiguous` choice, or a `type` step's absent field, is returned as it is. The search is the caller's value because `scrollTo` goes on to use its budget. A search that stops short answers its reason in `stopped`, and the choice is then `.none`. The loop lives here so a test replays it with scripted operations; the runner passes its own `resolve`, tree read and swipe.
    public mutating func resolveSeeking(
        reaching reach: RouteTarget.Reach,
        resolve: () throws -> RouteTarget.Choice,
        read: () throws -> AXNode,
        swipe: (Direction) -> Void
    ) throws -> (choice: RouteTarget.Choice, stopped: String?) {
        var choice = try resolve()
        while choice == .none, reach.seeksWhenAbsent {
            let tree = try read()
            switch seek(in: tree) {
            case let .swipe(direction):
                swipe(direction)
            case .found:
                choice = try resolve()
                // The seek read carried the label and resolve's last read did not: that costs a swipe, or
                // the loop would go round without the bound the Brief documents (`lostAfterFound`).
                if choice == .none {
                    switch lostAfterFound(in: tree) {
                    case let .swipe(direction):
                        swipe(direction)
                    case let .stopped(_, reason):
                        return (choice, reason)
                    case .found:
                        break
                    }
                }
            case let .stopped(_, reason):
                return (choice, reason)
            }
        }
        return (choice, nil)
    }

    private mutating func next(_ tree: AXNode, found: Bool, towards direction: Direction = .up) -> Move {
        lastTree = tree
        // No reset between the halves: the tree the last `seek` swiped from did not carry the label, so the
        // first read `reach` judges — which does — can never read the same as it.
        if found {
            return .found
        }
        // A tree with no scroll container has nothing a swipe moves: the swipe would be one more wait for the
        // comparison below to call a standstill, and a misspelt `tap` label would pay it after the lookup (SimWalk#119).
        guard tree.flattened.contains(where: { Self.scrollContainerTypes.contains($0.type) }) else {
            return .stopped(.nothingScrolls, reason: reason(.nothingScrolls))
        }
        // The same screen up to steady frames: an endless SwiftUI pulse rescales an element between the reads, and
        // a list at its end must not read as one still moving for the rest of the step's swipes.
        if let swipedFrom, swipedFrom.steadyShift(to: tree) != nil {
            return .stopped(.endOfList, reason: reason(.endOfList))
        }
        guard swipes < limit else {
            return .stopped(.limit, reason: reason(.limit))
        }
        swipedFrom = tree
        swipes += 1
        if direction == .down {
            swipesDown += 1
        }
        lastDirection = direction
        return .swipe(direction)
    }

    /// What a swipe can move: the sheet scope's scroll types, and a web view, whose page scrolls under elements the tree lists without any scroll view around them.
    static let scrollContainerTypes = SystemSheetScope.scrollTypes.union(["WebView"])

    private func reason(_ stop: Stop) -> String {
        func times(_ count: Int) -> String {
            count == 1 ? "once" : "\(count) times"
        }
        let swipesUp = swipes - swipesDown
        let swiped = switch (swipesUp, swipesDown) {
        case (_, 0): "swiped up \(times(swipesUp))"
        case (0, _): "swiped down \(times(swipesDown))"
        default: "swiped up \(times(swipesUp)) and down \(times(swipesDown))"
        }
        let end = lastDirection == .down ? "start" : "end"
        let why = switch stop {
        case .nothingScrolls: "nothing on this screen scrolls (no table, collection, scroll or web view), so \(swipes == 0 ? "nothing was swiped" : swiped)"
        case .endOfList: "\(swiped) and the last swipe moved nothing — the list is at its \(end), or nothing here scrolls"
        case .limit: "\(swiped), the most a step takes, and the screen was still moving"
        }
        guard let target else {
            let nearest = lastTree.map { RouteTarget.nearest(to: label, in: $0) } ?? []
            let listed = nearest.isEmpty ? "" : "; nearest: \(nearest.joined(separator: ", "))"
            return "\(RouteTarget.Choice.none.reason(for: label))\(listed): \(why)"
        }
        return "\(target.description) never came within reach of a tap: \(why)"
    }
}

public extension ScrollSearch {
    /// The runner's next move.
    enum Move: Equatable, Sendable {
        /// Swipe once in this direction and read again.
        case swipe(Direction)
        /// What the half was looking for is there: the label resolves (`seek`), or the element would take a tap (`reach`).
        case found
        /// Give up; `reason` is what the UNREACHABLE says, naming the label, the swipes and why they stopped.
        case stopped(Stop, reason: String)
    }

    /// Which way a swipe moves the finger, named as `XCUIElement`'s swipes are.
    enum Direction: Equatable, Sendable {
        /// Up the screen, the content following to reveal what is below: every seek's swipe.
        case up
        /// Down the screen, revealing what is above: towards an element read wholly above the visible part of its list (SimWalk#280).
        case down
    }

    /// Why the swipes stopped short of the element.
    enum Stop: Equatable, Sendable {
        /// A swipe left the screen reading exactly as before it: the list's end, or its start after a swipe down.
        case endOfList
        /// The screen holds no scroll container, so a swipe could move nothing and none was taken (or none more).
        case nothingScrolls
        /// Every swipe the step gets was taken and the screen was still moving.
        case limit
    }
}
