//
// Copyright © Agulhas Labs
//

import Foundation

/// A live session's `step`: the guard, the per-step setup a walk gives a route step, and the answer — decided here so `swift test` checks it, with the runner handing in only the reads and the step itself.
///
/// **A stale guard is refused before anything acts.** The screen is read once, hashed (``ScreenHash``), and compared with the request's `guard`; a text-less screen whose tree is the one a remembered hash was printed for, and whose picture moved by no more than ``PixelSignature/guardTolerance``, still holds the guard (SimWalk#226). Any other mismatch answers `snapshotChanged` with both hashes, and neither the sheet baseline nor the step is touched. That read is also the delta's *before*, so an unguarded step costs the same one read. **After the step the screen is watched until it holds still** (``SettleTracker``), then read as a `session read` reads it.
///
/// **The step is taken as a walk takes it** (`WalkRunner.follow`): the sheet scope a `systemTap` answers from comes from one ``SystemSheetBaseline`` kept for the whole session and told of every landed step, under the session's quiet period. A walk knows its route and reads a baseline only while a `systemTap` is still to come; a session does not know what the agent will send next, so it reads one before every step that is not a `systemTap` — the price of one tree read, the same as a baseline made without a route (``SystemSheetBaseline/init()``).
///
/// **What a landed step reports is what a walk records** — `landedAs`'s step, a `systemTap` with its owner, not the step as sent — because that is what the route so far is made of (``LiveSessionChannel/route()``) and what a saved walkbook replays.
public struct LiveSessionStepper: Sendable {
    /// The quiet period every step is taken under: the session's own, since no walkbook entry names the screen a live step is taken on.
    public let quiet: TimeInterval
    private var baseline = SystemSheetBaseline()
    private var printed: [Printed] = []

    /// How many printed text-less hashes the session remembers the picture of.
    static let memory = 32

    public init(quiet: TimeInterval) {
        self.quiet = quiet
    }

    /// Remembers the picture behind the `screen <hash>` a read of `screen` prints, when its tree has no text (SimWalk#226); the oldest is dropped past ``memory``.
    public mutating func remember(_ screen: LiveScreen) {
        guard let tree = screen.tree, let pixels = screen.pixels else { return }
        let hash = ScreenHash.of(tree, pixels: pixels)
        printed.removeAll { $0.hash == hash }
        printed.append(Printed(hash: hash, treeHash: ScreenHash.of(tree), pixels: pixels))
        if printed.count > Self.memory {
            printed.removeFirst(printed.count - Self.memory)
        }
    }

    /// How long a step is given to land: a walk's budget for the same quiet period.
    public var budget: TimeInterval {
        SettleWindow.budget(forQuiet: quiet)
    }

