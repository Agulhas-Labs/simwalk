//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The JUnit builders: each report's counts are the text answer's own tallies, and every case name is unique.
struct JUnitCasesTests {
    private typealias Fixture = CaptureBundleFixture
    private typealias Tree = LabelTreeFixture

    private static let light = Walkbook.CaptureState(theme: .light)
    private static let dark = Walkbook.CaptureState(theme: .dark)

    // MARK: diff

    private static func segmentation(unreadable: String? = nil) -> StateDiff.Segmentation {
        StateDiff.Segmentation(screenshotPath: "screens/x.png", sectionCount: unreadable == nil ? 3 : 0, unreadable: unreadable)
    }

    private static func flag(_ key: String, inherited: Bool = false) -> FormFlag {
        FormFlag(key: key, finding: .overlappingRuns(first: "a", second: "b", alsoInReference: inherited), crops: [])
    }

    private static func shift(_ label: String) -> CaptureManifest.Motion.Shift {
        let box = AXNode.Frame(x: 0, y: 0, width: 10, height: 10)
        return CaptureManifest.Motion.Shift(
            element: CaptureManifest.Motion.Element(type: "Button", identifier: nil, label: label, path: [0]),
            before: box,
            after: box,
            movedAtMilliseconds: 300,
            cause: nil
        )
    }

    private static func diff() -> BundleDiff {
        let build = BundleDiff.Build(walkName: "w", appBundleID: "app", appBuildHash: "h", walkbookHash: "w")
        let compared = ScreenDiff(
            id: "today",
            referenceOutcome: .captured,
            runOutcome: .captured,
            states: [
                StateDiff(slug: "light", reference: segmentation(), run: segmentation(), flags: [flag("A"), flag("A"), flag("B", inherited: true)]),
                StateDiff(slug: "dark", reference: segmentation(), run: segmentation(unreadable: "no tree"), flags: []),
                StateDiff(slug: "large", reference: segmentation(), run: segmentation(), flags: []),
            ],
            unpairedStates: [ScreenDiff.UnpairedState(slug: "rtl", side: .run, screenshotPath: "screens/rtl.png")],
            shiftFlags: [
                ScreenDiff.ShiftFlag(slug: "dark", side: .run, shift: shift("Row")),
                ScreenDiff.ShiftFlag(slug: "light", side: .run, shift: shift("Row")),
            ]
        )
        let refused = ScreenDiff(id: "power", referenceOutcome: .captured, runOutcome: .captureFailed(reason: "disk"), states: [], unpairedStates: [])
        return BundleDiff(reference: build, run: build, screens: [compared, refused], unpairedScreens: [BundleDiff.UnpairedScreen(id: "extra", side: .reference)])
    }

    /// A shift on a state whose tree could not be read is still counted by `flagCount`, so it fails; counts and names come from the diff.
    @Test
    func aDiffFailsEveryCountedFlagAndShiftEvenOnAnUnreadableState() {
        let diff = Self.diff()

        let report = JUnitDiffCases.report(diff)

        #expect(diff.flagCount > 0)
        #expect(report.failures == diff.flagCount)
        #expect(report.errors == 0)
        let comparedStates = diff.screens.filter(\.isCompared).flatMap(\.states)
        let unreadable = comparedStates.filter { !$0.isCompared }.count
        let unpaired = diff.unpairedScreens.count + diff.screens.filter { !$0.isCompared }.count + diff.screens.filter(\.isCompared).flatMap(\.unpairedStates).count
        #expect(report.skipped == unreadable + unpaired)
        let cleanStates = comparedStates.filter { state in state.isCompared && state.flags.allSatisfy(\.isInherited) && !diff.screens.flatMap { $0.shiftFlags ?? [] }.contains { $0.slug == state.slug } }
        #expect(report.cases.count - report.failures - report.skipped == cleanStates.count)
        #expect(report.cases.contains { $0.name == "dark · shift · Button 'Row'" })
    }

