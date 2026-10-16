//
// Copyright © Agulhas Labs
//

import Foundation

/// The quiet period a capture is taken under: how finely the runner can measure stillness, and what a request for one actually buys.
///
/// In the core rather than the runner because it is what the *manifest* claims. `settleQuietMilliseconds` is the other half of `axTreeSettled` — "the tree had stopped changing" is a statement about a window — and a number a reader takes at face value has to be arrived at somewhere a test can reach, which nothing in an XCUITest target is.
public struct SettleWindow {
    /// How long the runner leaves between two reads of the hierarchy.
    ///
    /// The unit of measurement, not a preference: stillness is decided by comparing consecutive trees, so no quiet period shorter than this can be observed at all.
    public static let interval: TimeInterval = 0.25

    /// The quiet period actually enforced for a requested one — the request rounded **up** to whole intervals.
    ///
    /// The loop accumulates quiet in whole intervals and proceeds at `>=`, so `--settle 100` is satisfied by the first 250ms read: the capture waited 250, and a manifest restating 100 names a window under which no capture was ever taken. Rounding up records what was enforced. Rounding down, or recording the request verbatim, is the same class of overclaim as `axTreeSettled` on a moving screen — a number stated more precisely, or more leniently, than the thing that produced it.
    public static func enforced(forRequested requested: TimeInterval) -> TimeInterval {
        max(1, (requested / interval).rounded(.up)) * interval
    }

    /// The same value in milliseconds, which is what a manifest carries.
    public static func enforcedMilliseconds(forRequested requested: TimeInterval) -> Int {
        Int((enforced(forRequested: requested) * 1000).rounded())
    }

    /// The quiet period one screen is captured under: the one its walkbook entry states, or the walk's own.
    ///
    /// **Per screen because a global one makes the whole walk pay for the slowest entry.** The only way to capture a real app's Browse tab honestly was `--settle 6000`, which tripled a thirteen-screen walk for the sake of two of them (SimWalk#7). A screen that streams its content in can now say so, and every screen that does not is timed exactly as it was.
    ///
    /// A non-positive request falls back rather than being honoured, matching `--settle`'s own floor — `WalkbookLoader` refuses one at authoring time, so reaching this with a zero means a walkbook that never went through it.
    public static func quiet(forScreenMilliseconds requested: Int?, default fallback: TimeInterval) -> TimeInterval {
        guard let requested, requested > 0 else { return fallback }
        return Double(requested) / 1000
    }

    /// The quiet period a route step waits on before it takes a bar's control (SimWalk#24): that of the screen the step is **taken on**, not the screen the route leads to.
    ///
    /// The screen a step is taken on is the walkbook entry whose route is exactly the steps before it — the entry routed `[tab 'Browse']`, for the second step of `[tab 'Browse', tap 'Heart']` — and its quiet period is the one that entry states, or the walk's own. Where the walkbook names no such screen — a route's first step, taken on whatever the app launched to; a screen passed through on the way; one a `--screen` subset left out — it is the walk's own. Two entries with one route that state different quiet periods give the longer: too short a quiet period is the one that acts early.
    ///
    /// **The destination's is the wrong one.** A screen with `settle: 6000` made every step along its route wait six seconds of stillness before taking a bar's `Edit`, on screens that asked for nothing of the kind. Its quiet period applies from where it is reached — its capture — and to the budget its route's steps are given, which is left as it was: a shorter budget would stop waiting for a row sooner than the runner used to.
    public static func quiet(forStep index: Int, of screen: Walkbook.Screen, in walkbook: Walkbook, default fallback: TimeInterval) -> TimeInterval {
        let before = Array(screen.route.prefix(index))
        let takenOn = walkbook.screens.filter { $0.route == before }
        return takenOn.map { quiet(forScreenMilliseconds: $0.settle, default: fallback) }.max() ?? fallback
    }

    /// How long the runner keeps watching a hierarchy before giving up on it.
    ///
    /// Scaled off the quiet period rather than fixed, since a budget that does not exceed it makes settling impossible; floored at the original 2.5s so the default is unchanged. It is also what a navigating step is given to move the app off the screen it was on — the same question, "how long before the runner stops believing this is going to happen", asked of a push instead of a render.
    public static func budget(forQuiet quiet: TimeInterval) -> TimeInterval {
        max(2.5, quiet * 4)
    }

    /// How long a capture waits for a tree holding only the app's chrome to fill before filing it unsettled (SimWalk#81) — or the screen's budget, where that is longer.
    ///
    /// **A content check with a cap, not a longer timer.** The wait ends the moment content arrives, so a screen that loads costs its load and one that arrived at once costs nothing; only a screen still bare at the cap pays all of it, once per state, and that screen is already a qualification. **15 seconds, from the specimen**: a metric screen on a fresh 12-month seed (1.35M samples) captured a bare spinner at the default settle and the real screen at `--settle 8000`, so it loaded within 8 seconds of the watch starting; 15 is about twice that, for a slower machine or a heavier seed. A screen slower still is captured unsettled and chrome-only — honest, and both lines name it.
    public static let contentWait: TimeInterval = 15

    /// The quiet period above which a screen's own `settle` lengthens the content wait: the watch runs to `max(contentWait, budget)` and the budget is four times the quiet period, so at or below `contentWait / 4` (3.75 s) a larger `settle` adds nothing.
    public static var contentWaitExtendedAboveQuiet: TimeInterval {
        contentWait / 4
    }
}
