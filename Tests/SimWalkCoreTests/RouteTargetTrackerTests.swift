//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// When the runner may act on what a route step's label resolved to, replayed against scripted reads of a screen as it arrives.
///
/// Every test drives the tracker exactly as the runner does — one read, then one interval's wait before the next — so a decision that depends on how long the screen has been still is measured in the same reads the runner would make.
struct RouteTargetTrackerTests {
    /// SimWalk#24: a bar-only `Edit` on a screen that holds still is taken on the second read — one interval of stillness, which at the default *is* the quiet period — rather than after the whole budget.
    @Test
    func abarOnlyChoiceOnAStillScreenIsTakenOnceTheQuietPeriodPasses() {
        let decisions = Self.replay(Array(repeating: Self.barOnly(), count: 12), label: "Edit")

        #expect(decisions.count == 2)
        #expect(Self.acted(decisions)?.isBarControl == true)
    }

    /// SimWalk#24, the protection it keeps: a row that arrives while the tree is still changing wins over the bar's `Edit` it would otherwise have lost to.
    @Test
    func alateRowStillBeatsTheBarControl() {
        let reads = [Self.barOnly(loading: "Loading"), Self.barOnly(loading: "Loading…"), Self.withRow()]

        let decisions = Self.replay(reads, label: "Edit")

        #expect(decisions.count == 3)
        #expect(Self.acted(decisions)?.isControl == true)
    }

    /// **The quiet period is the screen's own, measured as settling measures it.** A screen whose entry says `settle: 1000` is still for three reads, changes, and is still again: the bar control is taken only once four identical reads have followed the change — stillness before a change counts for nothing.
    @Test
    func stillnessThatBreaksBeforeTheScreensQuietPeriodStartsAgainFromNothing() {
        let still = Self.barOnly(loading: "Loading")
        let changed = Self.barOnly(loading: "Loading…")
        let reads = [still, still, still, changed] + Array(repeating: changed, count: 8)

        let decisions = Self.replay(reads, label: "Edit", quiet: 1.0, budget: 4.0)

        #expect(decisions.count == 8)
        #expect(decisions.dropLast().allSatisfy { $0 == .watch })
        #expect(Self.acted(decisions)?.isBarControl == true)
    }

    /// A screen that says `settle: 6000` holds a bar control for six seconds of stillness, not one interval's.
    ///
    /// The first cut took a bar control after one interval of stillness whatever the screen needed — so on such a screen, where a placeholder can sit unchanged through a fetch, it tapped the bar's `Edit` 250 ms in.
    @Test
    func alongQuietPeriodIsNotSatisfiedByOneStillInterval() {
        let decisions = Self.replay(Array(repeating: Self.barOnly(), count: 30), label: "Edit", quiet: 6.0, budget: 24.0)

        #expect(decisions.count == 25)
        #expect(Self.acted(decisions)?.isBarControl == true)
    }

    /// A lead-in is never taken early, even on a control and a still screen: it waits out the whole lookup — where the step used to report nothing — for a row that matches outright.
    ///
    /// The previous cut waited out the budget from the lead-in's first read, two and a half seconds, and so acted seven and a half seconds before the loop it replaced would have stopped looking for a literal match.
    @Test
    func aleadInWaitsOutTheLookupEvenOnAStillScreen() {
        let decisions = Self.replay(Array(repeating: Self.leadInOnly(), count: 60), label: "Sail, 12 August")

        #expect(decisions.count == 41)
        #expect(Self.acted(decisions)?.match == .prefix)
    }