    /// Two counted flags of one rule and key are two cases, and a CI reporter must not merge them.
    @Test
    func repeatedDiffFlagsGetUniqueNames() {
        let names = Self.rendered(JUnitDiffCases.report(Self.diff())).filter { $0.classname == "today" }.map(\.name)

        #expect(Set(names).count == names.count)
        #expect(names.contains { $0.hasSuffix(" #2") })
    }

    // MARK: audit

    private static func motion(settle: Int) -> CaptureManifest.Motion {
        CaptureManifest.Motion(settleMilliseconds: settle, readIntervalMilliseconds: 100, readCount: 12, shifts: [])
    }

    /// Disclosure rows, label findings and a budget overrun each fail once; a rule not applicable or not run is skipped; the counts are the sections' own.
    @Test
    func anAuditFailsEveryFindingAndSkipsWhatDidNotRunWithUniqueNames() throws {
        let directory = try TemporaryDirectory()
        let tree = Tree.screen([
            Tree.element("Switch", y: 100),
            Tree.element("Switch", y: 200),
            Tree.element("Switch", y: 300),
            Fixture.row(type: "Button", label: "Heart", y: 400),
            Fixture.row(type: "StaticText", label: "Log one meal", y: 500),
        ])
        let bundle = try Fixture.writeWalk(in: directory, screens: [
            Fixture.ScreenSpec(id: "you", captures: [
                Fixture.Capture(screenID: "you", state: Self.light, tree: tree, motion: Self.motion(settle: 1501)),
                Fixture.Capture(screenID: "you", state: Self.dark, tree: tree, motion: Self.motion(settle: 1501)),
            ]),
        ])
        let budgets = ["you": Walkbook.Budgets(settleMs: 1500)]
        let audit = try BundleAudit(bundle, budgets: budgets).run()
        let summary = BundleAuditSummary(audit, of: bundle, walkbookPassed: true, budgetsStated: true)

        let report = JUnitAuditCases.report(audit, of: bundle, walkbookPassed: true, budgetsStated: true)

        let labelFindings = AuditRuleName.allCases.compactMap { summary.labelSection($0) }.reduce(0) { $0 + ($1.notApplicable == nil ? $1.findingCount : 0) }
        let disclosure = audit.disclosure.map { DisclosureAuditSummary($0, of: bundle).failingRows.count } ?? 0
        let over = audit.motionBudget?.over.count ?? 0
        #expect(labelFindings > 1)
        #expect(over > 0)
        #expect(disclosure > 0)
        #expect(report.failures == labelFindings + disclosure + over)
        let notApplicable = audit.notApplicable.count
        let notRun = audit.rules.filter { ($0 == .performanceBudget && audit.performanceBudget == nil) || ($0 == .motionBudget && audit.motionBudget == nil) }.count
        // The bundle carries no Apple audit record, so each `apple*` rule is skipped as not recorded.
        let notRecorded = audit.rules.filter(\.isApple).count
        #expect(notApplicable + notRun > 0)
        #expect(report.skipped == notApplicable + notRun + notRecorded)
        #expect(report.errors == 0)
        let names = Self.rendered(report).map { "\($0.classname)\u{0}\($0.name)" }
        #expect(Set(names).count == names.count)
        #expect(report.cases.contains { $0.name.hasSuffix("Switch at y=100") })
    }

