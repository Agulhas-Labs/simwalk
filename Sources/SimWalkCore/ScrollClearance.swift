//
// Copyright © Agulhas Labs
//

import Foundation

/// A `scrollTo` nudging its target out from under a bar it has already reached, or saying it cannot (SimWalk#108); and a `tap` whose seek swiped, before it taps (SimWalk#104).
///
/// **Hittable is not clear.** On iOS 27 the floating tab bar sits over scrolling content, and XCUITest calls an element hittable while it is half beneath that bar — so a `scrollTo` that stopped at "a tap would land" captured with its target behind the bar, and the walk read `captured`. Once `ScrollSearch` has found the element, the runner reads its frame and asks this for the next move: nothing where no bar overlaps it, a nudge of the content where one does, or the stop. A `tap` whose label was swiped into the tree asks the same, because the row a seek brings in sits at the fold, where a tap would land on the tab bar instead.
///
/// **A bar** is a `TabBar`, `Toolbar` or `NavigationBar` with area that is shorter than half the screen. That height test is what leaves out the `Toolbar` every capture holds framed at the whole screen: a container, not a bar anything sits under. An element taller than the room between the bars above and below it can never clear them, so it is accepted as it was before this existed. So is a target that is a bar or sits inside one — a tab item, a navigation bar's button — which no scroll moves out from under its own bar (the #108 review: a `scrollTo` whose only match is a tab item lands on it without scrolling).
///
/// **Only a bar in front counts** (the #108 review). A modal can leave the screen it covers in the tree, its tab bar included (SimWalk#95), and the order of the tree is not the order of painting — a navigation bar precedes the content it is drawn over — so the tree cannot say which bar is in front. The runner can: it binds the bar and asks whether it is hittable. `isInFront` is asked only of the bars that overlap the element, so a read with nothing covering it costs no query.
///
/// **Which way** is decided by the side of the screen the bar is on (the #108 reviews): a bar in the lower half covers from below, and the content moves up; one in the upper half, down. Comparing top edges sent a row lying wholly inside the tab bar's band deeper under it, and comparing centres still did for a row in the band's lower half — off the screen, where the next read either lost it or called it clear. The same split decides which bars bound the free space, so a drag never starts on the bar it is clearing.
///
/// **A nudge is a drag**, and a drag moves nothing until it has travelled `slop` points; so `.nudge` names the drag — the distance the element must move plus `slop` — and the runner drags exactly that far. The slop was measured once, on an iPhone 17 (drags of 64, 96 and 192 pt moved the content 2, 34 and 131 pt); where it is larger, a nudge moves nothing, so the first read identical to the one the last nudge came from is answered with that drag doubled, every later nudge of the step is doubled too (the #108 review: a doubled drag that worked says the slop here is larger, and an ordinary nudge after it would move nothing and stop on a false "moved nothing"), and only a doubled drag that moves nothing is taken as the end of the list.
///
/// **Two ways to stop, each an UNREACHABLE reason like `ScrollSearch`'s**: a doubled drag after which the screen read exactly as it did before it — the whole tree compared, frames included — means the list is at its end or nothing here scrolls; and `limit` nudges taken with the element still covered. A capture then never reads `captured` with its target under a bar.
///
/// A value that takes each read and returns the next move, so a test replays it against scripted trees; the runner keeps only the reads and the drags.
public struct ScrollClearance: Sendable {
    /// The most nudges one step takes, not counting the one retried at twice its drag.
    public let limit: Int
    /// How far past a bar's edge the nudge puts the element's, in points, so it does not rest against it.
    public let margin: Double
    /// How far a drag travels before the content follows it, in points.
    public let slop: Double
    /// How many nudges the step has taken so far.
    public private(set) var nudges = 0
    /// The room between the bars the last `next` read, which its nudge's drag starts and ends inside; `next` hands it back so the runner asks no bar twice (SimWalk#122).
    public private(set) var room: ClosedRange<Double> = 0 ... 0
    /// The tree the last nudge was taken from, which the read after it is judged against.
    private var nudgedFrom: AXNode?
    /// The last nudge's drag, which a retry doubles.
    private var lastDrag = 0.0
    /// What every drag is multiplied by: 2 once a nudge has moved nothing, for the rest of the step.
    private var scale = 1.0

    public init(limit: Int = 3, margin: Double = 16, slop: Double = 62) {
        self.limit = limit
        self.margin = margin
        self.slop = slop
    }