    /// Answers one `step` request.
    ///
    /// - Parameters:
    ///   - screen: the app's tree as it stands — the read a `session read` hashes — read before the step, and watched after it until it holds still.
    ///   - pixels: the picture of the screen `tree` was read from, for a tree that lists no text (SimWalk#150); `nil` for one that does. It is asked only for the before-hash, and it must be the function a `session read` takes its picture with, or the hash a read prints is not the one the guard is compared with.
    ///   - sheetReads: what a `systemTap`'s baseline reads, the same source the step then reads its sheet from.
    ///   - perform: takes the step against the scope a `systemTap` answers from (`nil` for any other step).
    ///   - read: the screen after the step, as a `session read` reads it.
    public mutating func answer(
        _ request: LiveSessionRequest,
        screen: some TreeSource,
        sheetReads: some TreeSource,
        pixels: (AXNode) -> PixelSignature?,
        perform: (Walkbook.RouteStep, SystemSheetScope?) throws -> Performed,
        read: () throws -> LiveScreen
    ) throws -> LiveSessionResponse {
        guard let step = request.step else {
            throw Failure(description: "step request \(request.n) names no step: send {\"n\": …, \"action\": \"step\", \"step\": <a walkbook route step>}")
        }
        let before = try screen.appTree()
        // A tree with no text is told from another by its picture (SimWalk#150), from the source a read uses; a tree with text never costs a screenshot.
        let beforePixels = PixelSignature.isNeeded(for: before) ? pixels(before) : nil
        let found = ScreenHash.of(before, pixels: beforePixels)
        var held: (expected: String, moved: Double)?
        if let expected = request.guardHash, expected != found {
            var moved: Double?
            if let beforePixels, let remembered = printed.first(where: { $0.hash == expected }), remembered.treeHash == ScreenHash.of(before) {
                moved = remembered.pixels.changedFraction(to: beforePixels)
            }
            guard let moved, moved <= PixelSignature.guardTolerance else {
                return LiveSessionResponse(n: request.n, action: .step, step: .snapshotChanged(expected: expected, found: found, moved: moved))
            }
            held = (expected, moved)
        }
        let scope = try baseline.scope(for: step, from: sheetReads, quiet: quiet)
        let performed = try perform(step, scope)
        try settle(screen)
        let after = try read()
        remember(after)
        // An app that is gone after the step has lost every element it showed.
        let afterTree = after.tree ?? AXNode(type: before.type, frame: before.frame)
        let changed = beforePixels.flatMap { beforePixels in
            PixelSignature.isNeeded(for: afterTree) ? after.pixels.map { (before: beforePixels, after: $0) } : nil
        }
        let delta = ScreenDelta(from: before, to: afterTree, pixels: changed)
        switch performed {
        case let .landed(recorded, sheetClosed, bound):
            baseline.landed(recorded, sheetClosed: sheetClosed)
            return LiveSessionResponse(n: request.n, action: .step, screen: after, step: .landed(recorded, bound: bound, delta: delta, held: held))
        case let .blocked(reason):
            return LiveSessionResponse(n: request.n, action: .step, screen: after, step: .blocked(reason: reason, delta: delta, held: held))
        }
    }

    /// Answers one `relaunch` request: `launch` ends the app and starts it again as the session started it, then the screen is watched until it holds still and read.
    ///
    /// The sheet baseline starts over, since the app it was kept for is gone.
    public mutating func relaunch(_ request: LiveSessionRequest, screen: some TreeSource, launch: () throws -> Bool, read: () throws -> LiveScreen) throws -> LiveSessionResponse {
        baseline = SystemSheetBaseline()
        let turned = try launch()
        try settle(screen)
        let after = try read()
        remember(after)
        return LiveSessionResponse(n: request.n, action: .relaunch, screen: after, notes: turned ? [DeviceAlignment.note()] : nil)
    }

    /// Answers one `scroll` request: `drag` moves the container once, then the screen is watched until it holds still and read, as after a step.
    ///
    /// A request with no `scroll` is refused before anything is dragged. The sheet baseline is kept: the app is the one it was kept for.
    public mutating func scroll(_ request: LiveSessionRequest, screen: some TreeSource, drag: () throws -> Void, read: () throws -> LiveScreen) throws -> LiveSessionResponse {
        guard request.scroll != nil else {
            throw Failure(description: "scroll request \(request.n) names no scroll: send {\"n\": …, \"action\": \"scroll\", \"scroll\": {\"direction\": \"down\", \"container\": <its box>}}")
        }
        try drag()
        try settle(screen)
        let after = try read()
        remember(after)
        return LiveSessionResponse(n: request.n, action: .scroll, screen: after)
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

extension LiveSessionStepper {
    /// A text-less screen's printed hash, with the tree's own hash and the picture it was made from.
    struct Printed: Equatable, Sendable {
        let hash: String
        let treeHash: String
        let pixels: PixelSignature
    }
}

public extension LiveSessionStepper {
    /// What taking the step came to, as the runner's `StepPerformer` reports it.
    enum Performed: Equatable, Sendable {
        /// Landed, and recorded as `recorded` — the step as sent, or what the runner learned taking it — with whether the sheet a `systemTap` answered closed.
        ///
        /// `bound` is the element a `tap`, `scrollTo`, `type` or `longPress` bound, as the snapshot read it (SimWalk#93).
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