    /// The Settings shape: one unlabelled control type repeated in the same states is still one case per control.
    @Test
    func repeatedControlsOfOneTypeAndStateGetUniqueNames() throws {
        let directory = try TemporaryDirectory()
        let tree = Tree.screen((0 ..< 6).map { Tree.element("Switch", y: Double(100 + $0 * 50)) })
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "display", state: Self.light, tree: tree),
            Fixture.Capture(screenID: "display", state: Self.dark, tree: tree),
        ])
        let audit = try BundleAudit(bundle, rules: [.unlabelledControl]).run()
        let summary = BundleAuditSummary(audit, of: bundle)

        let report = JUnitAuditCases.report(audit, of: bundle)

        let findings = try #require(summary.labelSection(.unlabelledControl)).findingCount
        #expect(findings == 6)
        #expect(report.failures == findings)
        let names = Self.rendered(report).map(\.name)
        #expect(Set(names).count == names.count)
    }

    // MARK: renderer

    @Test
    func theRendererNumbersARepeatedNameInCaseOrderWhateverTheResult() {
        let report = JUnitReport(command: "x", cases: [
            JUnitCase(classname: "c", name: "n", result: .failed("1")),
            JUnitCase(classname: "c", name: "n", result: .passed),
            JUnitCase(classname: "c", name: "n", result: .failed("3")),
            JUnitCase(classname: "d", name: "n", result: .passed),
            JUnitCase(classname: "c", name: "n #2", result: .passed),
        ])

        #expect(report.uniquelyNamed.map(\.name) == ["n", "n #2", "n #3", "n", "n #2 #2"])
        #expect(report.render().contains("name=\"n #3\""))
    }

    @Test
    func aQualifiedVerdictWithNoFailureAddsOneFailingVerdictCase() {
        let green = JUnitReport(command: "x", cases: [JUnitCase(classname: "c", name: "n", result: .passed), JUnitCase(classname: "c", name: "s", result: .skipped("why"))])
        let qualified = AnswerVerdict.qualified(["one thing"], detail: "d")

        let held = green.holding(qualified)

        #expect(held.failures == 1)
        #expect(held.cases.last == JUnitCase(classname: "simwalk", name: "verdict", result: .failed(qualified.line)))
        #expect(green.holding(.unqualified("ok")) == green)
        #expect(held.holding(qualified) == held)
        #expect(green.holding(.refused("no")) == green)
    }

    // MARK: walk

    /// `unexpectedScreen` and `buildMismatch` fail every case of the screen, filed captures included; `stateNotApplied` keeps per-state truth.
    @Test
    func aWrongScreenFailsEveryCaseWhileARefusedStateFailsOnlyItself() throws {
        let directory = try TemporaryDirectory()
        func capture(_ id: String, _ state: Walkbook.CaptureState) -> Fixture.Capture {
            Fixture.Capture(screenID: id, state: state, tree: Tree.screen([]))
        }
        let bundle = try Fixture.writeWalk(in: directory, screens: [
            Fixture.ScreenSpec(id: "wrong", outcome: .unexpectedScreen(expected: "a", found: ["b"]), captures: [capture("wrong", Self.light), capture("wrong", Self.dark)]),
            Fixture.ScreenSpec(id: "stale", outcome: .buildMismatch(expected: "1", found: "2")),
            Fixture.ScreenSpec(id: "kept", outcome: .stateNotApplied(reason: "dark rendered as light"), captures: [capture("kept", Self.light)], refusedStates: [Self.dark]),
            Fixture.ScreenSpec(id: "fine", captures: [capture("fine", Self.light)]),
        ])

        let report = JUnitWalkCases.report(of: bundle)

        func results(_ id: String) -> [(String, Bool)] {
            report.cases.filter { $0.classname == id }.map { ($0.name, $0.result == .passed) }
        }
        #expect(results("wrong").map(\.0) == [Self.light.slug, Self.dark.slug])
        #expect(results("wrong").allSatisfy { !$0.1 })
        #expect(results("stale").map(\.0) == ["(screen)"])
        #expect(results("stale").allSatisfy { !$0.1 })
        #expect(results("kept").map(\.0) == [Self.light.slug, Self.dark.slug])
        #expect(results("kept").map(\.1) == [true, false])
        #expect(results("fine").map(\.1) == [true])
        let kept = bundle.manifest.screens.filter { ["kept", "fine"].contains($0.id) }.flatMap(\.captures).count
        #expect(report.cases.count - report.failures == kept)
        if case let .failed(why) = report.cases[0].result {
            #expect(why.contains("expected 'a'"))
        } else {
            Issue.record("a wrong screen's filed capture passed")
        }
    }

    private static func rendered(_ report: JUnitReport) -> [JUnitCase] {
        report.uniquelyNamed
    }
}
