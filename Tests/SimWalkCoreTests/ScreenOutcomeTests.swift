//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The honest contract lives in `ScreenOutcome`'s payloads: refusals must carry the evidence that makes them refusals.
struct ScreenOutcomeTests {
    @Test
    func unreachableCarriesTheRouteItTried() throws {
        let outcome = ScreenOutcome.unreachable(routeTried: [.tab(label: "Health"), .tap(label: "Heart")])
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(ScreenOutcome.self, from: data)

        #expect(decoded == .unreachable(routeTried: [.tab(label: "Health"), .tap(label: "Heart")]))
    }

    @Test
    func buildMismatchNamesBothHashes() throws {
        let outcome = ScreenOutcome.buildMismatch(expected: "aeb0ca6f", found: "58ebbd24")
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(ScreenOutcome.self, from: data)

        #expect(decoded == .buildMismatch(expected: "aeb0ca6f", found: "58ebbd24"))
    }

    /// A refusal over evidence that cannot be attributed to the state it was taken under — the reason is the whole payload, so it has to survive the wire.
    @Test
    func stateNotAppliedCarriesTheStatesThatCollided() throws {
        let outcome = ScreenOutcome.stateNotApplied(reason: "states 'light' and 'dark' produced byte-identical screenshots")
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(ScreenOutcome.self, from: data)

        #expect(decoded == outcome)
    }

    /// A screen refused for landing on the wrong screen carries what it expected and what it found instead — the reason the manifest never has to guess, unlike a route it never tried.
    @Test
    func unexpectedScreenCarriesWhatItExpectedAndWhatItFound() throws {
        let outcome = ScreenOutcome.unexpectedScreen(expected: "activity-detail", found: ["workouts-list", nil])
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(ScreenOutcome.self, from: data)

        #expect(decoded == outcome)
    }

    /// Round 2, finding 3: a write failure used to become a plain `captureFailed` whatever was about to be recorded, discarding a `stateNotApplied` refusal's own reason.
    ///
    /// It is folded in instead.
    @Test
    func awriteFailureFoldsIntoAStateRefusalRatherThanReplacingIt() {
        let outcome = ScreenOutcome.stateNotApplied(reason: "states 'light' and 'dark' produced byte-identical screenshots")
            .foldingWriteFailure("disk full")

        guard case let .stateNotApplied(reason) = outcome else {
            Issue.record("expected a state-not-applied refusal, got \(outcome)")
            return
        }

        #expect(reason.contains("byte-identical"))
        #expect(reason.contains("disk full"))
    }

    /// The same fold for `unexpectedScreen`: a write failure used to discard `expected`/`found` for a plain `captureFailed`, un-diagnosing the wrong screen the walk actually reached.
    @Test
    func awriteFailureFoldsIntoAScreenMismatchRatherThanReplacingIt() {
        let outcome = ScreenOutcome.unexpectedScreen(expected: "activity-detail-root", found: ["workouts-list-root"])
            .foldingWriteFailure("disk full")

        guard case let .unexpectedScreen(expected, found, reason) = outcome else {
            Issue.record("expected an unexpectedScreen refusal, got \(outcome)")
            return
        }

        #expect(expected == "activity-detail-root")
        #expect(found == ["workouts-list-root"])
        #expect(reason?.contains("disk full") == true)
    }

    /// Every other outcome has nothing to fold into, so a write failure still becomes a plain `captureFailed` for them — the disk, not the app, is what actually happened.
    @Test
    func awriteFailureOverAnOrdinaryOutcomeBecomesCaptureFailed() {
        #expect(ScreenOutcome.captured.foldingWriteFailure("disk full") == .captureFailed(reason: "disk full"))
    }

    /// Round 3 nit: the verdicts that file nothing have no explanation of what was being filed, so they fold the way `captured` does.
    @Test(arguments: [
        ScreenOutcome.unreachable(routeTried: [.tab(label: "Activity")], reason: "no element labelled 'Activity'"),
        ScreenOutcome.buildMismatch(expected: "a1b2c3d4", found: "58ebbd24"),
    ])
    func awriteFailureOverAVerdictThatFilesNothingBecomesCaptureFailed(outcome: ScreenOutcome) {
        #expect(outcome.foldingWriteFailure("disk full") == .captureFailed(reason: "disk full"))
    }

