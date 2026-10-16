//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import Testing

/// The manifest's `settleQuietMilliseconds` is a claim about what a capture waited for, and the runner recorded the request instead.
struct SettleWindowTests {
    /// `--settle 100` was recorded as 100 over captures that waited 250: the loop accumulates quiet in whole intervals, so a request finer than one buys a whole one.
    @Test(arguments: [
        (requested: 0.1, enforced: 250),
        (requested: 0.25, enforced: 250),
        (requested: 0.251, enforced: 500),
        (requested: 1.0, enforced: 1000),
        (requested: 1.2, enforced: 1250),
    ])
    func aRequestedQuietPeriodIsRecordedAsTheOneTheRunnerCanEnforce(_ window: (requested: Double, enforced: Int)) {
        #expect(SettleWindow.enforcedMilliseconds(forRequested: window.requested) == window.enforced)
    }

    /// Never below one interval: two consecutive identical reads is the shortest stillness that can be observed at all, so nothing can be captured under less.
    @Test
    func nothingIsEverRecordedAsHavingWaitedLessThanOneInterval() {
        #expect(SettleWindow.enforced(forRequested: 0) == SettleWindow.interval)
        #expect(SettleWindow.enforced(forRequested: 0.001) == SettleWindow.interval)
    }

    /// A screen that does not ask for its own quiet period is timed exactly as it always was — the whole point of the per-screen key is that adding it changes nothing for the screens that do not use it.
    @Test
    func aScreenWithoutItsOwnQuietPeriodIsCapturedUnderTheWalks() {
        #expect(SettleWindow.quiet(forScreenMilliseconds: nil, default: 0.25) == 0.25)
        #expect(SettleWindow.quiet(forScreenMilliseconds: nil, default: 6) == 6)
    }

    /// And one that does asks for itself alone, which is what stops a thirteen-screen walk tripling for the sake of two entries.
    @Test
    func aScreensOwnQuietPeriodOverridesTheWalks() {
        #expect(SettleWindow.quiet(forScreenMilliseconds: 6000, default: 0.25) == 6)
        #expect(SettleWindow.quiet(forScreenMilliseconds: 400, default: 6) == 0.4)
    }

    /// A route step waits on the quiet period of the screen it is taken on — the entry whose route is exactly the steps before it — and not the one of the screen its route leads to.
    ///
    /// Before, `settle: 6000` on a destination made every step along its route wait six seconds of stillness before taking a bar's control, on screens that asked for nothing of the kind.
    @Test
    func aRouteStepWaitsOnTheQuietPeriodOfTheScreenItIsTakenOn() {
        let browse = Self.screen("browse", [.tab(label: "Browse")], settle: 3000)
        let heart = Self.screen("heart", [.tab(label: "Browse"), .tap(label: "Heart"), .tap(label: "Resting")], settle: 6000)
        let book = Walkbook(name: "walk", appBundleID: "com.example", screens: [browse, heart])

        #expect(SettleWindow.quiet(forStep: 0, of: heart, in: book, default: 0.25) == 0.25)
        #expect(SettleWindow.quiet(forStep: 1, of: heart, in: book, default: 0.25) == 3)
        #expect(SettleWindow.quiet(forStep: 2, of: heart, in: book, default: 0.25) == 0.25)
    }

    /// A screen the walkbook names without a quiet period of its own is taken on under the walk's; two entries sharing one route give the longer, since too short a quiet period is the one that acts early.
    @Test
    func aStepTakenOnAScreenNamedTwiceWaitsOnTheLongerQuietPeriod() {
        let plain = Self.screen("today", [.tab(label: "Today")], settle: nil)
        let slow = Self.screen("today-lower", [.tab(label: "Today")], settle: 2000)
        let card = Self.screen("workouts", [.tab(label: "Today"), .scrollTo(label: "Workouts")], settle: nil)

        #expect(SettleWindow.quiet(forStep: 1, of: card, in: Self.book([plain, card]), default: 0.5) == 0.5)
        #expect(SettleWindow.quiet(forStep: 1, of: card, in: Self.book([plain, slow, card]), default: 0.5) == 2)
    }

    /// A budget that does not exceed the quiet period makes settling impossible, so it never can — and it keeps the original 2.5s floor, so the default walk is timed as it was.
    @Test
    func aBudgetAlwaysLeavesRoomForTheQuietPeriodItIsWatchingFor() {
        #expect(SettleWindow.budget(forQuiet: 0.25) == 2.5)
        #expect(SettleWindow.budget(forQuiet: 6) == 24)
        for quiet in [0.25, 1.0, 2.5, 6.0, 10.0] {
            #expect(SettleWindow.budget(forQuiet: quiet) > quiet)
        }
    }

    private static func screen(_ id: String, _ route: [Walkbook.RouteStep], settle: Int?) -> Walkbook.Screen {
        Walkbook.Screen(id: id, route: route, states: [Walkbook.CaptureState(theme: .light)], settle: settle)
    }

    private static func book(_ screens: [Walkbook.Screen]) -> Walkbook {
        Walkbook(name: "walk", appBundleID: "com.example", screens: screens)
    }
}
