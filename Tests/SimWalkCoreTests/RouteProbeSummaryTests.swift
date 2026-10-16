//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// What `walk --dry-run` prints: a drifted route is a shortfall — exit 2 — and its line names the step it stopped at, the label that step looked for, and what landed before it.
struct RouteProbeSummaryTests {
    @Test
    func adriftedRouteNamesTheStepTheLabelAndWhatLandedBeforeIt() {
        let probe = RouteProbe(screenID: "power", route: Self.route, outcome: .drifted(step: 1, reason: "'Power' matched nothing on this screen"))

        let line = RouteProbeSummary.probeLine(probe, position: 2)

        #expect(line == "  2 power — DRIFTED at step 2 of 3, tap 'Power' — 'Power' matched nothing on this screen; resolved before it: tab 'Workouts'; not reached: tap 'Heart'")
    }

    @Test
    func adriftedRouteWithNoReasonSaysTheRunnerCouldSayNoMore() {
        let probe = RouteProbe(screenID: "power", route: Self.route, outcome: .drifted(step: 2, reason: nil))

        let line = RouteProbeSummary.probeLine(probe, position: 1)

        #expect(line == "  1 power — DRIFTED at step 3 of 3, tap 'Heart' — the step did not land, and the runner could say no more; resolved before it: tab 'Workouts' → tap 'Power'")
    }

    @Test
    func anunreadableRouteSaysWhetherItLandedIsUnknown() {
        let probe = RouteProbe(screenID: "power", route: Self.route, outcome: .unreadable(step: 0, reason: "snapshot timed out"))

        let line = RouteProbeSummary.probeLine(probe, position: 1)

        #expect(line == "  1 power — UNREADABLE at step 1 of 3, tab 'Workouts' — the hierarchy could not be read, so whether it landed is unknown: snapshot timed out; resolved before it: nothing; not reached: tap 'Power' → tap 'Heart'")
    }

    @Test
    func everyRouteResolvedIsAnUnqualifiedAnswer() throws {
        let report = try RouteProbeFixture.report(of: RouteProbeReportTests.walkbook())

        let answer = RouteProbeSummary(report).answer()

        #expect(answer.verdict == .unqualified("2 of 2 routes resolved · nothing captured"))
        #expect(answer.verdict.exitCode == 0)
        #expect(answer.residue.first == "  1 today — resolved: tab 'Today'")
    }

