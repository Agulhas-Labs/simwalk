//
// Copyright © Agulhas Labs
//

import Foundation

/// A live session's `step`: the guard, the per-step setup a walk gives a route step, and the answer — decided here so `swift test` checks it, with the runner handing in only the reads and the step itself.
///
/// **A stale guard is refused before anything acts.** The screen is read once, hashed (``ScreenHash``), and compared with the request's `guard`; a mismatch answers `snapshotChanged` with both hashes, and neither the sheet baseline nor the step is touched. That read is also the delta's *before*, so an unguarded step costs the same one read. **After the step the screen is watched until it holds still** (``SettleTracker``), then read as a `session read` reads it.
///
/// **The step is taken as a walk takes it** (`WalkRunner.follow`): the sheet scope a `systemTap` answers from comes from one ``SystemSheetBaseline`` kept for the whole session and told of every landed step, under the session's quiet period. A walk knows its route and reads a baseline only while a `systemTap` is still to come; a session does not know what the agent will send next, so it reads one before every step that is not a `systemTap` — the price of one tree read, the same as a baseline made without a route (``SystemSheetBaseline/init()``).
///
/// **What a landed step reports is what a walk records** — `landedAs`'s step, a `systemTap` with its owner, not the step as sent — because that is what the route so far is made of (``LiveSessionChannel/route()``) and what a saved walkbook replays.
public struct LiveSessionStepper: Sendable {
    /// The quiet period every step is taken under: the session's own, since no walkbook entry names the screen a live step is taken on.
    public let quiet: TimeInterval
    private var baseline = SystemSheetBaseline()

    public init(quiet: TimeInterval) {
        self.quiet = quiet
    }

    /// How long a step is given to land: a walk's budget for the same quiet period.
    public var budget: TimeInterval {
        SettleWindow.budget(forQuiet: quiet)
    }

    /// Answers one `step` request.
    ///
    /// - Parameters:
    ///   - screen: the app's tree as it stands — the read a `session read` hashes — read before the step, and watched after it until it holds still.
    ///   - sheetReads: what a `systemTap`'s baseline reads, the same source the step then reads its sheet from.
    ///   - perform: takes the step against the scope a `systemTap` answers from (`nil` for any other step).
    ///   - read: the screen after the step, as a `session read` reads it.
    public mutating func answer(
        _ request: LiveSessionRequest,
        screen: some TreeSource,
        sheetReads: some TreeSource,
        perform: (Walkbook.RouteStep, SystemSheetScope?) throws -> Performed,
        read: () throws -> LiveScreen
    ) throws -> LiveSessionResponse {
        guard let step = request.step else {
            throw Failure(description: "step request \(request.n) names no step: send {\"n\": …, \"action\": \"step\", \"step\": <a walkbook route step>}")
        }
        let before = try screen.appTree()
        let found = ScreenHash.of(before)
        if let expected = request.guardHash, expected != found {
            return LiveSessionResponse(n: request.n, action: .step, step: .snapshotChanged(expected: expected, found: found))
        }
        let scope = try baseline.scope(for: step, from: sheetReads, quiet: quiet)
        let performed = try perform(step, scope)
        try settle(screen)
        let after = try read()
        // An app that is gone after the step has lost every element it showed.
        let delta = ScreenDelta(from: before, to: after.tree ?? AXNode(type: before.type, frame: before.frame))
        switch performed {
        case let .landed(recorded, sheetClosed, bound):
            baseline.landed(recorded, sheetClosed: sheetClosed)
            return LiveSessionResponse(n: request.n, action: .step, screen: after, step: .landed(recorded, bound: bound, delta: delta))
        case let .blocked(reason):
            return LiveSessionResponse(n: request.n, action: .step, screen: after, step: .blocked(reason: reason, delta: delta))
        }
    }

    /// Watches `screen` until it has held still for the quiet period, or the budget is spent on a screen still moving — as a walk waits before it captures.
    ///
    /// A navigating step lands once the hierarchy has *left* its screen, which is before a pop or a push has finished; read then, the after-screen is mid-transition and its hash is one no later read will have (measured on RouteFixture: every `back` answered with its read still changing).
    private func settle(_ screen: some TreeSource) throws {
        var tracker = SettleTracker(quiet: quiet, budget: budget)
        let started = screen.elapsed()
        while true {
            switch try tracker.next(tree: screen.appTree(), elapsed: screen.elapsed() - started) {
            case .watch:
                screen.pause(SettleWindow.interval)
            case .takeScreenshot, .settled, .unsettled:
                return
            }
        }
    }
}

public extension LiveSessionStepper {
    /// What taking the step came to, as the runner's `StepPerformer` reports it.
    enum Performed: Equatable, Sendable {
        /// Landed, and recorded as `recorded` — the step as sent, or what the runner learned taking it — with whether the sheet a `systemTap` answered closed.
        ///
        /// `bound` is the element a `tap`, `scrollTo` or `type` bound, as the snapshot read it (SimWalk#93).
        case landed(Walkbook.RouteStep, sheetClosed: Bool, bound: AXNode?)
        /// Taken and not landed; `reason` is what the runner can say beyond the step itself.
        case blocked(reason: String?)
    }
}

extension LiveSessionStepper {
    /// Why a step request could not be answered at all.
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }
}
