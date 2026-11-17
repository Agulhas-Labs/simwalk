//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The runner's capture loop, replayed without a simulator — which is the point of it living here at all.
///
/// The decision it makes is whether a screenshot and an accessibility tree may be filed as one capture, and a failed walk was found holding a pushed screen's picture beside the pre-push list's tree (SimWalk#4). Nothing in an XCUITest target is exercised by `swift test`, so the loop that decides it is in the core and the runner keeps only the reads.
struct SettleTrackerTests {
    /// The ordinary path: two identical reads open the window, the picture is taken, and a third read brackets it.
    @Test
    func astillScreenIsPhotographedBetweenTwoIdenticalReads() {
        let replayed = Self.replay(reads: [Self.screen(), Self.screen(), Self.screen()])

        #expect(replayed == [.watch, .takeScreenshot, .settled])
    }

    /// **The halves must be of one hierarchy.** A screen that changed between the picture and the read that follows it has produced a pair of artefacts describing different moments, which is not a capture — the clock restarts rather than the pair being filed with a warning.
    @Test
    func apictureAndAtreeOfDifferentMomentsAreNotAcapture() {
        let replayed = Self.replay(reads: [Self.screen(), Self.screen(), Self.pushedScreen()])

        #expect(replayed == [.watch, .takeScreenshot, .watch])
        #expect(!replayed.contains(.settled))
    }

    /// And the retry that follows it settles on the screen that was actually there, so a transient does not cost the screen.
    @Test
    func aretryAfterAtornPairSettlesOnTheScreenThatWasActuallyThere() {
        let replayed = Self.replay(reads: [
            Self.screen(), Self.screen(), Self.pushedScreen(), Self.pushedScreen(), Self.pushedScreen(),
        ])

        #expect(replayed == [.watch, .takeScreenshot, .watch, .takeScreenshot, .settled])
    }

    /// A screen that never holds still is captured and flagged rather than refused — refusing would make an animated app unwalkable, and a picture of a moving screen is a true fact about it.
    @Test
    func aScreenThatNeverHoldsStillIsCapturedAndFlagged() {
        let replayed = Self.replay(
            reads: [Self.screen(), Self.pushedScreen(), Self.screen(), Self.pushedScreen()],
            budget: 0.5
        )

        #expect(replayed == [.watch, .watch, .unsettled])
        #expect(!replayed.contains(.takeScreenshot))
    }

    /// Any change restarts the quiet period rather than accumulating across it, so a screen alternating between two states can never satisfy a long one without ever having been still.
    @Test
    func alternatingBetweenTwoStatesNeverSatisfiesTheQuietPeriod() {
        let alternating = (0 ..< 12).map { $0.isMultiple(of: 2) ? Self.screen() : Self.pushedScreen() }

        let replayed = Self.replay(reads: alternating, quiet: 0.5, budget: 60)

        #expect(!replayed.contains(.takeScreenshot))
        #expect(replayed.allSatisfy { $0 == .watch })
    }

    /// A screen's own quiet period buys exactly the extra reads it asks for, which is what makes a per-screen `settle` mean anything.
    @Test
    func alongerQuietPeriodWaitsForProportionallyMoreIdenticalReads() {
        let reads = Array(repeating: Self.screen(), count: 6)

        #expect(Self.replay(reads: reads, quiet: 0.25) == [.watch, .takeScreenshot, .settled])
        #expect(Self.replay(reads: reads, quiet: 0.75) == [.watch, .watch, .watch, .takeScreenshot, .settled])
    }

