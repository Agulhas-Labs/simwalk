//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// `ScrollClearance`: a `scrollTo` that reached its element nudges it out from under a bar, or refuses (SimWalk#108).
struct ScrollClearanceTests {
    /// **The fixture's shape**: `Partly covered row` at 130,787 is hittable with the floating tab bar at y 791 over its lower half; a nudge of its bottom edge past the bar's top plus the margin clears it, dragged that far plus the slop before the content follows.
    @Test
    func anElementUnderTheTabBarIsNudgedUpUntilItClears() throws {
        var clearance = ScrollClearance()
        let covered = Self.screen(row: Self.frame(y: 787))
        let target = try #require(Self.target(in: covered))

        #expect(clearance.next(target: target, frame: Self.frame(y: 787), in: covered, isInFront: Self.always) == .nudge(dy: 32 + 62))
        #expect(clearance.next(target: target, frame: Self.frame(y: 755), in: Self.screen(row: Self.frame(y: 755)), isInFront: Self.always) == .clear)
        #expect(clearance.nudges == 1)
    }

    /// The `Toolbar` every capture holds, framed at the whole screen, is a container: an element inside it is under no bar.
    @Test
    func theFullScreenToolbarAloneNeverCounts() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 400), bars: [])
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: Self.frame(y: 400), in: tree, isInFront: Self.always) == .clear)
    }

    /// An element clear of every bar is landed on as it always was.
    @Test
    func anElementClearOfEveryBarIsClear() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 400))
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: Self.frame(y: 400), in: tree, isInFront: Self.always) == .clear)
    }

    /// A bar above the element, the navigation bar a list scrolled under, drags the content down: a negative `dy`.
    @Test
    func anElementUnderTheNavigationBarIsNudgedDown() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 150))
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: Self.frame(y: 150), in: tree, isInFront: Self.always) == .nudge(dy: -(168.0 - 150 + 16 + 62)))
    }

    /// An element taller than the room between the bars can never clear them: it is accepted rather than nudged for ever.
    @Test
    func anElementTallerThanTheFreeSpaceIsClear() throws {
        var clearance = ScrollClearance()
        let tall = AXNode.Frame(x: 0, y: 100, width: 402, height: 800)
        let tree = Self.screen(row: tall)
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: tall, in: tree, isInFront: Self.always) == .clear)
    }

    /// A nudge after which the screen reads exactly as before is retried once at twice its drag, since the slop may be larger than measured; the read after that, unchanged too, is the end of the list, and the reason names the bar (the #108 review).
    @Test
    func aNudgeThatMovesNothingIsRetriedAtTwiceItsDragThenStops() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 787))
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: Self.frame(y: 787), in: tree, isInFront: Self.always) == .nudge(dy: 32 + 62))
        #expect(clearance.next(target: target, frame: Self.frame(y: 787), in: tree, isInFront: Self.always) == .nudge(dy: 2.0 * (32 + 62)))
        #expect(clearance.next(target: target, frame: Self.frame(y: 787), in: tree, isInFront: Self.always) == .stopped(
            reason: "a StaticText labelled 'Partly covered row' is on screen but 16 pt of it is under the tab bar, and a nudge at twice its drag moved nothing — the list is at its end, or nothing here scrolls"
        ))
        #expect(clearance.nudges == 1)
    }

    /// A retry that moved the content goes on as a nudge did: the step retries once, and a later nudge that moves nothing is the end.
    @Test
    func aRetryThatMovedKeepsTheDoubledDragAndOnlyADoubledNoMoveStops() throws {
        var clearance = ScrollClearance()
        let target = try #require(Self.target(in: Self.screen(row: Self.frame(y: 787))))
        let stuck = Self.screen(row: Self.frame(y: 787))
        let moved = Self.screen(row: Self.frame(y: 785))

        #expect(clearance.next(target: target, frame: Self.frame(y: 787), in: stuck, isInFront: Self.always) == .nudge(dy: 32 + 62))
        #expect(clearance.next(target: target, frame: Self.frame(y: 787), in: stuck, isInFront: Self.always) == .nudge(dy: 2.0 * (32 + 62)))
        #expect(clearance.next(target: target, frame: Self.frame(y: 785), in: moved, isInFront: Self.always) == .nudge(dy: 2.0 * (30 + 62)))
        guard case let .stopped(reason) = clearance.next(target: target, frame: Self.frame(y: 785), in: moved, isInFront: Self.always) else {
            Issue.record("expected a stop once a doubled drag moved nothing")
            return
        }
        #expect(reason.contains("at twice its drag moved nothing"))
    }

    /// **The review's probe**: a row lying wholly inside the tab bar's band, its top below the bar's, is covered from below — the bar's centre is below the row's — so the content moves up, not down and deeper under the bar.
    @Test
    func aRowInsideTheTabBarsBandIsNudgedUp() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 800))
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: Self.frame(y: 800), in: tree, isInFront: Self.always) == .nudge(dy: 820.0 - 791 + 16 + 62))
    }

    /// **The second review's probe**: a row in the lower half of the tab bar's band, its centre below the bar's, is still covered from below — the bar is in the lower half of the screen — so the content moves up, never down and off the screen.
    @Test
    func aRowInTheLowerHalfOfTheTabBarsBandIsNudgedUp() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 830))
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: Self.frame(y: 830), in: tree, isInFront: Self.always) == .nudge(dy: 850.0 - 791 + 16 + 62))
    }

    /// The mirror at the top: a row whose centre is above the navigation bar's is still under a bar in the upper half, so the content moves down, never up into the status bar.
    @Test
    func aRowInTheUpperHalfOfTheNavigationBarsBandIsNudgedDown() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 70))
        let target = try #require(Self.target(in: tree))

        #expect(clearance.next(target: target, frame: Self.frame(y: 70), in: tree, isInFront: Self.always) == .nudge(dy: -(168.0 - 70 + 16 + 62)))
    }

    /// A tab bar a modal is drawn over (SimWalk#95) is in the tree but not in front: a row beneath it is under nothing.
    @Test
    func aBarNotInFrontDoesNotCount() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 820))
        let target = try #require(Self.target(in: tree))
        var asked: [String] = []

        let move = clearance.next(target: target, frame: Self.frame(y: 820), in: tree) { bar in
            asked.append(bar.type)
            return false
        }

        #expect(move == .clear)
        #expect(asked == ["TabBar"])
    }

    /// A bar behind a modal does not narrow the room a drag has, nor make an element taller than it (SimWalk#119).
    @Test
    func aBarNotInFrontDoesNotNarrowTheFreeSpace() throws {
        let tall = AXNode.Frame(x: 0, y: 100, width: 402, height: 800)
        let tree = Self.screen(row: tall)
        let hidden = { (_: AXNode) in false }

        #expect(ScrollClearance.freeSpace(around: tall, in: tree, isInFront: Self.always) == 168 ... 791)
        #expect(ScrollClearance.freeSpace(around: tall, in: tree, isInFront: hidden) == 0 ... 874)
        var clearance = ScrollClearance()
        let target = try #require(Self.target(in: tree))
        #expect(clearance.next(target: target, frame: tall, in: tree, isInFront: hidden) == .clear)
    }

    /// `next` hands its `isInFront` to `freeSpace`: an element too tall for the room between both bars, but not for the room once the hidden navigation bar is ignored, is nudged out from under the tab bar in front rather than accepted.
    @Test
    func nextPassesIsInFrontToTheFreeSpace() throws {
        let tall = AXNode.Frame(x: 0, y: 150, width: 402, height: 700)
        let tree = Self.screen(row: tall)
        let tabBarOnly = { (bar: AXNode) in bar.type == "TabBar" }
        let target = try #require(Self.target(in: tree))
        var everything = ScrollClearance()
        var behindNavigation = ScrollClearance()

        #expect(everything.next(target: target, frame: tall, in: tree, isInFront: Self.always) == .clear)
        guard case .nudge = behindNavigation.next(target: target, frame: tall, in: tree, isInFront: tabBarOnly) else {
            Issue.record("expected a nudge")
            return
        }
    }

    /// A nudge asks each bar once and hands back the room it measured, so the runner repeats neither (SimWalk#122).
    @Test
    func aNudgeAsksEachBarOnceAndReturnsItsRoom() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 787))
        let target = try #require(Self.target(in: tree))
        var asked = [String]()

        let move = clearance.next(target: target, frame: Self.frame(y: 787), in: tree) { bar in
            asked.append("\(bar.type)@\(bar.frame.y)")
            return true
        }

        guard case .nudge = move else {
            Issue.record("expected a nudge")
            return
        }

        #expect(!asked.isEmpty)
        #expect(asked.count == Set(asked).count)
        #expect(clearance.room == ScrollClearance.freeSpace(around: Self.frame(y: 787), in: tree, isInFront: Self.always))
    }

    /// A read with no bar overlapping the element asks the runner nothing, so it costs no live query.
    @Test
    func aClearReadAsksNothing() throws {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 400))
        let target = try #require(Self.target(in: tree))
        var asked = 0

        let move = clearance.next(target: target, frame: Self.frame(y: 400), in: tree) { _ in
            asked += 1
            return true
        }

        #expect(move == .clear)
        #expect(asked == 0)
    }

    /// **The review's probe**: a `scrollTo` whose only match is a tab item lands on it without scrolling, as the Reference promises — no scroll moves it out from under its own bar.
    @Test
    func aTargetInsideABarIsClear() {
        var clearance = ScrollClearance()
        let item = AXNode(type: "Button", frame: AXNode.Frame(x: 100, y: 800, width: 80, height: 49), label: "Workouts")
        let tabBar = AXNode(type: "TabBar", frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83), label: "Tab Bar", children: [item])
        let tree = Self.screen(row: Self.frame(y: 400), bars: [tabBar])
        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Workouts", in: tree, reaching: .anything) else {
            Issue.record("expected the tab item")
            return
        }

        #expect(target.insideBar == "TabBar")
        #expect(clearance.next(target: target, frame: item.frame, in: tree, isInFront: Self.always) == .clear)
    }

    /// A match on a bar itself — the navigation bar carrying the screen's title — is the bar, which nothing covers.
    @Test
    func aTargetThatIsABarIsClear() {
        var clearance = ScrollClearance()
        let tree = Self.screen(row: Self.frame(y: 400))
        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Rows", in: tree, reaching: .anything) else {
            Issue.record("expected the navigation bar")
            return
        }

        #expect(target.node.type == "NavigationBar")
        #expect(clearance.next(target: target, frame: target.node.frame, in: tree, isInFront: Self.always) == .clear)
    }

    /// The nudges a step gets, all taken with the element still covered, end in a refusal that says how many.
    @Test
    func theNudgesRunOutWhileStillCovered() throws {
        var clearance = ScrollClearance(limit: 2)
        let target = try #require(Self.target(in: Self.screen(row: Self.frame(y: 787))))
        let moves = [787.0, 783, 779].map { y in
            clearance.next(target: target, frame: Self.frame(y: y), in: Self.screen(row: Self.frame(y: y)), isInFront: Self.always)
        }

        #expect(moves[0] == .nudge(dy: 32 + 62))
        #expect(moves[1] == .nudge(dy: 28 + 62))
        guard case let .stopped(reason) = moves[2] else {
            Issue.record("expected a stop, got \(moves[2])")
            return
        }
        #expect(reason.contains("still covered after 2 nudges"))
        #expect(reason.contains("tab bar"))
    }

    /// Every bar in front, as on a screen no modal covers.
    private static func always(_: AXNode) -> Bool {
        true
    }

    private static func frame(y: Double) -> AXNode.Frame {
        AXNode.Frame(x: 130, y: y, width: 141, height: 20)
    }

    /// The fixture's iPhone tree: a full-screen `Toolbar`, a navigation bar and a floating tab bar, with `row` among them.
    private static func screen(row: AXNode.Frame, bars: [AXNode]? = nil) -> AXNode {
        let chrome = bars ?? [
            AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 62, width: 402, height: 106), label: "Rows"),
            AXNode(type: "TabBar", frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83), label: "Tab Bar"),
        ]
        let toolbar = AXNode(type: "Toolbar", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874))
        let text = AXNode(type: "StaticText", frame: row, label: "Partly covered row")
        return AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [toolbar, text] + chrome)
    }

    private static func target(in tree: AXNode) -> RouteTarget.Candidate? {
        guard case let .chosen(candidate, _) = RouteTarget.choose(labelled: "Partly covered row", in: tree, reaching: .anything) else { return nil }
        return candidate
    }
}
