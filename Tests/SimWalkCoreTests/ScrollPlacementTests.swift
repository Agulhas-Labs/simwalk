//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// `ScrollPlacement`: bringing a `scrollTo`'s element to the top of its container (SimWalk#270).
struct ScrollPlacementTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 400, height: 900)
    private static let container = AXNode.Frame(x: 0, y: 100, width: 400, height: 700)
    private static let navigationBar = AXNode.Frame(x: 0, y: 50, width: 400, height: 100)

    private static func element(y: Double) -> AXNode.Frame {
        AXNode.Frame(x: 20, y: y, width: 360, height: 40)
    }

    /// The design's case: an element at 700 in a container 100 to 800 under a bar ending at 150 has its top put at 166, a move of 534 pt up.
    @Test
    func anElementBelowTheTargetIsDraggedUpByTheDistance() {
        let move = ScrollPlacement.next(element: Self.element(y: 700), container: Self.container, bars: [Self.navigationBar], screen: Self.screen, slop: 0)

        #expect(ScrollPlacement.targetY(container: Self.container, bars: [Self.navigationBar], screen: Self.screen) == 166)
        guard case let .drag(x, fromY, toY) = move else {
            Issue.record("expected a drag, got \(move)")
            return
        }

        #expect(x == 200)
        #expect(fromY - toY == 534)
        #expect((166 ... 784).contains(fromY) && (166 ... 784).contains(toY))
    }

    /// A drag moves nothing until it has travelled the slop, so the drag is that much longer.
    @Test
    func theDragIsLongerByTheSlop() {
        let move = ScrollPlacement.next(element: Self.element(y: 700), container: Self.container, bars: [Self.navigationBar], screen: Self.screen)

        guard case let .drag(_, fromY, toY) = move else {
            Issue.record("expected a drag, got \(move)")
            return
        }

        #expect(fromY - toY == 534 + ScrollPlacement.slop)
    }

    /// A drag longer than the visible height less a margin at each end is clamped to 800 - 150 - 32 = 618.
    @Test
    func aLongDistanceIsClampedToTheVisibleHeight() {
        let move = ScrollPlacement.next(element: Self.element(y: 5000), container: Self.container, bars: [Self.navigationBar], screen: Self.screen)

        guard case let .drag(_, fromY, toY) = move else {
            Issue.record("expected a drag, got \(move)")
            return
        }

        #expect(fromY - toY == 618)
        #expect(fromY == 784 && toY == 166)
    }

    /// An element above the target is dragged down.
    @Test
    func anElementAboveTheTargetIsDraggedDown() {
        let move = ScrollPlacement.next(element: Self.element(y: 120), container: Self.container, bars: [Self.navigationBar], screen: Self.screen, slop: 0)

        guard case let .drag(_, fromY, toY) = move else {
            Issue.record("expected a drag, got \(move)")
            return
        }

        #expect(toY - fromY == 46)
    }

    /// Within 8 pt of the target the step is done, either side of it.
    @Test(arguments: [166.0, 158, 174, 170])
    func anElementWithinEightPointsIsDone(_ y: Double) {
        #expect(ScrollPlacement.next(element: Self.element(y: y), container: Self.container, bars: [Self.navigationBar], screen: Self.screen) == .done)
    }

    /// With no bar the target is 16 below the container's own top, and a container that starts above the screen is clipped to it.
    @Test
    func theTargetIsBelowTheClippedContainerTop() {
        let tall = AXNode.Frame(x: 0, y: -300, width: 400, height: 1200)

        #expect(ScrollPlacement.targetY(container: Self.container, bars: [], screen: Self.screen) == 116)
        #expect(ScrollPlacement.targetY(container: tall, bars: [], screen: Self.screen) == 16)
    }

    /// A bar in the lower half of the screen covers no top.
    @Test
    func aBarInTheLowerHalfDoesNotMoveTheTarget() {
        let tabBar = AXNode.Frame(x: 0, y: 780, width: 400, height: 100)

        #expect(ScrollPlacement.targetY(container: Self.container, bars: [tabBar], screen: Self.screen) == 116)
    }

    /// The container is the nearest scroll-type ancestor of the element, found by the element's live frame.
    @Test
    func theContainerIsTheNearestScrollAncestor() {
        let inner = AXNode(type: "ScrollView", frame: Self.container, children: [
            AXNode(type: "Other", frame: Self.container, children: [AXNode(type: "StaticText", frame: Self.element(y: 700), label: "Heading")]),
        ])
        let outer = AXNode(type: "ScrollView", frame: Self.screen, children: [inner])
        let tree = AXNode(type: "Application", frame: Self.screen, children: [outer])
        let found = AXNode(type: "StaticText", frame: Self.element(y: 701), label: "Heading")

        #expect(ScrollPlacement.containerFrame(of: found, in: tree) == Self.container)
        #expect(ScrollPlacement.containerFrame(of: AXNode(type: "StaticText", frame: Self.element(y: 700), label: "Other"), in: tree) == nil)
    }

    /// Replays `Loop` on a device whose drags move nothing until `trueSlop` has been travelled, returning the element's top at the end and the drags made.
    private static func replay(trueSlop: Double, from start: Double) -> (top: Double, drags: Int) {
        var loop = ScrollPlacement.Loop()
        var top = start
        while case let .drag(_, fromY, toY) = loop.next(element: element(y: top), container: container, bars: [navigationBar], screen: screen) {
            let travelled = abs(toY - fromY)
            let moved = max(0, travelled - trueSlop)
            top += toY < fromY ? -moved : moved
        }
        return (top, loop.drags)
    }

    /// A device whose slop is 30 pt, not the 62 measured once: the first drag overshoots, the loop learns the slop from it, and the correction lands within tolerance.
    @Test
    func aSlopOfThirtyConvergesWithinFourDrags() {
        let result = Self.replay(trueSlop: 30, from: 700)

        #expect(abs(result.top - 166) <= ScrollPlacement.tolerance)
        #expect(result.drags <= 4)
    }

    /// A device whose slop is 100 pt: the second drag moves nothing, the slop doubles once, and the loop then converges.
    @Test
    func aSlopOfOneHundredConvergesWithinFourDrags() {
        let result = Self.replay(trueSlop: 100, from: 700)

        #expect(abs(result.top - 166) <= ScrollPlacement.tolerance)
        #expect(result.drags <= 4)
    }

    /// A list that will not move ends after the doubled try: two drags, the second at twice the slop.
    @Test
    func aListThatWillNotMoveEndsAfterTheDoubledTry() {
        var loop = ScrollPlacement.Loop()
        var drags: [Double] = []
        while case let .drag(_, fromY, toY) = loop.next(element: Self.element(y: 700), container: Self.container, bars: [Self.navigationBar], screen: Self.screen) {
            drags.append(abs(toY - fromY))
        }

        #expect(drags == [596, 618])
        #expect(loop.slop == ScrollPlacement.slop * 2)
    }
}
