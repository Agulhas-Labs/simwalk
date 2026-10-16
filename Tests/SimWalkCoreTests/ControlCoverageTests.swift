//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `ControlCoverage` over bundles on disk: which controls the captured trees expose that no route step in the manifest covers (SimWalk#35).
struct ControlCoverageTests {
    /// Every control is a route's target, or drawn selected: nothing to add, and the plain `ok`.
    @Test
    func aBundleWhoseEveryControlIsRoutedIsTheUnqualifiedAnswer() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("progress", [.tab(label: "Progress"), .tap(label: "Filter")], Self.screen(Self.button("Filter"), Fixture.tabBar())),
            Self.spec("workouts", [.tab(label: "Workouts")], Self.screen(Fixture.tabBar())),
            Self.spec("you", [.tab(label: "You")], Self.screen(Fixture.tabBar())),
        ])

        let findings = try ControlCoverage(bundle).findings()
        let verdict = ControlCoverageSummary(findings, of: bundle).answer().verdict

        #expect(findings.uncovered.isEmpty)
        #expect(findings.controls == 5)
        #expect(verdict == .unqualified("read 3 of 3 screens, 5 controls reachable"))
    }

    /// A button no route taps is named as the step that would reach it, on the screen it is on.
    @Test
    func aControlNoRouteReachesIsNamedAsTheStepThatWould() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("progress", [.tab(label: "Progress")], Self.screen(Self.button("Filter"), Self.button("Share"))),
        ])

        let findings = try ControlCoverage(bundle).findings()

        #expect(findings.uncovered == [
            ControlCoverage.Uncovered(screenID: "progress", step: .tap(label: "Filter")),
            ControlCoverage.Uncovered(screenID: "progress", step: .tap(label: "Share")),
        ])
        #expect(ControlCoverageSummary(findings, of: bundle).answer().verdict.isQualified)
    }

    /// A tab bar is on every screen; its unrouted tab is one finding, as a `tab` step, on the first screen that shows it.
    @Test
    func aControlOnEveryScreenIsReportedOnceOnTheFirst() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("progress", [.tab(label: "Progress")], Self.screen(Fixture.tabBar())),
            Self.spec("workouts", [.tab(label: "Workouts")], Self.screen(Fixture.tabBar())),
        ])

        let findings = try ControlCoverage(bundle).findings()

        #expect(findings.uncovered == [ControlCoverage.Uncovered(screenID: "progress", step: .tab(label: "You"))])
    }

    /// The segmented control's disabled `Y` is not a state to reach, and its selected `W` is the one captured.
    @Test
    func aDisabledControlIsNotReportedAndASelectedOneIsCovered() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("progress", [.tab(label: "Progress")], Fixture.segmentedControl()),
        ])

        let findings = try ControlCoverage(bundle).findings()

        #expect(findings.uncovered.map(\.step) == [.tap(label: "D"), .tap(label: "M"), .tap(label: "6M")])
    }

    /// A `tapPoint` that names its element covers it; one placed by screen coordinates names nothing and covers nothing.
    @Test
    func aTapPointWithALabelCoversItsElement() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("chart", [.tapPoint(label: "Chart", point: [0.8, 0.5])], Self.screen(Self.button("Chart"))),
            Self.spec("bars", [.tapPoint(label: nil, point: [201, 610])], Self.screen(Self.button("Bars"))),
        ])

        let findings = try ControlCoverage(bundle).findings()

        #expect(findings.uncovered == [ControlCoverage.Uncovered(screenID: "bars", step: .tap(label: "Bars"))])
    }

    /// A row's label carries its figures; the step names it by its leading component, which the runner resolves and which outlives the data — and a route naming that component covers it.
    @Test
    func aStepNamesARowByItsLeadingComponent() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("heart", [.tab(label: "Progress"), .tap(label: "Resting Heart Rate")], Self.screen(
                Self.button("Resting Heart Rate, 52, bpm"),
                Self.button("Heart Rate Variability, 73, ms, good")
            )),
        ])

        let findings = try ControlCoverage(bundle).findings()

        #expect(findings.uncovered.map(\.step) == [.tap(label: "Heart Rate Variability")])
    }

    /// The step an unreachable screen tried is the walkbook reaching for that control — covered; the screen itself holds nothing to read, and the verdict says so.
    @Test
    func aStepAnUnreachableScreenTriedCoversItsControlAndTheScreenIsNamed() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.writeWalk(in: directory, screens: [
            Self.spec("progress", [.tab(label: "Progress")], Self.screen(Self.button("Power"))),
            Fixture.ScreenSpec(id: "power", outcome: .unreachable(routeTried: [.tab(label: "Progress"), .tap(label: "Power")]), routeTaken: [.tab(label: "Progress")]),
        ])

        let findings = try ControlCoverage(bundle).findings()
        let verdict = ControlCoverageSummary(findings, of: bundle).answer().verdict

        #expect(findings.uncovered.isEmpty)
        #expect(findings.screensNotRead == ["power"])
        #expect(verdict == .qualified(["1 screen holding no captures at all"], detail: "read 1 of 2 screens, 1 control reachable"))
    }

    /// A segmented option's label carries the segment count — `All 4` — which pins today's data; the suggested step drops it because `tap 'All'` still resolves the control through `RouteTarget`'s lead-in tier.
    @Test
    func aSegmentedOptionsCountDoesNotRideIntoTheSuggestedStep() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("workouts", [.tab(label: "Workouts")], Self.screen(Self.button("All 4"), Self.button("Cycling 2"))),
        ])

        let findings = try ControlCoverage(bundle).findings()

        #expect(findings.uncovered.map(\.step) == [.tap(label: "All"), .tap(label: "Cycling")])
    }

    /// A label that is only a number has no remainder to trim to, so it stays as it is.
    @Test
    func aLabelThatIsOnlyANumberStaysAsItIs() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, [
            Self.spec("workouts", [.tab(label: "Workouts")], Self.screen(Self.button("4"))),
        ])

        let findings = try ControlCoverage(bundle).findings()

        #expect(findings.uncovered.map(\.step) == [.tap(label: "4")])
    }

    private static func walk(in directory: TemporaryDirectory, _ screens: [Fixture.ScreenSpec]) throws -> CaptureBundle {
        try Fixture.writeWalk(in: directory, screens: screens)
    }

    private static func spec(_ id: String, _ route: [Walkbook.RouteStep], _ tree: AXNode) -> Fixture.ScreenSpec {
        Fixture.ScreenSpec(
            id: id,
            routeTaken: route,
            captures: [Fixture.Capture(screenID: id, state: Walkbook.CaptureState(theme: .light), tree: tree)]
        )
    }

    private static func screen(_ children: AXNode...) -> AXNode {
        AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: children)
    }

    private static func button(_ label: String) -> AXNode {
        AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 120, width: 120, height: 44), label: label)
    }
}

private typealias Fixture = CaptureBundleFixture
