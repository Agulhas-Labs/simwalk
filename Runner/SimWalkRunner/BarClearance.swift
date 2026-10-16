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
                from.press(forDuration: StepPerformer.scrollPress, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
                Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
            case let .stopped(reason):
                return .blocked(reason: reason)
            }
        }
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
            let twins = query.allElementsBoundByIndex.filter { TargetResolution.frame($0.frame, matches: bar.frame) }
            return twins.isEmpty || twins.contains { $0.isHittable }
        }
    }
}