    /// The next move having read `tree`, where `frame` is `target`'s frame now and `isInFront` answers whether a bar overlapping it is drawn in front of it.
    public mutating func next(target: RouteTarget.Candidate, frame: AXNode.Frame, in tree: AXNode, isInFront: (AXNode) -> Bool) -> Move {
        guard target.insideBar == nil, !RouteTarget.barTypes.contains(target.node.type) else {
            return .clear
        }
        // Each bar is asked once however many of the reads below need its answer: `isInFront` is a live query.
        let all = Self.bars(in: tree)
        var answers = [Int: Bool]()
        func inFront(_ index: Int) -> Bool {
            if let known = answers[index] {
                return known
            }
            let answer = isInFront(all[index])
            answers[index] = answer
            return answer
        }
        let covering = all.indices.filter { all[$0].frame.intersects(frame) && inFront($0) }.map { all[$0] }
        guard let worst = covering.max(by: { $0.frame.verticalOverlap(with: frame) < $1.frame.verticalOverlap(with: frame) }) else {
            return .clear
        }
        let space = Self.extent(of: all, in: tree, inFront: inFront)
        room = space
        guard frame.height <= space.upperBound - space.lowerBound else {
            return .clear
        }
        if let nudgedFrom, nudgedFrom == tree {
            guard scale == 1 else {
                return .stopped(reason: reason(target, worst, frame, why: "a nudge at twice its drag moved nothing — the list is at its end, or nothing here scrolls"))
            }
            scale = 2
            lastDrag *= 2
            return .nudge(dy: lastDrag)
        }
        guard nudges < limit else {
            return .stopped(reason: reason(target, worst, frame, why: "still covered after \(nudges == 1 ? "1 nudge" : "\(nudges) nudges"), the most a step takes"))
        }
        nudgedFrom = tree
        nudges += 1
        let bar = worst.frame
        let distance = Self.isBelowMiddle(worst, of: tree) ? frame.maxY - bar.minY + margin : -(bar.maxY - frame.minY + margin)
        lastDrag = scale * (distance + (distance > 0 ? slop : -slop))
        return .nudge(dy: lastDrag)
    }

    /// The vertical extent between the bars above `frame` and the bars below it, bars `isInFront` says are behind a modal left out: where a drag that nudges it can start and end without beginning on a bar.
    public static func freeSpace(around _: AXNode.Frame, in tree: AXNode, isInFront: (AXNode) -> Bool) -> ClosedRange<Double> {
        let all = bars(in: tree)
        return extent(of: all, in: tree) { isInFront(all[$0]) }
    }

    /// `freeSpace` over bars already read, `inFront` answering for the bar at an index.
    private static func extent(of all: [AXNode], in tree: AXNode, inFront: (Int) -> Bool) -> ClosedRange<Double> {
        let screen = tree.screenBounds
        let (below, above) = all.indices.filter(inFront).map { all[$0] }.reduce(into: ([AXNode](), [AXNode]())) { split, bar in
            if isBelowMiddle(bar, of: tree) {
                split.0.append(bar)
            } else {
                split.1.append(bar)
            }
        }
        let top = above.map(\.frame.maxY).max() ?? screen.minY
        let bottom = below.map(\.frame.minY).min() ?? screen.maxY
        return top ... max(top, bottom)
    }

    /// Whether `bar` sits in the lower half of the screen — a tab bar or a bottom toolbar, which content is moved up to clear — rather than the upper, as a navigation bar does.
    private static func isBelowMiddle(_ bar: AXNode, of tree: AXNode) -> Bool {
        let screen = tree.screenBounds
        return bar.frame.y + bar.frame.height / 2 > screen.y + screen.height / 2
    }

    private static func bars(in tree: AXNode) -> [AXNode] {
        let screen = tree.screenBounds
        return tree.flattened.filter {
            RouteTarget.barTypes.contains($0.type) && $0.frame.hasArea && $0.frame.height < screen.height / 2
        }
    }

    private func reason(_ target: RouteTarget.Candidate, _ bar: AXNode, _ frame: AXNode.Frame, why: String) -> String {
        let covered = Int(bar.frame.verticalOverlap(with: frame).rounded())
        let name = switch bar.type {
        case "TabBar": "tab bar"
        case "Toolbar": "toolbar"
        default: "navigation bar"
        }
        return "\(target.description) is on screen but \(covered) pt of it is under the \(name), and \(why)"
    }
}

public extension ScrollClearance {
    /// The runner's next move.
    enum Move: Equatable, Sendable {
        /// No bar covers the element, or none could be cleared: land.
        case clear
        /// Drag the content by `dy` points, `slop` included, and read again; positive drags it up, negative down.
        case nudge(dy: Double)
        /// Give up; `reason` is what the UNREACHABLE says.
        case stopped(reason: String)
    }
}
