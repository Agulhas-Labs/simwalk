//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// SimWalk#111: an open system `Menu` hides the screen's identifier, so it is verified by its `Button` labels instead.
struct ExpectedMenuCheckTests {
    private static let wanted = ["Endurance", "Walking", "Strength"]

    @Test
    func orderedButtonLabelsPassAndExtraButtonsBetweenThemStillDo() {
        let tree = Self.tree(buttons: ["Endurance", "Other thing", "Walking", "Mobility", "Strength"])

        #expect(ExpectedMenuCheck.outcome(for: [tree], expectMenu: Self.wanted, instead: .captured) == .captured)
    }

    @Test
    func aMissingLabelIsAMismatchNamingItAndTheButtonsHeld() {
        let outcome = ExpectedMenuCheck.outcome(for: [Self.tree(identifier: "menus-screen", buttons: ["Endurance", "Walking"])], expectMenu: Self.wanted, instead: .captured)

        #expect(outcome == .unexpectedScreen(
            expected: "menu: Endurance, Walking, Strength",
            found: ["menus-screen"],
            reason: "Menu label 'Strength' was not found among the Buttons in order; its Buttons are 'Endurance', 'Walking'"
        ))
    }

    @Test
    func aTreeWithNoButtonsAndNoIdentifierIsAMismatchFoundNil() {
        let outcome = ExpectedMenuCheck.outcome(for: [Self.tree(buttons: [])], expectMenu: ["Walking"], instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "menu: Walking", found: [nil], reason: "Menu label 'Walking' was not found among the Buttons in order; it holds no Button labels"))
    }

    /// iOS lists a menu's items nearest the control that opened it first, so one opening upwards reads bottom-up (the fixture's `Kind` menu, live, 2026-10-15).
    @Test
    func aMenuThatOpensUpwardsPassesReadBottomUp() {
        let tree = Self.tree(buttons: ["Strength", "Mobility", "Walking", "Endurance"])

        #expect(ExpectedMenuCheck.outcome(for: [tree], expectMenu: Self.wanted, instead: .captured) == .captured)
    }

    @Test
    func labelsOutOfOrderAreAMismatch() {
        let outcome = ExpectedMenuCheck.outcome(for: [Self.tree(buttons: ["Walking", "Endurance", "Strength"])], expectMenu: Self.wanted, instead: .captured)

        guard case let .unexpectedScreen(_, _, reason) = outcome else {
            Issue.record("expected a mismatch, got \(outcome)")
            return
        }

        #expect(reason?.hasPrefix("Menu label 'Walking' was not found") == true)
    }

    @Test
    func aLabelOnlyOnAStaticTextIsAMismatch() {
        let frame = AXNode.Frame(x: 0, y: 0, width: 10, height: 10)
        let tree = AXNode(type: "Application", frame: frame, children: [AXNode(type: "StaticText", frame: frame, label: "Walking")])

        let outcome = ExpectedMenuCheck.outcome(for: [tree], expectMenu: ["Walking"], instead: .captured)

        #expect(outcome != .captured)
    }

    @Test
    func aLabelIsMatchedWholeNotByItsLeadingComponent() {
        let outcome = ExpectedMenuCheck.outcome(for: [Self.tree(buttons: ["Walking 3"])], expectMenu: ["Walking"], instead: .captured)

        #expect(outcome != .captured)
    }

    @Test
    func oneCaptureOfTwoMismatchingIsAMismatch() {
        let good = Self.tree(buttons: Self.wanted)
        let bad = Self.tree(identifier: "menus-screen", buttons: ["Endurance"])

        let outcome = ExpectedMenuCheck.outcome(for: [good, bad], expectMenu: Self.wanted, instead: .captured)

        guard case let .unexpectedScreen(_, found, _) = outcome else {
            Issue.record("expected a mismatch, got \(outcome)")
            return
        }

        #expect(found == ["menus-screen"])
    }

    @Test
    func theButtonListIsCappedAtEight() {
        let buttons = (1 ... 11).map { "B\($0)" }

        let outcome = ExpectedMenuCheck.outcome(for: [Self.tree(buttons: buttons)], expectMenu: ["Nope"], instead: .captured)

        guard case let .unexpectedScreen(_, _, reason) = outcome else {
            Issue.record("expected a mismatch, got \(outcome)")
            return
        }

        #expect(reason?.hasSuffix("'B8' and 3 more") == true)
        #expect(reason?.contains("'B9'") == false)
    }

    @Test
    func aPriorScreenMismatchKeepsItsExpectedAndFoundAndGainsTheMenuClause() {
        let prior = ScreenOutcome.unexpectedScreen(expected: "activity-detail", found: ["menus-screen"], reason: "earlier")

        let outcome = ExpectedMenuCheck.outcome(for: [Self.tree(identifier: "menus-screen", buttons: [])], expectMenu: ["Walking"], instead: prior)

        guard case let .unexpectedScreen(expected, found, reason) = outcome else {
            Issue.record("expected a mismatch, got \(outcome)")
            return
        }

        #expect(expected == "activity-detail")
        #expect(found == ["menus-screen"])
        #expect(reason?.hasPrefix("earlier. Menu label 'Walking'") == true)
    }

    @Test
    func aFailureRidesInTheReasonAndAFilelessVerdictIsUnchanged() {
        let tree = Self.tree(buttons: [])
        let failed = ExpectedMenuCheck.outcome(for: [tree], expectMenu: ["Walking"], instead: .captureFailed(reason: "boom"))
        let unreachable = ScreenOutcome.unreachable(routeTried: [], reason: "no route")

        guard case let .unexpectedScreen(_, _, reason) = failed else {
            Issue.record("expected a mismatch, got \(failed)")
            return
        }

        #expect(reason?.hasSuffix("The screen also failed mid-capture: boom") == true)
        #expect(ExpectedMenuCheck.outcome(for: [tree], expectMenu: ["Walking"], instead: unreachable) == unreachable)
    }

    @Test
    func noMenuExpectationChecksNothing() {
        #expect(ExpectedMenuCheck.outcome(for: [Self.tree(buttons: [])], expectMenu: nil, instead: .captured) == .captured)
    }

    private static let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    private static func tree(identifier: String? = nil, buttons: [String]) -> AXNode {
        var children = buttons.map { AXNode(type: "Cell", frame: frame, children: [AXNode(type: "Button", frame: frame, label: $0)]) }
        if let identifier {
            children.insert(AXNode(type: "ScrollView", frame: frame, identifier: identifier), at: 0)
        }
        return AXNode(type: "Application", frame: frame, children: children)
    }
}