    @Test
    func adriftedAndAnUnreadableRouteQualifyTheAnswer() throws {
        let report = try RouteProbeFixture.report(
            of: RouteProbeReportTests.walkbook(),
            outcomes: [.unreadable(step: 0, reason: "timed out"), .drifted(step: 1, reason: nil)]
        )

        let answer = RouteProbeSummary(report, qualifiedBy: ["a runner failure this report survived"]).answer()

        #expect(answer.verdict == .qualified(
            ["1 route drifted from the app", "1 route that could not be read to the end", "a runner failure this report survived"],
            detail: "0 of 2 routes resolved · nothing captured"
        ))
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(answer.header.contains("dry run: routes only"))
    }

    /// Each screen is probed under its first state's launch arguments only, so a screen walked under `en` and `de` whose route resolved under `en` is a qualification, not `ok` (SimWalk#36).
    @Test
    func aresolvedRouteWhoseScreenIsWalkedInAnotherLocaleQualifiesTheAnswer() throws {
        let book = try Self.localeWalkbook()
        let gaps = RouteProbeSummary.LaunchConditionGap.all(in: book)

        let answer = try RouteProbeSummary(RouteProbeFixture.report(of: book), launchConditionGaps: gaps).answer()

        #expect(gaps == [
            RouteProbeSummary.LaunchConditionGap(screenID: "settings", axis: .locale, probed: "en", unprobed: ["de"]),
            RouteProbeSummary.LaunchConditionGap(screenID: "today", axis: .locale, probed: nil, unprobed: ["fr"]),
        ])
        #expect(answer.verdict == .qualified(["2 routes not probed under every locale its screen is walked in"], detail: "3 of 3 routes resolved · nothing captured"))
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(answer.residue.contains("  ⚠ settings — probed under locale en only; a walk also follows it under locale de, whose labels this run did not check"))
        #expect(answer.residue.contains("  ⚠ today — probed under the device's locale only; a walk also follows it under locale fr, whose labels this run did not check"))
    }

    /// Extended to arguments (SimWalk#44): a state whose arguments differ from the first state's is a gap naming the axis and the state's slug, not `ok`.
    @Test
    func astateUnderOtherArgumentsThanTheFirstQualifiesTheAnswer() throws {
        let book = try Self.argumentWalkbook()
        let gaps = RouteProbeSummary.LaunchConditionGap.all(in: book)
        let secondSlug = book.screens[0].states[1].slug

        let answer = try RouteProbeSummary(RouteProbeFixture.report(of: book), launchConditionGaps: gaps).answer()

        #expect(gaps == [RouteProbeSummary.LaunchConditionGap(screenID: "power", axis: .arguments, probed: nil, unprobed: [secondSlug])])
        #expect(answer.verdict == .qualified(["1 route not probed under every argument list its screen is walked under"], detail: "1 of 1 route resolved · nothing captured"))
        #expect(answer.residue.contains { $0.contains("arguments") && $0.contains(secondSlug) })
    }

    /// The dry run applies no state's `resetPermissions` or `location` — the first state's included — so a screen with a state naming either is a qualification naming the screen, state and key (SimWalk#62 item 1).
    @Test
    func aScreenWithAStateNamingResetPermissionsOrLocationQualifiesTheAnswer() throws {
        let json = #"""
        {"name":"sheets","appBundleID":"com.example.probe","screens":[
          {"id":"nearby","route":[{"tab":{"label":"Nearby"}},{"systemTap":{"label":"Allow While Using App"}}],"states":[{"theme":"light","resetPermissions":["location"]},{"theme":"dark","location":{"latitude":51.5,"longitude":-0.12}}]},
          {"id":"plain","route":[{"tab":{"label":"Plain"}}],"states":[{"theme":"light"}]}
        ]}
        """#
        let book = try WalkbookLoader.load(from: Data(json.utf8), source: "sheets.json")
        let gaps = RouteProbeSummary.LaunchConditionGap.all(in: book)

        let answer = try RouteProbeSummary(RouteProbeFixture.report(of: book), launchConditionGaps: gaps).answer()

        #expect(gaps == [
            RouteProbeSummary.LaunchConditionGap(screenID: "nearby", axis: .resetPermissions, probed: nil, unprobed: [book.screens[0].states[0].slug]),
            RouteProbeSummary.LaunchConditionGap(screenID: "nearby", axis: .location, probed: nil, unprobed: [book.screens[0].states[1].slug]),
        ])
        #expect(answer.verdict == .qualified(
            ["1 route probed without the permission reset its screen's states name", "1 route probed without the location its screen's states name"],
            detail: "2 of 2 routes resolved · nothing captured"
        ))
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(answer.residue.contains { $0.contains("nearby") && $0.contains("resetPermissions") && $0.contains("probed without") && $0.contains(book.screens[0].states[0].slug) })
        #expect(answer.residue.contains { $0.contains("nearby") && $0.contains("names location") })
    }

    /// A screen whose states share arguments produces no gap.
    @Test
    func astatesSharingArgumentsProduceNoGap() throws {
        let json = #"""
        {"name":"same-args","appBundleID":"com.example.probe","screens":[
          {"id":"power","route":[{"tab":{"label":"Power"}}],"states":[{"theme":"light","arguments":["--seed-sample-data"]},{"theme":"dark","arguments":["--seed-sample-data"]}]}
        ]}
        """#
        let book = try WalkbookLoader.load(from: Data(json.utf8), source: "same-args.json")

        let gaps = RouteProbeSummary.LaunchConditionGap.all(in: book)

        #expect(gaps.isEmpty)
    }

    /// A route drifted behind a system sheet the app's snapshot cannot see is its own qualification, apart from an ordinary drift — mirroring the walk's own verdict (SimWalk#58 item 2).
    @Test
    func adriftCausedByASnapshotBlindSheetIsItsOwnQualification() throws {
        let report = try RouteProbeFixture.report(
            of: RouteProbeReportTests.walkbook(),
            outcomes: [.resolved, .drifted(step: 1, reason: "'Heart' matched nothing on this screen", cause: .snapshotBlind)]
        )

        let answer = RouteProbeSummary(report).answer()

        #expect(answer.verdict == .qualified(
            ["1 route drifted behind a system sheet the app's snapshot cannot see"],
            detail: "1 of 2 routes resolved · nothing captured"
        ))
        #expect(answer.residue.contains { $0.contains("DRIFTED behind a system sheet the app's snapshot cannot see") })
    }

    /// One screen, `power`, whose second state adds an argument the first does not carry — the SimWalk#44 example.
    private static func argumentWalkbook() throws -> Walkbook {
        let json = #"""
        {"name":"args","appBundleID":"com.example.probe","screens":[
          {"id":"power","route":[{"tab":{"label":"Power"}}],"states":[{"theme":"light"},{"theme":"light","arguments":["--seed-sample-data"]}]}
        ]}
        """#
        return try WalkbookLoader.load(from: Data(json.utf8), source: "args.json")
    }

    /// Three screens: `settings` walked in `en` and `de`; `today` in the device's locale and `fr`; `plain` in one locale under two themes, which the probe covers.
    private static func localeWalkbook() throws -> Walkbook {
        let json = #"""
        {"name":"locales","appBundleID":"com.example.probe","screens":[
          {"id":"settings","route":[{"tap":{"label":"Settings"}}],"states":[{"theme":"light","locale":"en"},{"theme":"dark","locale":"en"},{"theme":"light","locale":"de"}]},
          {"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"},{"theme":"light","locale":"fr"}]},
          {"id":"plain","route":[{"tab":{"label":"Plain"}}],"states":[{"theme":"light","locale":"en"},{"theme":"dark","locale":"en"}]}
        ]}
        """#
        return try WalkbookLoader.load(from: Data(json.utf8), source: "locales.json")
    }

    private static var route: [Walkbook.RouteStep] {
        [.tab(label: "Workouts"), .tap(label: "Power"), .tap(label: "Heart")]
    }
}
