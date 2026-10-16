//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The wait after a `tapPoint`'s touch, replayed without a simulator (SimWalk#29 review, item 1; SimWalk#38, item 2).
///
/// Each case names the tree its reads would show; the decision is taken on the clock alone, which is the point — no read of the tree lands the step early (the 2026-09-23 review).
struct TapPointLandingTests {
    /// **The wait itself.** A touch that never moves the hierarchy — a bar selection — lands after one quiet period; landing at touch delivery is the defect SimWalk#29's review fixed, and removing the wait fails this test where it once left every test green (SimWalk#38, item 2).
    @Test
    func atouchThatNeverLeavesTheScreenLandsAfterOneQuietPeriod() {
        #expect(Self.replay([0, 0.25, 0.5, 0.75]) == [.watch, .watch, .landed])
    }

    /// A push that reaches the tree within the quiet period is not landed on as it arrives, but when the quiet period ends, by which time it has been in the tree for a while — the settle window then opens on the screen arrived at.
    @Test
    func apushThatReachesTheTreeWithinTheQuietPeriodLandsWhenItEnds() {
        // list at 0, list at 0.2, detail at 0.4, detail at 0.6
        #expect(Self.replay([0, 0.2, 0.4, 0.6]) == [.watch, .watch, .watch, .landed])
    }

    /// **A spinner that holds is not taken for the push** (the 2026-09-23 review).
    ///
    /// A label that changes at 0.1 s and holds reads the same on two reads running, exactly as an arrived push does; landing on it ran the next step against the screen the push had not yet left.
    @Test
    func aspinnerThatHoldsBeforeThePushDoesNotLandTheStep() {
        // list at 0, "Loading" at 0.1 and 0.2, detail at 0.4 and 0.6
        #expect(Self.replay([0, 0.1, 0.2, 0.4, 0.6]) == [.watch, .watch, .watch, .watch, .landed])
    }

    /// **A change the tree takes back still lands the step** (SimWalk#38, item 4): a callout that appears under the touch and dismisses returns the tree to exactly the screen touched, and the step selected a bar correctly — so it lands when the quiet period ends, and is never held for a destination that was never coming.
    @Test
    func acalloutThatAppearsAndDismissesLandsWhenTheQuietPeriodEnds() {
        // list at 0, callout at 0.2, list at 0.4 and 0.6
        #expect(Self.replay([0, 0.2, 0.4, 0.6, 3]) == [.watch, .watch, .watch, .landed])
    }

    private static let quiet: TimeInterval = 0.5

    /// Asks a landing at each `elapsed` in turn, stopping at the first decision that ends the step.
    private static func replay(_ reads: [TimeInterval]) -> [TapPointLanding.Decision] {
        let landing = TapPointLanding(quiet: quiet)
        var decisions: [TapPointLanding.Decision] = []
        for elapsed in reads {
            let decision = landing.next(elapsed: elapsed)
            decisions.append(decision)
            if decision != .watch {
                break
            }
        }
        return decisions
    }
}
