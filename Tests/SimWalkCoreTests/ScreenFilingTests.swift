//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// Round 4, finding 4: the runner's `record` decision, held where `swift test` compiles it — `expect` checked first against the outcome the runner was headed for, the state check second on what that made of it, and the write-failure fold of the result.
struct ScreenFilingTests {
    /// The wiring the runner used to hold alone: a screen that captured the wrong screen under `light` and then failed reading `dark` is filed as the mismatch, carrying the failure — never as a bare `captureFailed`, whose captures `bundle audit` reads under the id the walkbook expected.
    @Test
    func awrongScreenOnThePartialPathIsFiledAsTheMismatch() {
        let filing = ScreenFiling.decide(
            trees: [Self.screen("workouts-list")],
            evidence: [Self.evidence(.light, "light picture")],
            expect: "activity-detail",
            instead: .captureFailed(reason: "state 'dark': snapshot timed out")
        )

        #expect(filing == StateApplicationCheck.Filing(
            outcome: .unexpectedScreen(
                expected: "activity-detail",
                found: ["workouts-list"],
                reason: "The screen also failed mid-capture: state 'dark': snapshot timed out"
            ),
            kept: [Walkbook.CaptureState(theme: .light)],
            refused: []
        ))
    }

    /// The state check still runs on the checked outcome: a mismatch and a state refusal come back together, the refused states named beside the mismatch.
    @Test
    func astateRefusalRidesInTheMismatchItWasHandedAfterTheCheck() {
        let filing = ScreenFiling.decide(
            trees: [Self.screen("workouts-list"), Self.screen("workouts-list")],
            evidence: [Self.evidence(.light, "one picture"), Self.evidence(.dark, "one picture")],
            expect: "activity-detail",
            instead: .captured
        )

        guard case let .unexpectedScreen(expected, found, reason) = filing.outcome else {
            Issue.record("expected the mismatch to lead, got \(filing.outcome)")
            return
        }

        #expect(expected == "activity-detail")
        #expect(found == ["workouts-list"])
        #expect(reason?.contains("'light' and 'dark'") == true)
        #expect(filing.refused == [Walkbook.CaptureState(theme: .light), Walkbook.CaptureState(theme: .dark)])
    }

    /// SimWalk#111: the menu check is chained after `expect`, so a menu that did not open is filed as the mismatch.
    @Test
    func aMenuThatDidNotOpenIsFiledAsTheMismatch() {
        let filing = ScreenFiling.decide(
            trees: [Self.screen("menus-screen")],
            evidence: [Self.evidence(.light, "light picture")],
            expect: nil,
            expectMenu: ["Endurance", "Walking"],
            instead: .captured
        )

        guard case let .unexpectedScreen(expected, found, _) = filing.outcome else {
            Issue.record("expected the menu mismatch, got \(filing.outcome)")
            return
        }

        #expect(expected == "menu: Endurance, Walking")
        #expect(found == ["menus-screen"])
    }

    /// Both mismatching: `expect`'s expected and found lead, with the menu clause in the reason.
    @Test
    func anExpectMismatchLeadsAndTheMenuClauseRidesInItsReason() {
        let filing = ScreenFiling.decide(
            trees: [Self.screen("menus-screen")],
            evidence: [Self.evidence(.light, "light picture")],
            expect: "activity-detail",
            expectMenu: ["Walking"],
            instead: .captured
        )

        guard case let .unexpectedScreen(expected, found, reason) = filing.outcome else {
            Issue.record("expected the mismatch, got \(filing.outcome)")
            return
        }

        #expect(expected == "activity-detail")
        #expect(found == ["menus-screen"])
        #expect(reason?.contains("Menu label 'Walking'") == true)
    }

    /// With no `expect`, the filing is the state check's alone.
    @Test
    func noExpectationFilesWhatTheStateCheckDecides() {
        let evidence = [Self.evidence(.light, "light picture"), Self.evidence(.dark, "dark picture")]

        let filing = ScreenFiling.decide(trees: [Self.screen("workouts-list"), Self.screen("workouts-list")], evidence: evidence, expect: nil, instead: .captured)

        #expect(filing == StateApplicationCheck.filing(for: evidence, instead: .captured))
    }

    /// A write failure files nothing, and a refusal that is still true keeps naming the states it refused.
    @Test(arguments: [
        ScreenOutcome.stateNotApplied(reason: "'dark' is not darker than 'light'"),
        ScreenOutcome.unexpectedScreen(expected: "activity-detail", found: ["workouts-list"]),
    ])
    func awriteFailureKeepsTheRefusedStatesBesideARefusal(outcome: ScreenOutcome) {
        let filing = StateApplicationCheck.Filing(outcome: outcome, kept: [Walkbook.CaptureState(theme: .light)], refused: [Walkbook.CaptureState(theme: .dark)])

        let failed = filing.foldingWriteFailure("writing screen 'activity': disk full")

        #expect(failed == StateApplicationCheck.Filing(
            outcome: outcome.foldingWriteFailure("writing screen 'activity': disk full"),
            kept: [],
            refused: [Walkbook.CaptureState(theme: .dark)]
        ))
    }

    /// A write failure that folds into `captureFailed` names no refused states — the outcome beside them refuses nothing.
    @Test(arguments: [ScreenOutcome.captured, ScreenOutcome.captureFailed(reason: "state 'dark': snapshot timed out")])
    func awriteFailureFoldedIntoCaptureFailedNamesNoRefusedStates(outcome: ScreenOutcome) {
        let filing = StateApplicationCheck.Filing(outcome: outcome, kept: [Walkbook.CaptureState(theme: .light)], refused: [Walkbook.CaptureState(theme: .dark)])

        let failed = filing.foldingWriteFailure("writing screen 'activity': disk full")

        #expect(failed == StateApplicationCheck.Filing(outcome: outcome.foldingWriteFailure("writing screen 'activity': disk full"), kept: [], refused: []))
    }

    private static let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    private static func screen(_ identifier: String) -> AXNode {
        AXNode(type: "Application", frame: frame, children: [AXNode(type: "ScrollView", frame: frame, identifier: identifier)])
    }

    private static func evidence(_ theme: Walkbook.Theme, _ picture: String) -> StateApplicationCheck.Evidence {
        StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: theme), screenshot: Data(picture.utf8))
    }

    /// A state refused at launch joins the refused list and turns a captured screen into `stateNotApplied`, leading with an earlier refusal's reason (SimWalk#222 review).
    @Test
    func aStateRefusedAtLaunchIsRefusedWithoutACapture() {
        let landscape = Walkbook.CaptureState(theme: .light, orientation: .portrait)
        let captured = StateApplicationCheck.Filing(outcome: .captured, kept: [Walkbook.CaptureState(theme: .light)], refused: [])

        let refused = captured.refusingAtLaunch([(landscape, "asked for portrait and the app kept a 820×1180 pt frame (landscape)")])

        guard case let .stateNotApplied(reason) = refused.outcome else {
            Issue.record("expected stateNotApplied, got \(refused.outcome)")
            return
        }

        #expect(reason.contains("'\(landscape.slug)' asked for portrait"))
        #expect(refused.refused == [landscape])
        #expect(refused.kept == captured.kept)
        #expect(captured.refusingAtLaunch([]) == captured)
    }

    /// A screen whose every state was refused at launch has no tree to check `expect` against: it is filed as the state refusal naming both states, not as a mismatch on nothing and not as a capture (SimWalk#225).
    @Test
    func aScreenWhoseEveryStateWasRefusedAtLaunchIsFiledAsTheRefusalNamingThem() {
        let light = Walkbook.CaptureState(theme: .light, orientation: .portrait)
        let dark = Walkbook.CaptureState(theme: .dark, orientation: .portrait)
        let clause = "asked for portrait and the app kept a 820×1180 pt frame (landscape)"

        let filing = ScreenFiling.decide(trees: [], evidence: [], expect: "activity-detail", instead: .captured)
            .refusingAtLaunch([(light, clause), (dark, clause)])

        guard case let .stateNotApplied(reason) = filing.outcome else {
            Issue.record("expected stateNotApplied, got \(filing.outcome)")
            return
        }

        #expect(reason.contains("'\(light.slug)' \(clause)"))
        #expect(reason.contains("'\(dark.slug)' \(clause)"))
        #expect(filing.refused == [light, dark])
        #expect(filing.kept.isEmpty)
    }
}