    /// Round 3: a screen that stopped part-way and then could not file what it had taken has two failures, and the first — which state, and why — is not dropped for the second.
    @Test
    func awriteFailureFoldsIntoAFailureMidCaptureRatherThanReplacingIt() {
        let outcome = ScreenOutcome.captureFailed(reason: "state 'dark': snapshot timed out").foldingWriteFailure("disk full")

        #expect(outcome == .captureFailed(reason: "state 'dark': snapshot timed out. The states it did take could not be filed either: disk full"))
    }

    /// Round 3 nit: a mismatch already carrying a second finding keeps it, with the write failure after it — three facts, none dropped.
    @Test
    func awriteFailureJoinsAMismatchsExistingReasonRatherThanReplacingIt() {
        let outcome = ScreenOutcome.unexpectedScreen(
            expected: "activity-detail-root",
            found: ["workouts-list-root"],
            reason: "The screen also failed mid-capture: state 'dark': snapshot timed out"
        ).foldingWriteFailure("disk full")

        #expect(outcome == .unexpectedScreen(
            expected: "activity-detail-root",
            found: ["workouts-list-root"],
            reason: "The screen also failed mid-capture: state 'dark': snapshot timed out. The states it kept could not be filed: disk full"
        ))
    }

    /// Round 5, finding 4: `reason` may be nothing more than the navigation-bar-title hint `ExpectedScreenCheck` adds, which is not itself something that failed to be filed — so a write failure folded into it never claims "either".
    @Test
    func awriteFailureFoldedIntoATitleHintNeverClaimsEither() {
        let outcome = ScreenOutcome.unexpectedScreen(
            expected: "Sleep",
            found: ["HealthService.SleepView.Identifiers_screen"],
            reason: "'Sleep' is this screen's navigation-bar title, which is localised and never counts; its stable identifier is 'HealthService.SleepView.Identifiers_screen'"
        ).foldingWriteFailure("disk full")

        #expect(outcome == .unexpectedScreen(
            expected: "Sleep",
            found: ["HealthService.SleepView.Identifiers_screen"],
            reason: "'Sleep' is this screen's navigation-bar title, which is localised and never counts; its stable identifier is 'HealthService.SleepView.Identifiers_screen'. The states it kept could not be filed: disk full"
        ))
    }

    /// Only one outcome means the bundle holds what was asked for; every other one is a way of not capturing.
    @Test
    func onlyCapturedCountsAsCaptured() {
        #expect(ScreenOutcome.captured.isCaptured)
        #expect(!ScreenOutcome.unreachable(routeTried: [.tab(label: "Progress")]).isCaptured)
        #expect(!ScreenOutcome.buildMismatch(expected: "a", found: "b").isCaptured)
        #expect(!ScreenOutcome.captureFailed(reason: "disk full").isCaptured)
        #expect(!ScreenOutcome.stateNotApplied(reason: "light and dark are one picture").isCaptured)
        #expect(!ScreenOutcome.unexpectedScreen(expected: "activity-detail", found: ["workouts-list"]).isCaptured)
    }

    /// The property the walk's exit code is derived from: a refused screen is a shortfall even though the bundle is honest about it.
    @Test
    func aRefusedScreenIsAShortfallAndACleanWalkHasNone() {
        let refused = Self.manifest(outcomes: [.captured, .unreachable(routeTried: [.tab(label: "Progress")])])
        #expect(refused.shortfall.map(\.id) == ["screen1"])

        let unapplied = Self.manifest(outcomes: [.captured, .stateNotApplied(reason: "light and dark are one picture")])
        #expect(unapplied.shortfall.map(\.id) == ["screen1"])

        let wrongScreen = Self.manifest(outcomes: [.captured, .unexpectedScreen(expected: "activity-detail", found: ["workouts-list"])])
        #expect(wrongScreen.shortfall.map(\.id) == ["screen1"])

        let clean = Self.manifest(outcomes: [.captured, .captured])
        #expect(clean.shortfall.isEmpty)
    }

    /// A cause a future binary named that this one does not decodes as `nil` rather than failing the whole manifest to decode (SimWalk#58 item 3).
    @Test
    func anUnreachableScreensUnknownCauseDecodesAsNil() throws {
        let json = #"{"unreachable":{"routeTried":[{"tap":{"label":"Heart"}}],"reason":"a system sheet appeared","cause":"somethingFuture"}}"#

        let decoded = try JSONDecoder().decode(ScreenOutcome.self, from: Data(json.utf8))

        #expect(decoded == .unreachable(routeTried: [.tap(label: "Heart")], reason: "a system sheet appeared", cause: nil))
    }

    /// A payload naming two cases is corrupt and refused, as synthesized decoding refused it, never settled by whichever key comes first (SimWalk#61 item 3).
    @Test
    func anOutcomeNamingTwoCasesIsRefused() {
        let json = #"{"captured":{},"captureFailed":{"reason":"the screenshot failed"}}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenOutcome.self, from: Data(json.utf8))
        }
    }

    /// A cause this binary knows survives the round trip, so a reloaded manifest still counts a snapshot-blind screen apart (the #58 review).
    @Test
    func anUnreachableScreensKnownCauseRoundTrips() throws {
        let outcome = ScreenOutcome.unreachable(routeTried: [.tap(label: "Heart")], reason: "not in the snapshot", cause: .snapshotBlind)
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(ScreenOutcome.self, from: data)

        #expect(decoded == outcome)
    }

    // MARK: - UnreachableState (SimWalk#120)

    @Test
    func failingStateSplitsTheStatesAroundIt() {
        let slugs = ["a", "b", "c"]

        #expect(ScreenOutcome.UnreachableState(failing: "a", among: slugs) == ScreenOutcome.UnreachableState(failed: "a", reached: [], notTried: ["b", "c"]))
        #expect(ScreenOutcome.UnreachableState(failing: "b", among: slugs) == ScreenOutcome.UnreachableState(failed: "b", reached: ["a"], notTried: ["c"]))
        #expect(ScreenOutcome.UnreachableState(failing: "c", among: slugs) == ScreenOutcome.UnreachableState(failed: "c", reached: ["a", "b"], notTried: []))
        #expect(ScreenOutcome.UnreachableState(failing: "a", among: ["a"]) == ScreenOutcome.UnreachableState(failed: "a", reached: [], notTried: []))
    }

    @Test
    func theClauseNamesOnlyWhatItHas() {
        #expect(ScreenOutcome.UnreachableState(failed: "x", reached: [], notTried: []).clause == "in state 'x'")
        #expect(ScreenOutcome.UnreachableState(failed: "x", reached: ["a", "b"], notTried: []).clause == "in state 'x' (reached in a, b)")
        #expect(ScreenOutcome.UnreachableState(failed: "x", reached: [], notTried: ["c"]).clause == "in state 'x' (not tried: c)")
        #expect(ScreenOutcome.UnreachableState(failed: "x", reached: ["a", "b"], notTried: ["c"]).clause == "in state 'x' (reached in a, b; not tried: c)")
    }

    @Test
    func anUnreachableScreensStateRoundTripsAndIsOptionalOnDecode() throws {
        let state = ScreenOutcome.UnreachableState(failing: "b", among: ["a", "b", "c"])
        let outcome = ScreenOutcome.unreachable(routeTried: [.tap(label: "Heart")], state: state)
        let data = try JSONEncoder().encode(outcome)

        #expect(String(decoding: data, as: UTF8.self).contains("\"state\""))
        #expect(try JSONDecoder().decode(ScreenOutcome.self, from: data) == outcome)

        let old = #"{"unreachable":{"routeTried":[{"tap":{"label":"Heart"}}]}}"#
        #expect(try JSONDecoder().decode(ScreenOutcome.self, from: Data(old.utf8)) == .unreachable(routeTried: [.tap(label: "Heart")], state: nil))
    }

    private static func manifest(outcomes: [ScreenOutcome]) -> CaptureManifest {
        CaptureManifest(
            walkName: "example",
            appBundleID: "dev.simwalk.route-fixture",
            appBuildHash: "aa9e7052",
            walkbookHash: "55d5ce9d",
            device: CaptureManifest.Device(name: "iPhone18,1", udid: "914BA16A", osVersion: "26.5"),
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 1),
            screens: outcomes.enumerated().map { index, outcome in
                CaptureManifest.ScreenRecord(id: "screen\(index)", outcome: outcome, routeTaken: [], captures: [])
            }
        )
    }
}