    /// And a row that does match outright, arriving while the lead-in waits, is the one acted on.
    @Test
    func arowMatchingOutrightThatArrivesLaterBeatsTheLeadIn() {
        let arrived = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 14:50 · 3.43 km, 12 min"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Sail, 12 August"),
        ])

        let decisions = Self.replay([Self.leadInOnly(), Self.leadInOnly(), arrived], label: "Sail, 12 August")

        #expect(decisions.count == 3)
        #expect(Self.acted(decisions)?.node.label == "Sail, 12 August")
    }

    /// A tie between lead-ins is refused only once the lookup is out — the row that would break it may still arrive.
    @Test
    func atieBetweenLeadInsIsRefusedOnlyOnceTheLookupIsOut() {
        let tied = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 07:10 · 5.10 km"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Sail, 12 August 18:30 · 3.20 km"),
        ])

        let decisions = Self.replay(Array(repeating: tied, count: 60), label: "Sail, 12 August")

        #expect(decisions.count == 41)
        guard case let .act(choice) = decisions.last, case .ambiguous = choice else {
            Issue.record("expected a refusal, got \(String(describing: decisions.last))")
            return
        }
    }

    /// A control named outright is acted on at the first read.
    @Test
    func acontrolNamedOutrightIsActedOnAtOnce() {
        #expect(Self.replay([Self.withRow()], label: "Edit").count == 1)
    }

    /// A `tap` whose only match is content waits out the budget for a control; a `scrollTo` arrives at it on the first read, as a scroll always did — not after the screen's quiet period, which on a screen that never holds still is the whole lookup.
    @Test
    func contentWaitsTheBudgetForATapAndIsArrivedAtOnceByAScroll() {
        let heading = Self.screen([AXNode(type: "StaticText", frame: Self.frame(y: 1200, height: 20), label: "By sport")])
        let reads = Array(repeating: heading, count: 20)
        let moving = (0 ..< 20).map { tick in
            Self.screen([
                AXNode(type: "StaticText", frame: Self.frame(y: 1200, height: 20), label: "By sport"),
                AXNode(type: "ProgressIndicator", frame: Self.frame(y: 300, height: 20), value: "\(tick)"),
            ])
        }

        #expect(Self.replay(reads, label: "By sport", reach: .control).count == 11)
        #expect(Self.replay(reads, label: "By sport", reach: .anything).count == 1)
        #expect(Self.replay(moving, label: "By sport", reach: .anything, quiet: 6.0, budget: 24.0).count == 1)
    }

    /// A `scrollTo` whose first read finds only a pushed screen's title bar waits, rather than "arriving" at the bar, and scrolls to the heading of that name once it loads.
    @Test
    func ascrollWaitsOutChromeForTheContentOfItsName() {
        let titleOnly = Self.screen([AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), identifier: "Workouts")])
        let loaded = Self.screen([
            AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), identifier: "Workouts"),
            AXNode(type: "StaticText", frame: Self.frame(y: 1400, height: 24), label: "Workouts"),
        ])

        let decisions = Self.replay([titleOnly, loaded, loaded], label: "Workouts", reach: .anything)

        #expect(decisions.count == 2)
        #expect(Self.acted(decisions)?.node.type == "StaticText")
    }

    /// SimWalk#13: a chip a `{n}` pattern reaches is taken once the lookup has run out with nothing literal found — not on its first read, and not once the screen holds still.
    ///
    /// The previous cut took it after one interval of stillness. The loop it replaced went on looking for a literal `Week {n}` for the whole lookup, so an element that literally reads it and arrives after a still spell was tapped there and would not have been here.
    @Test
    func apatternWaitsOutTheLookupEvenOnAStillScreen() {
        let decisions = Self.replay(Array(repeating: Self.patternOnly(), count: 60), label: "Week {n}")

        #expect(decisions.count == 41)
        #expect(Self.acted(decisions)?.match == .pattern)
    }

    /// The same for a `scrollTo`, which otherwise takes a bar's control or chrome once still: a pattern it matched still waits for the lookup.
    @Test
    func apatternWaitsOutTheLookupForAScrollToo() {
        let decisions = Self.replay(Array(repeating: Self.patternOnly(), count: 60), label: "Week {n}", reach: .anything)

        #expect(decisions.count == 41)
    }

    /// A literal match that goes away leaves a lead-in to be acted on when the budget it started runs out — a moment the loop it replaced would have reported nothing, having nothing literal in hand.
    @Test
    func aleadInIsActedOnWhenTheBudgetALiteralMatchStartedRunsOutOnNothingLiteral() {
        let title = Self.screen([
            AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), identifier: "Sail, 12 August"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 14:50 · 3.43 km, 12 min"),
        ])
        let reads = [title] + Array(repeating: Self.leadInOnly(), count: 59)

        let decisions = Self.replay(reads, label: "Sail, 12 August")

        #expect(decisions.count == 11)
        #expect(Self.acted(decisions)?.match == .prefix)
    }

    /// **A chip drawn before the row, against the loop the tracker replaced** (a Workouts screen): `tap 'Sailing'` while the chip `Sailing 1` is drawn first and the *By sport* row `Sailing, …` arrives three seconds in.
    ///
    /// The old loop found nothing in the chip and tapped the row at 3.0 s; the previous cut started the budget on the chip's lead-in and tapped the chip at 2.5 s — which filters the list, changes the screen, and reports the step landed.
    @Test
    func achipDrawnBeforeTheRowItSharesAWordWithDoesNotTakeTheTapFromIt() {
        let reads = (0 ..< 60).map { read in read < 12 ? Self.screen([Self.chip]) : Self.screen([Self.chip, Self.bySportRow]) }

        let tracked = Self.replay(reads, label: "Sailing")
        let replaced = Self.replacedLoop(reads, label: "Sailing")

        #expect(Self.acted(tracked)?.node.label == Self.bySportRow.label)
        #expect(tracked.count == 13)
        #expect(Self.acted(tracked) == replaced.acted)
        #expect(tracked.count == replaced.reads)
    }

    /// **And with a title bar between them**: the chip first, a navigation bar identified `Sailing` at 2.0 s, the row at 3.0 s.
    ///
    /// The old loop started its budget on the bar and tapped the row when it arrived; the previous cut tapped the bar at 2.5 s and reported UNREACHABLE.
    @Test
    func achipDrawnBeforeATitleBarAndARowDoesNotEndTheWaitForTheRow() {
        let title = AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), identifier: "Sailing")
        let reads = (0 ..< 60).map { read in
            switch read {
            case ..<8: Self.screen([Self.chip])
            case ..<12: Self.screen([title, Self.chip])
            default: Self.screen([title, Self.chip, Self.bySportRow])
            }
        }

        let tracked = Self.replay(reads, label: "Sailing")
        let replaced = Self.replacedLoop(reads, label: "Sailing")

        #expect(Self.acted(tracked)?.node.label == Self.bySportRow.label)
        #expect(Self.acted(tracked) == replaced.acted)
        #expect(tracked.count == replaced.reads)
    }

    /// A `type` step naming fields of two types refuses (`RouteTarget.choose`) — and that refusal is a literal match, so it starts the budget as any literal match does, rather than waiting out the lookup like a lead-in.
    @Test
    func arefusalBetweenFieldsMatchedLiterallyIsAnsweredAtTheBudget() {
        let fields = Self.screen([
            AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 110), children: [
                AXNode(type: "SearchField", frame: AXNode.Frame(x: 24, y: 114, width: 350, height: 36), label: "Search"),
            ]),
            AXNode(type: "TextField", frame: Self.frame(y: 300, height: 44), label: "Search"),
        ])

        let decisions = Self.replay(Array(repeating: fields, count: 60), label: "Search", reach: .textEntry)

        #expect(decisions.count == 11)
        guard case let .act(choice) = decisions.last, case .ambiguous = choice else {
            Issue.record("expected a refusal, got \(String(describing: decisions.last))")
            return
        }
    }

    /// And an element that literally reads `Week {n}`, arriving a beat after the pattern's chip, is the one acted on — as it was before the placeholder existed, when the step waited for it.
    @Test
    func aliteralMatchThatArrivesLaterBeatsThePattern() {
        let arrived = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Week 3"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Week {n}"),
        ])

        let decisions = Self.replay([Self.patternOnly(), arrived], label: "Week {n}")

        #expect(decisions.count == 2)
        #expect(Self.acted(decisions)?.node.label == "Week {n}")
    }

    /// The lookup bounds the whole step, matched or not: a screen whose budget is longer than the lookup stops waiting for something better at the lookup.
    @Test
    func awaitForSomethingBetterEndsAtTheLookupWhenTheBudgetIsLonger() {
        let heading = Self.screen([AXNode(type: "StaticText", frame: Self.frame(y: 1200, height: 20), label: "By sport")])

        let decisions = Self.replay(Array(repeating: heading, count: 100), label: "By sport", budget: 20, lookup: 5)

        #expect(decisions.count == 21)
        #expect(Self.acted(decisions)?.node.label == "By sport")
    }

    /// Nothing matching is answered as nothing once the lookup is out.
    @Test
    func nothingMatchingIsAnsweredOnceTheLookupIsOut() {
        let decisions = Self.replay(Array(repeating: Self.barOnly(), count: 20), label: "Power", lookup: 1.0)

        #expect(decisions.count == 5)
        #expect(decisions.last == .act(.none))
    }

    /// Replays scripted reads as the runner makes them: a read, and one interval before the next, until the tracker acts.
    private static func replay(
        _ reads: [AXNode],
        label: String,
        reach: RouteTarget.Reach = .control,
        quiet: TimeInterval = SettleWindow.interval,
        budget: TimeInterval = 2.5,
        lookup: TimeInterval = 10
    ) -> [RouteTargetTracker.Decision] {
        var tracker = RouteTargetTracker(label: label, reaching: reach, quiet: quiet, budget: budget, lookup: lookup)
        var decisions: [RouteTargetTracker.Decision] = []
        var elapsed: TimeInterval = 0
        for tree in reads {
            let decision = tracker.next(tree: tree, elapsed: elapsed)
            decisions.append(decision)
            if decision != .watch {
                return decisions
            }
            elapsed += SettleWindow.interval
        }
        return decisions
    }

    /// The loop the tracker replaced, as the runner ran it on `main`, replaying the same reads: act at once on a control matched literally, and otherwise on whatever it has once the lookup has run out, or the budget has since its first literal match.
    ///
    /// Literal matches are the only ones that loop made — a whole label, an identifier, a leading component — so it sees the literal tier of each read's choice and nothing else. The static replay holds that choice equal to `main`'s own over every captured tree.
    private static func replacedLoop(_ reads: [AXNode], label: String, budget: TimeInterval = 2.5, lookup: TimeInterval = 10) -> (acted: RouteTarget.Candidate?, reads: Int) {
        var firstMatched: TimeInterval?
        for (read, tree) in reads.enumerated() {
            let now = Double(read) * SettleWindow.interval
            var literal: RouteTarget.Candidate?
            if case let .chosen(candidate, _) = RouteTarget.choose(labelled: label, in: tree),
               [RouteTarget.Match.label, .identifier, .leadingComponent].contains(candidate.match)
            {
                literal = candidate
            }
            if let literal, literal.isControl {
                return (literal, read + 1)
            }
            if literal != nil, firstMatched == nil {
                firstMatched = now
            }
            if now >= lookup || firstMatched.map({ now - $0 >= budget }) == true {
                return (literal, read + 1)
            }
        }
        return (nil, reads.count)
    }

    /// a Workouts filter chip `Sailing 1`, which `'Sailing'` leads into.
    private static let chip = AXNode(type: "Button", frame: AXNode.Frame(x: 156, y: 401, width: 81, height: 45), label: "Sailing 1")

    /// The *By sport* row, whose leading component `'Sailing'` names literally.
    private static let bySportRow = AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 690, width: 358, height: 45), label: "Sailing, Wednesday · 1.48 km in 8 min, 1")

    /// The candidate the tracker finally acted on, if it chose one.
    private static func acted(_ decisions: [RouteTargetTracker.Decision]) -> RouteTarget.Candidate? {
        guard case let .act(choice) = decisions.last, case let .chosen(candidate, _) = choice else { return nil }
        return candidate
    }

    /// A screen whose only `Edit` is the toolbar's, with a line of text that may still be changing.
    private static func barOnly(loading: String = "Loading") -> AXNode {
        screen([
            AXNode(type: "StaticText", frame: frame(y: 300, height: 20), label: loading),
            AXNode(type: "Toolbar", frame: frame(y: 740, height: 50), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 745, width: 60, height: 40), label: "Edit"),
            ]),
        ])
    }

    /// The same screen once its own `Edit` row has loaded.
    private static func withRow() -> AXNode {
        screen([
            AXNode(type: "Button", frame: frame(y: 300), label: "Edit"),
            AXNode(type: "Toolbar", frame: frame(y: 740, height: 50), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 745, width: 60, height: 40), label: "Edit"),
            ]),
        ])
    }

    /// A list whose only match for `'Sail, 12 August'` is a lead-in to a row's data.
    private static func leadInOnly() -> AXNode {
        screen([AXNode(type: "Button", frame: frame(y: 200), label: "Sail, 12 August 14:50 · 3.43 km, 12 min")])
    }

    /// A screen whose only match for `'Week {n}'` is a control the pattern reaches.
    private static func patternOnly() -> AXNode {
        screen([AXNode(type: "Button", frame: frame(y: 200), label: "Week 3")])
    }

    private static func screen(_ content: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: frame(y: 0, height: 874), children: [
            AXNode(type: "Window", frame: frame(y: 0, height: 874), children: content),
        ])
    }

    private static func frame(y: Double, height: Double = 60) -> AXNode.Frame {
        AXNode.Frame(x: 0, y: y, width: 402, height: height)
    }
}
