//
// Copyright © Agulhas Labs
//

import Foundation

/// Watches successive reads of a screen for the element a route step names, and says when the runner may act on its choice.
///
/// **A decision the runner used to make in a loop nothing tested.** A screen arrives in parts — a pushed screen's navigation bar at once, the row a step is reaching for a beat later — so the runner reads until the answer cannot get better. `SettleTracker` is the model: a value that takes each read and returns the next move, replayable in a test against a scripted sequence of trees, with time arriving as a parameter.
///
/// Three ways to stop:
/// - **Settled**: the best match is literal and a control in the screen, or content for a `scrollTo` (`RouteTarget.Choice.isSettled`) — waiting cannot improve on it.
/// - **Still for the quiet period** (SimWalk#24): a literal match on a bar's control, or on a bar's control or chrome for a `scrollTo` (`acceptsOnceStill`), once the hierarchy has held still for as long as the screen needs to settle. Measured exactly as `SettleTracker` measures it — each read identical to the one before adds an interval, any change starts again from nothing — so a screen whose walkbook entry says `settle: 6000` holds a bar's `Edit` for six seconds of stillness rather than one interval's: 250 ms of stillness has fooled real screens before, a spinner or a placeholder reading identically while a fetch is still out. At the default the quiet period *is* one interval, so a still bar-only screen is taken on its second read.
/// - **Out of time**: the step's budget has run since something first matched *literally* (`Choice.matchedLiterally`), or the lookup has run since the step began — **whichever comes first, and the lookup whether or not anything has matched**. So a step waits at most the lookup in all, and on a screen whose budget is longer than the lookup (a long `settle`, `SettleWindow.budget(forQuiet:)`) a wait for something better ends at the lookup rather than the budget. The choice in hand is the answer — a lead-in, a tie, content, chrome, nothing — and the runner acts on it or reports it.
///
/// **A `{n}` pattern or a lead-in waits for the lookup to end with nothing literal** — neither starts the budget, neither is taken once still. Each is what the step found where the loop it replaced found nothing, and that loop went on reading for the whole lookup: a row matching literally that arrived three seconds in was tapped. Starting the budget on a lead-in acted at two and a half seconds on a filter chip instead (a list screen: `Sailing 1` drawn first, the *By sport* row `Sailing, …` a beat later). So a pattern or a lead-in is acted on only at a moment that loop would have reported nothing — the lookup run out with nothing literal ever found, or the budget run out on a literal match that has since gone. The cost is a step that uses either: it takes the whole lookup, ten seconds at the default, unless something literal turns up.
public struct RouteTargetTracker {
    private let label: String
    private let reach: RouteTarget.Reach
    private let quiet: TimeInterval
    private let budget: TimeInterval
    private let lookup: TimeInterval
    private let interval: TimeInterval
    private var previous: AXNode?
    private var quietSoFar: TimeInterval = 0
    private var firstMatchedLiterally: TimeInterval?

    /// - Parameters:
    ///   - label: What the step names.
    ///   - reach: What the step is reaching for.
    ///   - quiet: How long the hierarchy must hold still before a bar control is taken — the quiet period of the screen the step is taken on (`SettleWindow.quiet(forStep:of:in:default:)`).
    ///   - budget: How long to keep reading, once something matches literally, for something better to arrive — cut short by the lookup.
    ///   - lookup: The longest the step reads at all, from its first read, whether or not anything has matched.
    ///   - interval: How long the runner leaves between two reads — the unit stillness is measured in.
    public init(
        label: String,
        reaching reach: RouteTarget.Reach,
        quiet: TimeInterval,
        budget: TimeInterval,
        lookup: TimeInterval,
        interval: TimeInterval = SettleWindow.interval
    ) {
        self.label = label
        self.reach = reach
        self.quiet = quiet
        self.budget = budget
        self.lookup = lookup
        self.interval = interval
    }

    /// What the runner should do having just read `tree`, `elapsed` into the step.
    public mutating func next(tree: AXNode, elapsed: TimeInterval) -> Decision {
        if let previous, tree == previous {
            quietSoFar += interval
        } else {
            quietSoFar = 0
        }
        previous = tree
        let choice = RouteTarget.choose(labelled: label, in: tree, reaching: reach)
        if choice.isSettled || (choice.acceptsOnceStill && quietSoFar >= quiet) {
            return .act(choice)
        }
        if choice.matchedLiterally, firstMatchedLiterally == nil {
            firstMatchedLiterally = elapsed
        }
        let waitedForMatch = elapsed >= lookup
        let waitedForBetter = firstMatchedLiterally.map { elapsed - $0 >= budget } ?? false
        return waitedForMatch || waitedForBetter ? .act(choice) : .watch
    }
}

public extension RouteTargetTracker {
    /// The runner's next move.
    enum Decision: Equatable, Sendable {
        /// Wait one interval and read the hierarchy again.
        case watch
        /// Act on this choice — or, for one with nothing to act on, report it.
        case act(RouteTarget.Choice)
    }
}
