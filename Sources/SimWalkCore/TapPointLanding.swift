//
// Copyright © Agulhas Labs
//

import Foundation

/// Decides, read by read after a `tapPoint`'s touch, when the step has landed (SimWalk#29 review, item 1).
///
/// **The same defect `tap` was fixed for (SimWalk#6), one step over.** A `tapPoint` that navigates — `tapPoint{label:'Continue', at:[0.5,0.5]}` reaching a push — used to return `.landed` at touch delivery, before the push had happened; the screen it left then held still, so the settle window closed on *it* and filed its capture under the destination's id as `captured`, and the next step in the route could go on to resolve against the wrong screen. So the step waits one quiet period after the touch before it lands. A push slower than that is not waited for (SimWalk#38, item 3).
///
/// **No read of the tree lands it early** (the 2026-09-23 review). `ScreenIdentity` cannot tell a push from a ticking label, a spinner or a callout, since `label` is part of it: landing on the first read that differed took a spinner for a push, and landing on a change seen twice takes a spinner that holds for two reads for one. What the touch did is unknowable from identity alone, so the quiet period is the only rule, and it is unconditional — a callout that appears and dismisses, or a bar that only lights up, lands the step when it runs out, and nothing after the touch refuses (SimWalk#38, item 4). What is left to check is `expect` on the screen it leads to.
///
/// **In the core, not the runner, because nothing in `Runner/` is exercised by `swift test`** (SimWalk#38, item 2): with the wait written there, removing it left every test green. The runner keeps the clock and asks here what to do next, the shape `SettleTracker` set.
public struct TapPointLanding {
    private let quiet: TimeInterval

    /// - Parameter quiet: The walk's quiet period — how long a push is given to reach the tree.
    public init(quiet: TimeInterval) {
        self.quiet = quiet
    }

    /// What the runner should do `elapsed` after the touch.
    public func next(elapsed: TimeInterval) -> Decision {
        elapsed >= quiet ? .landed : .watch
    }
}

public extension TapPointLanding {
    /// The runner's next move.
    enum Decision: Equatable, Sendable {
        /// Wait one interval and read the hierarchy again.
        case watch
        /// The touch has landed: one quiet period has passed since it.
        case landed
    }
}
