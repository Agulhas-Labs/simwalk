//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// SimWalk#259: a screen states the values its elements must read, checked on every capture's tree.
struct ExpectedValueCheckTests {
    private static let done = [Walkbook.ExpectedValue(label: "Choosing a strategy", value: "Done")]

    @Test
    func aNodeSoLabelledReadingTheValuePasses() {
        let tree = Self.tree([Self.node(label: "Choosing a strategy", value: "Done")])

        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: .captured) == .captured)
    }

    @Test
    func aNodeSoIdentifiedReadingTheValuePasses() {
        let tree = Self.tree([Self.node(label: "Strategy row", identifier: "Choosing a strategy", value: "Done")])

        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: .captured) == .captured)
    }

    @Test
    func anotherNodeSharingTheLabelMayBeTheOneThatReadsIt() {
        let tree = Self.tree([Self.node(label: "Choosing a strategy"), Self.node(label: "Choosing a strategy", value: "Done")])

        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: .captured) == .captured)
    }

    @Test
    func aDifferentValueIsAMismatchNamingWhatItReads() {
        let tree = Self.tree([Self.node(label: "Choosing a strategy", value: "Start")], identifier: "home-screen")

        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: .captured) == .unexpectedScreen(
            expected: "values: Choosing a strategy = Done",
            found: ["home-screen"],
            reason: "'Choosing a strategy' reads 'Start', not 'Done'"
        ))
    }

    @Test
    func severalNodesSoNamedListTheirDistinctValuesInTreeOrder() {
        let nodes = ["Start", "Mastered", "Start"].map { Self.node(label: "Choosing a strategy", value: $0) }

        let outcome = ExpectedValueCheck.outcome(for: [Self.tree(nodes)], expectValues: Self.done, instead: .captured)

        #expect(Self.reason(outcome) == "'Choosing a strategy' reads 'Start' and 'Mastered', not 'Done'")
    }

    @Test
    func aNodeWithNoValueReadsNoValue() {
        let outcome = ExpectedValueCheck.outcome(for: [Self.tree([Self.node(label: "Choosing a strategy")])], expectValues: Self.done, instead: .captured)

        #expect(Self.reason(outcome) == "'Choosing a strategy' has no value, not 'Done'")
    }

    @Test
    func noNodeSoNamedSaysTheListMayBeLazy() {
        let outcome = ExpectedValueCheck.outcome(for: [Self.tree([Self.node(label: "Other", value: "Done")])], expectValues: Self.done, instead: .captured)

        #expect(Self.reason(outcome) == "nothing labelled or identified 'Choosing a strategy' is in the capture — a lazy list holds only the rows on screen, so end the route by scrolling to it")
    }

    @Test
    func aLabelAndValueAreMatchedWholeNotByTheirLeadingComponent() {
        let tree = Self.tree([Self.node(label: "Choosing a strategy 2", value: "Done"), Self.node(label: "Choosing a strategy", value: "Done 2")])

        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: .captured) != .captured)
    }

    @Test
    func everyCaptureIsCheckedAndTheFailingOnesFoundIsNamed() {
        let good = Self.tree([Self.node(label: "Choosing a strategy", value: "Done")], identifier: "light-screen")
        let bad = Self.tree([Self.node(label: "Choosing a strategy", value: "Start")], identifier: "dark-screen")

        let outcome = ExpectedValueCheck.outcome(for: [good, bad], expectValues: Self.done, instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "values: Choosing a strategy = Done", found: ["dark-screen"], reason: "'Choosing a strategy' reads 'Start', not 'Done'"))
    }

    @Test
    func eachFailingEntryIsNamedAndJoinedAndPassingOnesAreLeftOut() {
        let wanted = [
            Walkbook.ExpectedValue(label: "A", value: "1"),
            Walkbook.ExpectedValue(label: "B", value: "2"),
            Walkbook.ExpectedValue(label: "C", value: "3"),
        ]
        let tree = Self.tree([Self.node(label: "A", value: "9"), Self.node(label: "B", value: "2")])

        let outcome = ExpectedValueCheck.outcome(for: [tree], expectValues: wanted, instead: .captured)

        guard case let .unexpectedScreen(expected, _, reason) = outcome else {
            Issue.record("expected a mismatch, got \(outcome)")
            return
        }

        #expect(expected == "values: A = 1, B = 2, C = 3")
        #expect(reason?.hasPrefix("'A' reads '9', not '1'; nothing labelled or identified 'C'") == true)
    }

    @Test
    func aPriorMismatchKeepsItsExpectedAndFoundAndGainsTheValueClause() {
        let prior = ScreenOutcome.unexpectedScreen(expected: "menu: X", found: ["home-screen"], reason: "earlier")
        let tree = Self.tree([Self.node(label: "Choosing a strategy", value: "Start")])

        let outcome = ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: prior)

        #expect(outcome == .unexpectedScreen(expected: "menu: X", found: ["home-screen"], reason: "earlier. 'Choosing a strategy' reads 'Start', not 'Done'"))
    }

    @Test
    func aFailureAndAStateRefusalRideInTheReason() {
        let tree = Self.tree([Self.node(label: "Choosing a strategy", value: "Start")])

        let failed = ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: .captureFailed(reason: "boom"))
        let refused = ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: .stateNotApplied(reason: "no dark"))

        #expect(Self.reason(failed)?.hasSuffix("The screen also failed mid-capture: boom") == true)
        #expect(Self.reason(refused)?.hasSuffix(". no dark") == true)
    }

    @Test
    func aFilelessVerdictIsUnchanged() {
        let tree = Self.tree([])
        let unreachable = ScreenOutcome.unreachable(routeTried: [], reason: "no route")

        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: Self.done, instead: unreachable) == unreachable)
    }

    @Test
    func noExpectationChecksNothing() {
        let tree = Self.tree([])

        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: nil, instead: .captured) == .captured)
        #expect(ExpectedValueCheck.outcome(for: [tree], expectValues: [], instead: .captured) == .captured)
    }

    private static let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    private static func node(label: String, identifier: String? = nil, value: String? = nil) -> AXNode {
        AXNode(type: "Button", frame: frame, label: label, identifier: identifier, value: value)
    }

    private static func tree(_ nodes: [AXNode], identifier: String? = nil) -> AXNode {
        var children = nodes
        if let identifier {
            children.insert(AXNode(type: "ScrollView", frame: frame, identifier: identifier), at: 0)
        }
        return AXNode(type: "Application", frame: frame, children: children)
    }

    private static func reason(_ outcome: ScreenOutcome) -> String? {
        guard case let .unexpectedScreen(_, _, reason) = outcome else { return nil }
        return reason
    }
}