    /// Without a content wait a chrome-only tree settles as any still tree does: a read that waits before a step files nothing, and must not stall on a screen that is legitimately empty — only a capture waits for content (SimWalk#81).
    @Test
    func aplainReadStillSettlesOnAchromeOnlyTree() {
        let bare = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), label: "App")

        #expect(Self.replay(reads: [bare, bare, bare]) == [.watch, .takeScreenshot, .settled])
    }

    /// The cap is `SettleWindow.contentWait`, 15 s: a bare screen is watched that long and not a second less, so shortening it fails here (SimWalk#81).
    @Test
    func aBareTreeIsWatchedForTheWholeContentWaitAndNoLonger() {
        let last = Self.bareWatch(quiet: 0.25, budget: 2.5)

        #expect(last.elapsed >= SettleWindow.contentWait)
        #expect(last.elapsed < SettleWindow.contentWait + 1)
        #expect(last.decision == .unsettled)
    }

    /// A budget larger than the cap extends the watch: the deadline is `max(contentWait, budget)`, so a screen whose own `settle` makes the budget 20 s is watched 20 s, and capping it at the content wait fails here (SimWalk#81).
    @Test
    func aBudgetLargerThanTheContentWaitExtendsTheWatchOfABareTree() {
        let budget = SettleWindow.budget(forQuiet: 5)
        #expect(budget > SettleWindow.contentWait)

        let last = Self.bareWatch(quiet: 5, budget: budget)

        #expect(last.elapsed >= budget)
        #expect(last.elapsed < budget + 1)
        #expect(last.decision == .unsettled)
    }

    /// **The settle time is the last read that differed from the one before it** (SimWalk#67): a screen that changed once, at the second read, settled there, however many identical reads it then took to prove it.
    @Test
    func theSettleTimeIsTheElapsedOfTheLastReadThatDiffered() {
        let watched = Self.watch(reads: [Self.pushedScreen(), Self.screen(), Self.screen(), Self.screen()])

        #expect(watched.decisions == [.watch, .watch, .takeScreenshot, .settled])
        #expect(watched.tracker.settleTime == 0.25)
        #expect(watched.tracker.reads == 4)
    }

    /// The read that brackets the picture is a read like any other: a torn pair's second half is where the screen changed, so the settle time is the moment it was seen, not the earlier still screen the picture was taken of.
    @Test
    func aTornPairsBracketingReadIsWhereTheScreenSettled() {
        let watched = Self.watch(reads: [Self.screen(), Self.screen(), Self.pushedScreen(), Self.pushedScreen(), Self.pushedScreen()])

        #expect(watched.decisions == [.watch, .takeScreenshot, .watch, .takeScreenshot, .settled])
        #expect(watched.tracker.settleTime == 0.25)
        #expect(watched.tracker.reads == 5)
    }

    /// **A screen still from the first read settled at the first read**, not at zero: the watch opened some way after the step landed, and the first read is the earliest moment it can vouch for.
    @Test
    func aScreenThatNeverChangedSettledAtTheFirstRead() {
        let watched = Self.watch(reads: [Self.screen(), Self.screen(), Self.screen()], from: 0.1)

        #expect(watched.decisions == [.watch, .takeScreenshot, .settled])
        #expect(watched.tracker.settleTime == 0.1)
        #expect(watched.tracker.reads == 3)
    }

    /// **An unsettled watch has no settle time**, only its reads: the last change before the budget ran out is not a moment the screen settled, and filing it as one would read as a measurement of a screen that was never still.
    @Test
    func anUnsettledWatchHasNoSettleTime() {
        let watched = Self.watch(reads: [Self.screen(), Self.pushedScreen(), Self.screen(), Self.pushedScreen()], budget: 0.5)

        #expect(watched.decisions == [.watch, .watch, .unsettled])
        #expect(watched.tracker.settleTime == nil)
        #expect(watched.tracker.reads == 3)
    }

    /// Nor has a watch still in progress: until the bracketing read matches, nothing has settled.
    @Test
    func aWatchStillInProgressHasNoSettleTime() {
        let watched = Self.watch(reads: [Self.screen(), Self.screen()])

        #expect(watched.decisions == [.watch, .takeScreenshot])
        #expect(watched.tracker.settleTime == nil)
        #expect(watched.tracker.reads == 2)
    }

    /// **A pulse is not motion** (SimWalk#252): a SwiftUI element scaled 6% on every read is the same screen read again, so the quiet period passes and the picture's bracketing read, a pulse apart from the tree it photographed, still holds.
    @Test
    func aScreenPulsingWithinEightPercentSettlesAfterTheQuietPeriod() {
        let reads = (0 ..< 12).map { Self.pulsing(large: $0.isMultiple(of: 2)) }

        let replayed = Self.replay(reads: reads, quiet: 0.75)

        #expect(replayed == [.watch, .watch, .watch, .takeScreenshot, .settled])
    }

    /// The anchor is the start of the quiet run, not the read before: a button creeping two points a read is steady against its neighbour every time, yet leaves the allowance within a few reads, so a long quiet period never accrues until the creep stops.
    @Test
    func aScreenCreepingAcrossManyReadsDoesNotSettleUntilItStops() {
        let creeping = (0 ..< 20).map { Self.pulsing(large: false, x: Double($0) * 2) }
        let stopped = Array(repeating: Self.pulsing(large: false, x: 40), count: 12)

        let whileCreeping = Self.replay(reads: creeping, quiet: 2, budget: 60)
        let afterwards = Self.replay(reads: creeping + stopped, quiet: 2, budget: 60)

        #expect(whileCreeping.allSatisfy { $0 == .watch })
        #expect(afterwards.last == .settled)
        #expect(afterwards.count > creeping.count + 8)
    }

    /// A label that changes is a different screen however much of it is steady, so the quiet period restarts.
    @Test
    func aLabelChangeOnAPulsingScreenRestartsTheQuietPeriod() {
        let reads = [
            Self.pulsing(large: false), Self.pulsing(large: true), Self.pulsing(large: false, label: "Go!"),
            Self.pulsing(large: true, label: "Go!"), Self.pulsing(large: false, label: "Go!"),
        ]

        #expect(Self.replay(reads: reads, quiet: 0.5) == [.watch, .watch, .watch, .watch, .takeScreenshot])
    }

    /// The settle time of a pulsing screen is when its content arrived, not the last pulse.
    @Test
    func theSettleTimeOfAPulsingScreenIsWhenItsContentArrived() {
        let reads = [Self.pushedScreen()] + (0 ..< 8).map { Self.pulsing(large: $0.isMultiple(of: 2)) }

        let watched = Self.watch(reads: reads, quiet: 0.5)

        #expect(watched.decisions.last == .settled)
        #expect(watched.tracker.settleTime == 0.25)
    }

    /// **The settle time of a creep is when it stopped**: a button creeping two points a read is a steady shift of the read before every time, so against the last read nothing ever changed and the settle time was the first read.
    ///
    /// Held against the last change instead, the creep keeps changing until it stops.
    @Test
    func theSettleTimeOfACreepIsWhenItStopped() throws {
        let creeping = (0 ..< 20).map { Self.pulsing(large: false, x: Double($0) * 2) }
        let stopped = Array(repeating: Self.pulsing(large: false, x: 40), count: 12)

        let watched = Self.watch(reads: creeping + stopped, quiet: 2, budget: 60)
        let settleTime = try #require(watched.tracker.settleTime)

        #expect(watched.decisions.last == .settled)
        #expect(settleTime >= 4.5)
        #expect(settleTime <= 5)
    }

    /// A title above a labelled spinner, or the same screen with the spinner gone.
    private static func loadingScreen(spinning: Bool) -> AXNode {
        let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let title = AXNode(type: "StaticText", frame: frame, label: "Another way to see it")
        let spinner = AXNode(type: "ActivityIndicator", frame: frame, label: "Loading the answer…", value: "1")
        return AXNode(type: "Application", frame: frame, label: "App", children: spinning ? [title, spinner] : [title])
    }

    /// **A spinner beside content is waited on, not settled on** (SimWalk#267): no quiet accrues however still it holds, so it is never photographed, and the screen settles once the spinner goes.
    @Test
    func aTreeShowingASpinnerAccruesNoQuietUntilItGoes() {
        var tracker = SettleTracker(quiet: 0.25, budget: 2.5, interval: 0.25, contentWait: SettleWindow.contentWait)
        var elapsed: TimeInterval = 0
        for _ in 0 ..< 20 {
            #expect(tracker.next(tree: Self.loadingScreen(spinning: true), elapsed: elapsed) == .watch)
            elapsed += 0.25
        }

        #expect(tracker.next(tree: Self.loadingScreen(spinning: false), elapsed: elapsed) == .watch)
        #expect(tracker.next(tree: Self.loadingScreen(spinning: false), elapsed: elapsed + 0.25) == .takeScreenshot)
        #expect(tracker.next(tree: Self.loadingScreen(spinning: false), elapsed: elapsed + 0.25) == .settled)
    }

    /// The settle budget runs from when the spinner went, so a screen that stops spinning past the budget still gets all of it.
    @Test
    func theBudgetRunsFromWhenTheSpinnerWent() {
        var tracker = SettleTracker(quiet: 2, budget: 2.5, interval: 0.25, contentWait: SettleWindow.contentWait)
        for read in 0 ..< 40 {
            #expect(tracker.next(tree: Self.loadingScreen(spinning: true), elapsed: Double(read) * 0.25) == .watch)
        }

        // Ten seconds in: past the budget, inside the content wait. Quiet needs 2 s, so a watch on the old clock would give up.
        var decision = tracker.next(tree: Self.loadingScreen(spinning: false), elapsed: 10)
        var elapsed: TimeInterval = 10
        while decision == .watch, elapsed < 12.4 {
            elapsed += 0.25
            decision = tracker.next(tree: Self.loadingScreen(spinning: false), elapsed: elapsed)
        }

        #expect(decision == .takeScreenshot)
    }

    /// A spinner that never goes is given up on at the content wait, not before.
    @Test
    func aSpinnerThatNeverGoesIsUnsettledAtTheContentWait() {
        var tracker = SettleTracker(quiet: 0.25, budget: 2.5, interval: 0.25, contentWait: SettleWindow.contentWait)
        var elapsed: TimeInterval = 0
        var decision = tracker.next(tree: Self.loadingScreen(spinning: true), elapsed: elapsed)
        while decision == .watch, elapsed < 60 {
            elapsed += 0.25
            decision = tracker.next(tree: Self.loadingScreen(spinning: true), elapsed: elapsed)
        }

        #expect(decision == .unsettled)
        #expect(elapsed == SettleWindow.contentWait)
    }

    /// Reads a bare tree on the runner's cadence until the tracker gives up on it, returning when and what it decided.
    private static func bareWatch(quiet: TimeInterval, budget: TimeInterval) -> (elapsed: TimeInterval, decision: SettleTracker.Decision) {
        let bare = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), label: "App")
        var tracker = SettleTracker(quiet: quiet, budget: budget, interval: 0.25, contentWait: SettleWindow.contentWait)
        var elapsed: TimeInterval = 0
        for _ in 0 ..< 1000 {
            let decision = tracker.next(tree: bare, elapsed: elapsed)
            if decision != .watch {
                return (elapsed, decision)
            }
            elapsed += 0.25
        }
        return (elapsed, .watch)
    }

    /// Replays a scripted sequence of hierarchy reads exactly as the runner drives it: a wait before every read but the one that brackets the picture, which is taken immediately.
    private static func replay(
        reads: [AXNode],
        quiet: TimeInterval = SettleWindow.interval,
        budget: TimeInterval = 2.5,
        interval: TimeInterval = SettleWindow.interval
    ) -> [SettleTracker.Decision] {
        watch(reads: reads, quiet: quiet, budget: budget, interval: interval).decisions
    }

    /// `replay`, keeping the tracker for the figures it reports, with the first read `start` into the watch.
    private static func watch(
        reads: [AXNode],
        from start: TimeInterval = 0,
        quiet: TimeInterval = SettleWindow.interval,
        budget: TimeInterval = 2.5,
        interval: TimeInterval = SettleWindow.interval
    ) -> (decisions: [SettleTracker.Decision], tracker: SettleTracker) {
        var tracker = SettleTracker(quiet: quiet, budget: budget, interval: interval)
        var decisions: [SettleTracker.Decision] = []
        var elapsed = start
        for tree in reads {
            let decision = tracker.next(tree: tree, elapsed: elapsed)
            decisions.append(decision)
            switch decision {
            case .watch:
                elapsed += interval
            case .takeScreenshot:
                // The bracketing read follows without waiting — that is what makes it a bracket.
                break
            case .settled, .unsettled:
                return (decisions, tracker)
            }
        }
        return (decisions, tracker)
    }

    private static func screen() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [AXNode(type: "Cell", frame: AXNode.Frame(x: 14, y: 120, width: 374, height: 55), label: "Rowing, 12 August")]
        )
    }

    /// A screen with one button an endless animation scales: 100 points square, or 106 when `large`, optionally moved to `x`.
    private static func pulsing(large: Bool, x: Double = 100, label: String = "Go") -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [AXNode(type: "Button", frame: AXNode.Frame(x: x, y: 400, width: large ? 106 : 100, height: large ? 106 : 100), label: label)]
        )
    }

    private static func pushedScreen() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 200, height: 30), label: "Split")]
        )
    }
}
