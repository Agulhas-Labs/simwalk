//
// Copyright © Agulhas Labs
//

import SimWalkCore
import UIKit
import XCTest

/// The bar-clearance half of a `tap` or `scrollTo`: nudging the content until no bar in front of the element covers it (SimWalk#108), split from `StepPerformer` for its size (SimWalk#119).
@MainActor
struct BarClearance {
    /// Lands on `element` once no tab bar, toolbar or navigation bar in front of it covers it, nudging the content until none does (SimWalk#108); a `scrollTo` always, a `tap` whose seek swiped (SimWalk#104).
    ///
    /// `ScrollClearance` decides each move from the tree and the element's live frame; this keeps the reads and the drags. A bar counts only where it is hittable live, bound among its type's bars by the frame the tree read; one that cannot be bound counts. A nudge is one slow press-and-drag of `dy` points, held at its end to stop a fling, from the middle of the space between the bars, clamped to that space, at the element's own x — on iPad the screen's centre can be another column of a split view. The snapshot's frame is from before the swipes (SimWalk#93 review), so the node lands with the frame the element has now.
    static func clearOfBars(_ element: XCUIElement, as target: RouteTarget.Candidate, in app: XCUIApplication) throws -> StepPerformer.StepResult {
        var clearance = ScrollClearance()
        var node = target.node
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let bounds = app.frame
        while true {
            if let live = StepPerformer.liveRead(or: nil, { Optional(element.frame) }) {
                node.frame = AXNode.Frame(x: Double(live.minX), y: Double(live.minY), width: Double(live.width), height: Double(live.height))
            }
            let tree = try AXTreeCapture.tree(of: app)
            switch clearance.next(target: target, frame: node.frame, in: tree, isInFront: { isInFront($0, in: app) }) {
            case .clear:
                return .landedOn(node)
            case let .nudge(dy):
                let space = clearance.room
                let middle = (space.lowerBound + space.upperBound) / 2
                let end = min(max(middle - dy, space.lowerBound), space.upperBound)
                let x = min(max(node.frame.x + node.frame.width / 2, bounds.minX + 8), bounds.maxX - 8) - bounds.origin.x
                let from = origin.withOffset(CGVector(dx: x, dy: middle - bounds.origin.y))
                let to = origin.withOffset(CGVector(dx: x, dy: end - bounds.origin.y))
                // Made once more when XCTest timed out synthesizing it, and refused when it did twice (SimWalk#274).
                guard StepPerformer.GestureSynthesis.withRetry({ from.press(forDuration: StepPerformer.scrollPress, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3) }) else {
                    return .blocked(reason: SynthesisTimeout.refusal(.scroll, on: nil))
                }
                Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
            case let .stopped(reason):
                return .blocked(reason: reason)
            }
        }
    }

    /// Drags the content until `element`'s top edge rests just below the top of its scroll container, after it has landed clear of the bars (`scrollTo` with `position: "top"`, SimWalk#270).
    ///
    /// `ScrollPlacement` decides each drag from the element's live frame, its container's frame in a fresh tree and the bars in front of the container's top; this keeps the reads and the drags: at most `ScrollPlacement.maxDrags`, each slow and held at its end, along the container's middle, in `ScrollPlacement.Loop`, which adapts the slop to what each drag measured and ends at the end of the list, where the step still lands. The element is where the list left it then, and the step says nothing of that: a landed step carries no note. Last, `clearOfBars` runs again so the element is never left under a bar.
    static func placeAtTop(_ element: XCUIElement, as target: RouteTarget.Candidate, in app: XCUIApplication) throws -> StepPerformer.StepResult {
        var node = target.node
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let bounds = app.frame
        let screen = AXNode.Frame(x: Double(bounds.minX), y: Double(bounds.minY), width: Double(bounds.width), height: Double(bounds.height))
        func readFrame() {
            if let live = StepPerformer.liveRead(or: nil, { Optional(element.frame) }) {
                node.frame = AXNode.Frame(x: Double(live.minX), y: Double(live.minY), width: Double(live.width), height: Double(live.height))
            }
        }
        var loop = ScrollPlacement.Loop()
        while true {
            readFrame()
            let tree = try AXTreeCapture.tree(of: app)
            let container = ScrollPlacement.containerFrame(of: node, in: tree) ?? screen
            let bars = ScrollPlacement.bars(in: tree).filter { isInFront($0, in: app) }.map(\.frame)
            guard case let .drag(x, fromY, toY) = loop.next(element: node.frame, container: container, bars: bars, screen: screen) else {
                break
            }
            let from = origin.withOffset(CGVector(dx: x - bounds.origin.x, dy: fromY - bounds.origin.y))
            let to = origin.withOffset(CGVector(dx: x - bounds.origin.x, dy: toY - bounds.origin.y))
            from.press(forDuration: StepPerformer.scrollPress, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
        }
        // The last drag may have left the element under a bar (the #108 failure), so it is cleared again before the step lands.
        return try clearOfBars(element, as: target, in: app)
    }

    /// Whether `bar` is drawn in front of what it overlaps: hittable live, a modal over it having made it not (SimWalk#95, the #108 review).
    ///
    /// Twin bars at one frame (a cover's over the one behind it) count as in front when any is hittable. `isHittable` tests one hit point, so a tab bar split into pills may read not-hittable at its centre (unverified, SimWalk#119).
    private static func isInFront(_ bar: AXNode, in app: XCUIApplication) -> Bool {
        let query = switch bar.type {
        case "TabBar": app.tabBars
        case "Toolbar": app.toolbars
        default: app.navigationBars
        }
        return StepPerformer.liveRead(or: true) {
            let twins = query.allElementsBoundByIndex.filter { TargetResolution.frame($0.frame, exactlyMatches: bar.frame) }
            return twins.isEmpty || twins.contains { $0.isHittable }
        }
    }
}
