//
// Copyright © Agulhas Labs
//

import Foundation

/// Decides, read by read, when a screen may be photographed and what the pair of artefacts may claim.
///
/// **It is in the core rather than in the runner because it is the part a test can reach.** Nothing in an XCUITest target is exercised by `swift test`, so a loop written there is a loop nobody checks — and this one decides whether a bundle's two halves are of the same screen. The runner keeps the I/O it alone can do (read the hierarchy, take the picture, wait) and asks here what to do next, so a scripted sequence of trees replays the whole decision without a simulator. Time arrives as `elapsed` for the same reason the determinism rule bans a naked `Date()` in a core logic path.
///
/// **The screenshot is bracketed, which is the fix for a capture whose halves disagree.** The first runner read the settled tree and *then* took the picture, leaving a window in which the screen could change between the description and the photograph — and a failed walk was found holding a pushed screen's `screen.png` beside the pre-push list's `ax-tree.json` (SimWalk#4). One capture whose halves are of different screens is worse than no capture, so the picture is taken between two reads and kept only if they agree; a pair that fails that is discarded and the clock restarts.
///
/// **A screen that never settles is still captured**, flagged rather than refused. Refusing would make an animated app unwalkable, and a capture of a moving screen is a true fact about that screen — what was never acceptable is taking one silently. `unsettled` is where the budget lands, and it is the honest statement that the two artefacts were taken as close together as the runner could manage and were not proven to be of one moment.
///
/// **Given a content wait, a screen that has not arrived is never photographed** (SimWalk#81). A spinner inside the app's chrome holds perfectly still, so the quiet period closed on it: a capture was filed `axTreeSettled: true` beside the chrome-only warning `ScreenContentCheck` raised over the same tree, and the header counted it settled. With `contentWait` set, a tree `ScreenContentCheck.isChromeOnly` calls bare is watched rather than photographed until content arrives or the wait is spent — and then it is `unsettled`, so a chrome-only capture is never a settled one. It is the warning's own predicate, so the two cannot drift apart. Only a capture asks for it: a read that waits for stillness before a step files nothing, and would stall on a screen that is legitimately empty.
///
/// **It keeps two figures about the watch as it reads, because the reads were already being paid for** (SimWalk#67): `reads`, and `settleTime`, the moment the tree took the form it was captured in. A capture that asks for `motion` files them beside `SettleWindow.interval`, the resolution they were read at — a change that comes and goes between two reads is never seen, and neither is an animation the tree cannot see, the blind spot `axTreeSettled` documents.
public struct SettleTracker {
    private let quiet: TimeInterval
    private let budget: TimeInterval
    private let interval: TimeInterval
    private let contentWait: TimeInterval?
    private var previous: AXNode?
    private var quietSoFar: TimeInterval = 0
    private var photographed: AXNode?
    /// When the current run of trees holding more than the app's chrome began; `nil` before one, and again after any chrome-only read.
    private var contentSince: TimeInterval?
    /// The tree the last read handed over, whatever the decision made of it — what the next read is compared with for `settleTime`, apart from `previous`, which the decisions reset.
    private var lastRead: AXNode?
    /// The `elapsed` of the last read that differed from the one before it; the first read counts as differing, since nothing before it was seen.
    private var lastChange: TimeInterval = 0
    /// Whether the last decision was `settled`.
    private var hasSettled = false

    /// How many trees the watch has been handed, the read that brackets the picture included.
    public private(set) var reads = 0

    /// How far into the watch the tree took the form it settled in: the `elapsed` of the last read that differed from the read before it, or of the first read when none did — the screen was already still when the watch first looked, and how long before that is not something a read can see.
    ///
    /// **`nil` until the watch settles, and for a watch that ran out of budget unsettled.** A screen that never held still has no settle time, and the last change seen before the budget ran out is not one: filing it would read as a measured settle where the measurement is that the screen did not settle. Measured in reads, so it is never finer than `interval`.
    public var settleTime: TimeInterval? {
        hasSettled ? lastChange : nil
    }

    /// - Parameters:
    ///   - quiet: How long the hierarchy must hold still before the picture is taken.
    ///   - budget: How long to keep watching before giving up and capturing a screen that never stopped moving.
    ///   - interval: How long the runner leaves between two reads — the unit stillness is measured in.
    ///   - contentWait: How long to wait for a tree holding only the app's chrome to fill before giving up on it (`SettleWindow.contentWait`); `nil` settles on whatever holds still, chrome-only or not.
    public init(quiet: TimeInterval, budget: TimeInterval, interval: TimeInterval = SettleWindow.interval, contentWait: TimeInterval? = nil) {
        self.quiet = quiet
        self.budget = budget
        self.interval = interval
        self.contentWait = contentWait
    }

    /// What the runner should do having just read `tree`, `elapsed` into the watch.
    public mutating func next(tree: AXNode, elapsed: TimeInterval) -> Decision {
        reads += 1
        if tree != lastRead {
            lastChange = elapsed
        }
        lastRead = tree
        let decision = decide(tree: tree, elapsed: elapsed)
        hasSettled = decision == .settled
        return decision
    }

    /// The decision `next` returns, apart from the figures it keeps about the watch.
    private mutating func decide(tree: AXNode, elapsed: TimeInterval) -> Decision {
        if let photographed {
            self.photographed = nil
            guard tree != photographed else {
                return .settled
            }
            // The picture and the tree describe different moments, so the pair is not a capture at all.
            // The clock restarts rather than the capture being filed with a warning: a bracketed pair is
            // the only thing `axTreeSettled: true` is allowed to mean.
            quietSoFar = 0
            previous = tree
            return elapsed >= deadline ? .unsettled : .watch
        }
        if contentWait != nil {
            guard !ScreenContentCheck.isChromeOnly(tree) else {
                // Not the screen yet, however still: no quiet accumulates on it, so it is never photographed.
                // Content read before it — the screen a push is leaving, mid-transition — is forgotten, so the
                // content wait rather than that passing screen's budget decides how long this one gets.
                quietSoFar = 0
                contentSince = nil
                previous = tree
                return elapsed >= deadline ? .unsettled : .watch
            }
            contentSince = contentSince ?? elapsed
        }
        if let previous, tree == previous {
            quietSoFar += interval
        } else {
            // Any change restarts it. Accumulating across a change would let a screen alternating between
            // two states satisfy a long quiet period without ever having been still.
            quietSoFar = 0
        }
        previous = tree
        if quietSoFar >= quiet {
            photographed = tree
            return .takeScreenshot
        }
        return elapsed >= deadline ? .unsettled : .watch
    }

    /// When the watch gives up: `budget` in, as ever, for a screen that had content from the first read or was never asked to wait for it.
    ///
    /// **The budget runs from when the current content arrived**, so a screen that loaded at four seconds still gets the whole budget to hold still rather than being given up on as it appears — and the screen a push is leaving, read before the spinner that replaces it, does not start that clock early. **A screen that never arrives is given up on at the longer of the content wait and the budget**, so a screen's own `settle` still buys a longer watch — which is the advice the chrome-only warning gives. Bounded either way: a chrome-only read past that ends the watch, and each run of content ends one budget after it began.
    private var deadline: TimeInterval {
        guard let contentWait else { return budget }
        guard let contentSince else { return max(contentWait, budget) }
        return contentSince + budget
    }
}

public extension SettleTracker {
    /// The runner's next move.
    enum Decision: Equatable, Sendable {
        /// Wait one interval and read the hierarchy again.
        case watch
        /// The hierarchy has held still for the quiet period: take the picture, then read once more **without waiting** — that read is what brackets it.
        case takeScreenshot
        /// The bracketing read matched: the picture and the tree in hand are of one hierarchy, and the capture may claim it.
        case settled
        /// The budget is spent without the hierarchy ever holding still: capture what is there and record that it was moving.
        case unsettled
    }
}
