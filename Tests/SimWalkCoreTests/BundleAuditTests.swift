//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle audit` as a whole: which rules run, how each is headed, and how their findings become one verdict.
///
/// The rules have tests of their own; these are about what the run adds — the heading per rule, the selection, the collapse of one control seen in several states, and the verdict.
struct BundleAuditTests {
    private typealias Fixture = CaptureBundleFixture
    private typealias Tree = LabelTreeFixture

    private static let light = Walkbook.CaptureState(theme: .light)
    private static let dark = Walkbook.CaptureState(theme: .dark)
    private static let large = Walkbook.CaptureState(theme: .light, dynamicTypeSize: "UICTContentSizeCategoryXXL")

    private static func text(
        _ captures: [Fixture.Capture],
        only rules: [AuditRuleName] = [],
        in directory: TemporaryDirectory
    ) throws -> String {
        let bundle = try Fixture.write(in: directory, captures: captures)
        let report = try BundleAudit(bundle, rules: rules).run()
        return BundleAuditSummary(report, of: bundle).render()
    }

    private static func capture(_ state: Walkbook.CaptureState, _ children: [AXNode]) -> Fixture.Capture {
        Fixture.Capture(screenID: "you", state: state, tree: Tree.screen(children))
    }

    @Test
    func everyRuleHasItsOwnHeadingAndACleanOneKeepsItsArithmetic() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.text([Self.capture(Self.light, [Tree.element("Button", label: "Save", y: 100)])], in: directory)

        #expect(text.contains("[disclosureAffordance]"))
        #expect(text.contains("[unlabelledControl] clean — 1 control examined across 1 capture"))
        #expect(text.contains("[symbolNameLabel] clean"))
        #expect(text.contains("[duplicateLabel] clean"))
        #expect(text.contains("[smallTarget] clean — 1 control examined across 1 capture"))
        #expect(text.contains("[readingOrder] clean — 1 element examined across 1 capture"))
        #expect(text.contains("[largeTypeOverflow] not applicable — no accessibility type-size state"))
        #expect(text.contains("by 6 rules, 1 not applicable"))
    }

    @Test
    func onlySelectsTheNamedRulesOnceEachInPrintOrder() throws {
        let directory = try TemporaryDirectory()
        let children = [Tree.element("Switch", y: 100)]
        let text = try Self.text(
            [Self.capture(Self.light, children)],
            only: [.duplicateLabel, .unlabelledControl, .duplicateLabel],
            in: directory
        )

        #expect(text.contains("[unlabelledControl] 1 found"))
        #expect(text.contains("[duplicateLabel]"))
        #expect(!text.contains("[symbolNameLabel]"))
        #expect(!text.contains("[disclosureAffordance]"))
        #expect(text.components(separatedBy: "[duplicateLabel]").count == 2)
        #expect(try #require(text.range(of: "[unlabelledControl]")).lowerBound < #require(text.range(of: "[duplicateLabel]")).lowerBound)
    }

    @Test
    func theSelectionIsEveryRuleWhenNoneIsNamed() {
        #expect(AuditRuleName.selection([]) == AuditRuleName.allCases)
        #expect(AuditRuleName.selection([.symbolNameLabel, .symbolNameLabel]) == [.symbolNameLabel])
    }

    @Test
    func oneControlSeenInThreeStatesIsOneFindingNamingThem() throws {
        let directory = try TemporaryDirectory()
        let children = [Tree.element("Switch", y: 100)]
        let text = try Self.text(
            [Self.capture(Self.light, children), Self.capture(Self.dark, children), Self.capture(Self.large, children)],
            only: [.unlabelledControl],
            in: directory
        )

        #expect(text.contains("[unlabelledControl] 1 found"))
        let row = try #require(text.split(separator: "\n").first { $0.contains("Switch") && $0.contains("[") })
        #expect(row.contains("light"))
        #expect(row.contains("dark"))
    }

    @Test
    func twoUnlabelledControlsOfOneTypeOnOneScreenStayTwoFindings() throws {
        let directory = try TemporaryDirectory()
        let children = [Tree.element("Switch", y: 100), Tree.element("Switch", y: 200)]
        let text = try Self.text(
            [Self.capture(Self.light, children), Self.capture(Self.dark, children)],
            only: [.unlabelledControl],
            in: directory
        )

        #expect(text.contains("[unlabelledControl] 2 found"))
    }

    @Test
    func aFindingQualifiesTheVerdictOfACompleteBundle() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [Self.capture(Self.light, [Tree.element("Switch", y: 100)])])
        let report = try BundleAudit(bundle, rules: [.unlabelledControl]).run()
        let answer = BundleAuditSummary(report, of: bundle).answer()

        #expect(report.coverage.isComplete)
        #expect(answer.verdict.isQualified)
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
    }

    @Test
    func aCleanCompleteBundleIsNotQualified() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [Self.capture(Self.light, [Tree.element("Button", label: "Save", y: 100)])])
        let report = try BundleAudit(bundle, rules: [.unlabelledControl]).run()

        #expect(!BundleAuditSummary(report, of: bundle).answer().verdict.isQualified)
    }

    @Test
    func aRuleThatExaminedNothingIsNotApplicableAndNotAPass() throws {
        let directory = try TemporaryDirectory()
        let mirrored = Walkbook.CaptureState(theme: .light, layoutDirection: .rtl)
        let text = try Self.text([Self.capture(mirrored, [Tree.element("Button", label: "Save", y: 100)])], only: [.readingOrder, .unlabelledControl], in: directory)

        #expect(text.contains("[readingOrder] not applicable — only right-to-left states"))
        #expect(text.contains("[unlabelledControl] clean"))
        #expect(text.contains("by 1 rule, 1 not applicable"))
    }

    // MARK: motionBudget (SimWalk#67, M3)

    private static func motion(settle: Int? = 800, shifts: [CaptureManifest.Motion.Shift]? = []) -> CaptureManifest.Motion {
        CaptureManifest.Motion(settleMilliseconds: settle, readIntervalMilliseconds: 100, readCount: 12, shifts: shifts)
    }

    private static func shift(_ label: String) -> CaptureManifest.Motion.Shift {
        let box = AXNode.Frame(x: 0, y: 0, width: 10, height: 10)
        return CaptureManifest.Motion.Shift(
            element: CaptureManifest.Motion.Element(type: "Button", identifier: nil, label: label, path: [0]),
            before: box,
            after: box,
            movedAtMilliseconds: 300,
            cause: CaptureManifest.Motion.Cause(change: .inserted, element: CaptureManifest.Motion.Element(type: "Banner", identifier: nil, label: "Offline", path: [1]))
        )
    }

    private static func budgetText(
        motion: CaptureManifest.Motion?,
        budgets: Walkbook.Budgets,
        outcome: ScreenOutcome = .captured,
        screenID: String = "you",
        in directory: TemporaryDirectory
    ) throws -> String {
        let captures = outcome.isCaptured ? [Fixture.Capture(screenID: "you", state: light, tree: Tree.screen([]), motion: motion)] : []
        let bundle = try Fixture.writeWalk(in: directory, screens: [Fixture.ScreenSpec(id: "you", outcome: outcome, routeTaken: [.tab(label: "You"), .tap(label: "Open")], captures: captures)])
        let report = try BundleAudit(bundle, rules: [.motionBudget], budgets: [screenID: budgets]).run()
        return BundleAuditSummary(report, of: bundle).render()
    }

    @Test
    func aCaptureWithinBudgetIsCountedAndNotListed() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.budgetText(motion: Self.motion(settle: 1500), budgets: Walkbook.Budgets(settleMs: 1500, layoutShifts: 0), in: directory)

        #expect(text.contains("[motionBudget] clean — 2 checks within budget across 1 screen"))
        #expect(text.contains("by 1 rule"))
    }

    @Test
    func aSettleOverBudgetNamesTheFigureTheBudgetAndTheCadence() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.budgetText(motion: Self.motion(settle: 1501), budgets: Walkbook.Budgets(settleMs: 1500), in: directory)

        #expect(text.contains("[motionBudget] 1 over budget"))
        #expect(text.contains("settle 1501 ms > budget 1500 ms (reads every 100 ms)"))
        #expect(text.contains("1 motion budget over budget"))
    }

    @Test
    func aWatchThatNeverSettledIsOverEverySettleBudget() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.budgetText(motion: Self.motion(settle: nil), budgets: Walkbook.Budgets(settleMs: 60000), in: directory)

        #expect(text.contains("never settled within the watch (12 reads, every 100 ms)"))
    }

    @Test
    func shiftsOverBudgetAreListedWithTheirElementAndCause() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.budgetText(motion: Self.motion(shifts: [Self.shift("Save")]), budgets: Walkbook.Budgets(layoutShifts: 0), in: directory)

        #expect(text.contains("1 layout shift > budget 0: Button 'Save' (caused by inserted Banner 'Offline')"))
    }

    @Test
    func aShiftBudgetOverARecordWithoutShiftsIsUnreachableAndNeverWithin() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.budgetText(motion: Self.motion(shifts: nil), budgets: Walkbook.Budgets(layoutShifts: 0), in: directory)

        #expect(text.contains("UNREACHABLE you/light: layoutShifts budget — motion recorded before layout shifts were"))
        #expect(text.contains("0 checks within budget"))
        #expect(text.contains("1 motion budget unreachable"))
    }

    @Test
    func aCaptureWithoutMotionIsUnreachableNamingTheRouteTheWalkTook() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.budgetText(motion: nil, budgets: Walkbook.Budgets(settleMs: 1500), in: directory)

        #expect(text.contains("UNREACHABLE you/light: no motion record (walked without motion); route taken: "))
        #expect(text.contains("Open"))
        #expect(text.contains("0 checks within budget"))
    }

    @Test
    func aScreenNotCapturedIsUnreachableWithItsOutcomeAndRoute() throws {
        let directory = try TemporaryDirectory()
        let refused = try Self.budgetText(motion: nil, budgets: Walkbook.Budgets(settleMs: 1), outcome: .stateNotApplied(reason: "no such axis"), in: directory)
        #expect(refused.contains("UNREACHABLE you: not captured (refused, state not applied); route taken: "))

        let otherDirectory = try TemporaryDirectory()
        let missing = try Self.budgetText(motion: Self.motion(), budgets: Walkbook.Budgets(settleMs: 1), screenID: "elsewhere", in: otherDirectory)
        #expect(missing.contains("UNREACHABLE elsewhere: not captured (not in the bundle)"))
    }

    @Test
    func withoutBudgetsTheRuleSaysItWasNotRunAndIsNotCounted() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [Self.capture(Self.light, [Tree.element("Button", label: "Save", y: 100)])])

        let everyRule = try BundleAuditSummary(BundleAudit(bundle).run(), of: bundle).render()
        let named = try BundleAuditSummary(BundleAudit(bundle, rules: [.motionBudget]).run(), of: bundle).render()

        #expect(everyRule.contains("[motionBudget] not run — no walkbook budgets (pass --walkbook)"))
        #expect(everyRule.contains("by 6 rules, 1 not applicable"))
        #expect(named.contains("[motionBudget] not run — no walkbook budgets (pass --walkbook)"))
        #expect(named.contains("by 0 rules"))
    }

    /// A walkbook that was passed and states nothing is not "no --walkbook".
    @Test
    func aPassedWalkbookWithoutBudgetsIsBlamedInTheHeading() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [Self.capture(Self.light, [Tree.element("Button", label: "Save", y: 100)])])

        let text = try BundleAuditSummary(BundleAudit(bundle).run(), of: bundle, walkbookPassed: true).render()

        #expect(text.contains("[motionBudget] not run — no walkbook budgets (the walkbook states no budgets)"))
        #expect(!text.contains("pass --walkbook"))
    }

    // MARK: performanceBudget (SimWalk#67, M4)

    private static var prefix: String {
        "com.apple.dt.XCTMetric_"
    }

    private static var app: String {
        "dev.simwalk.route-fixture"
    }

    private static func metric(_ identifier: String, _ unit: String, _ values: [Double]) -> CaptureManifest.Performance.Metric {
        CaptureManifest.Performance.Metric(identifier: prefix + identifier, displayName: identifier, unit: unit, polarity: "prefers smaller", measurements: values)
    }

    /// Launch 0.307/0.298/0.41 s (median 307 ms), no hitches, CPU 1.3 s, peak 64 MB.
    private static func performance(_ extra: [CaptureManifest.Performance.Metric] = [], launch: Bool = true) -> CaptureManifest.Performance {
        CaptureManifest.Performance(iterations: 3, metrics: (launch ? [metric("ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration", "s", [0.307, 0.298, 0.41])] : []) + [
            metric("OSSignpost-NavigationTransition.animation.hitch.number", "hitches", [0, 0, 2]),
            metric("CPU-\(app).time", "s", [1.3, 1.32, 1.35]),
            metric("Memory-\(app).physical_peak", "kB", [65536, 65536, 90000]),
        ] + extra)
    }

    /// The record `xcrun xcresulttool get test-results metrics` printed for a real iPad run (iOS 27.0.1, Settings), parsed by the same code the walk uses.
    ///
    /// The fixture's identifiers and units are reconstructed from that run's `measured [...] performanceMetricID:` log lines, with the iteration values as logged. Launch median 307 ms, CPU 1347 ms, peak memory 63963.784 kB (62.46 MB, kB over 1024), no hitches.
    private static func iPadRecord(sourceLocation: SourceLocation = #_sourceLocation) throws -> CaptureManifest.Performance {
        let url = try #require(Bundle.module.url(forResource: "xcresult-metrics-ipad-settings", withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        return try XCResultMetrics.performance(from: Data(contentsOf: url), test: "WalkRunner/testMeasure()", iterations: 3)
    }

    private static func performanceText(
        _ performance: CaptureManifest.Performance?,
        budgets: Walkbook.Budgets,
        device: Bool = true,
        appBundleID: String = "dev.simwalk.route-fixture",
        outcome: ScreenOutcome = .captured,
        in directory: TemporaryDirectory
    ) throws -> String {
        let captures = outcome.isCaptured ? [Fixture.Capture(screenID: "you", state: light, tree: Tree.screen([]), performance: performance)] : []
        let bundle = try Fixture.writeWalk(
            in: directory,
            screens: [Fixture.ScreenSpec(id: "you", outcome: outcome, routeTaken: [.tab(label: "You"), .tap(label: "Open")], captures: captures)],
            buildHash: device ? AppBuildIdentity.unreadOnDevice : "a1b2c3d4",
            appBundleID: appBundleID
        )
        let report = try BundleAudit(bundle, rules: [.performanceBudget], budgets: ["you": budgets]).run()
        return BundleAuditSummary(report, of: bundle).render()
    }

    @Test
    func everyPerformanceBudgetIsHeldToTheMedianInItsOwnUnit() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.performanceText(Self.performance(), budgets: Walkbook.Budgets(launchMs: 308, transitionHitches: 0, cpuMs: 1320, memoryPeakMB: 64), in: directory)

        #expect(text.contains("[performanceBudget] clean — 4 checks within budget across 1 screen"))
    }

    @Test
    func aFigureOverItsBudgetIsListedWithTheMedianItWasMeasuredAt() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.performanceText(Self.performance(), budgets: Walkbook.Budgets(launchMs: 306, transitionHitches: 0, cpuMs: 1319, memoryPeakMB: 63), in: directory)

        #expect(text.contains("[performanceBudget] 3 over budget"))
        #expect(text.contains("you/light: launch 307 ms > budget 306 ms (median of 3 measurements)"))
        #expect(text.contains("you/light: CPU time 1320 ms > budget 1319 ms"))
        #expect(text.contains("you/light: peak memory 64 MB > budget 63 MB"))
        #expect(!text.contains("transition hitches"))
        #expect(text.contains("3 performance budgets over budget"))
    }

    /// The budget is to the first responsive frame; `AppLaunch.duration` is a different span, so it must not stand in.
    @Test
    func aRecordWithOnlyTheAppLaunchMetricIsUnreachableForLaunchMs() throws {
        let directory = try TemporaryDirectory()
        let appLaunch = Self.metric("ApplicationLaunch-AppLaunch.duration", "s", [0.9])
        let text = try Self.performanceText(Self.performance([appLaunch], launch: false), budgets: Walkbook.Budgets(launchMs: 800), in: directory)

        #expect(text.contains("UNREACHABLE you/light: launchMs budget — the record has no first-responsive-frame launch metric (ApplicationFirstFramePresentationResponsive.duration)"))
        #expect(!text.contains("launch 900 ms"))
    }

    /// A median of 65579 kB is 64.04 MB: printed to one decimal it read `64.0 MB > budget 64 MB`.
    @Test
    func aMemoryFigureJustOverItsBudgetPrintsAsOverIt() throws {
        let directory = try TemporaryDirectory()
        let record = CaptureManifest.Performance(iterations: 1, metrics: [Self.metric("Memory-\(Self.app).physical_peak", "kB", [65579])])
        let text = try Self.performanceText(record, budgets: Walkbook.Budgets(memoryPeakMB: 64), in: directory)

        #expect(text.contains("you/light: peak memory 64.04 MB > budget 64 MB"))
    }

    @Test
    func theAuditReadsTheFiguresOfARealIPadRecord() throws {
        let directory = try TemporaryDirectory()
        let record = try Self.iPadRecord()
        let within = try Self.performanceText(record, budgets: Walkbook.Budgets(launchMs: 307, transitionHitches: 0, cpuMs: 1347, memoryPeakMB: 63), appBundleID: "com.apple.Preferences", in: directory)
        #expect(within.contains("[performanceBudget] clean — 4 checks within budget"))

        let over = try Self.performanceText(record, budgets: Walkbook.Budgets(launchMs: 306, transitionHitches: -1, cpuMs: 1346, memoryPeakMB: 62), appBundleID: "com.apple.Preferences", in: TemporaryDirectory())
        #expect(over.contains("launch 307 ms > budget 306 ms (median of 3 measurements)"))
        #expect(over.contains("transition hitches 0 hitches > budget -1 hitches"))
        #expect(over.contains("CPU time 1347 ms > budget 1346 ms"))
        #expect(over.contains("peak memory 62.46 MB > budget 62 MB"))
    }

    @Test
    func theRealRecordKeepsEveryMetricWithItsPolarity() throws {
        let record = try Self.iPadRecord()

        #expect(record.metrics.count == 14)
        #expect(record.metric("com.apple.dt.XCTMetric_OSSignpost-NavigationTransition.animation.frame.rate")?.polarity == "prefers larger")
        #expect(record.metric("com.apple.dt.XCTMetric_OSSignpost-NavigationTransition.animation.hitch.time.ratio")?.unit == "ms per s")
        #expect(record.metric("com.apple.dt.XCTMetric_CPU-com.apple.Preferences.cycles")?.unit == "kC")
    }

    /// G3: none of these may read as within budget.
    @Test
    func aSimulatorBundleIsUnreachableForEveryCaptureEvenWithARecord() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.performanceText(Self.performance(), budgets: Walkbook.Budgets(launchMs: 10000), device: false, in: directory)

        #expect(text.contains("UNREACHABLE you/light: performance is recorded on a device only"))
        #expect(text.contains("0 checks within budget"))
        #expect(text.contains("1 performance budget unreachable"))
    }

    @Test
    func aCaptureWithoutARecordIsUnreachableNamingTheRoute() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.performanceText(nil, budgets: Walkbook.Budgets(launchMs: 10000), in: directory)

        #expect(text.contains("UNREACHABLE you/light: no performance record (not measured); route taken: "))
        #expect(text.contains("Open"))
        #expect(text.contains("0 checks within budget"))
    }

    @Test
    func aRecordLackingTheMetricABudgetNeedsIsUnreachableForThatBudgetOnly() throws {
        let directory = try TemporaryDirectory()
        let record = CaptureManifest.Performance(iterations: 3, metrics: [Self.metric("CPU-\(Self.app).time", "s", [1])])
        let text = try Self.performanceText(record, budgets: Walkbook.Budgets(launchMs: 500, transitionHitches: 0, cpuMs: 2000, memoryPeakMB: 100), in: directory)

        #expect(text.contains("[performanceBudget] 3 unreachable — 1 check within budget"))
        #expect(text.contains("UNREACHABLE you/light: launchMs budget — the record has no first-responsive-frame launch metric"))
        #expect(text.contains("UNREACHABLE you/light: transitionHitches budget"))
        #expect(text.contains("UNREACHABLE you/light: memoryPeakMB budget"))
    }

    @Test
    func aMetricOfAnotherAppOrInAnUnexpectedUnitIsNotAFigure() throws {
        let directory = try TemporaryDirectory()
        let record = CaptureManifest.Performance(iterations: 1, metrics: [
            Self.metric("CPU-com.other.app.time", "s", [1]),
            Self.metric("Memory-\(Self.app).physical_peak", "MB", [64]),
        ])
        let text = try Self.performanceText(record, budgets: Walkbook.Budgets(cpuMs: 5000, memoryPeakMB: 500), in: directory)

        #expect(text.contains("UNREACHABLE you/light: cpuMs budget"))
        #expect(text.contains("UNREACHABLE you/light: memoryPeakMB budget"))
        #expect(text.contains("0 checks within budget"))
    }

    @Test
    func aScreenNotCapturedIsUnreachableForPerformanceToo() throws {
        let directory = try TemporaryDirectory()
        let text = try Self.performanceText(nil, budgets: Walkbook.Budgets(launchMs: 1), outcome: .stateNotApplied(reason: "no such axis"), in: directory)

        #expect(text.contains("UNREACHABLE you: not captured (refused, state not applied); route taken: "))
    }

    @Test
    func aDeviceWalkIsToldFromASimulatorOneByHowItKnewTheBuild() {
        func manifest(hash: String, provenance: CaptureManifest.AppBuildProvenance?) -> CaptureManifest {
            CaptureManifest(
                walkName: "w", appBundleID: Self.app, appBuildHash: hash, walkbookHash: "h",
                device: CaptureManifest.Device(name: "iPad17,3", udid: "u", osVersion: "27.0"),
                startedAt: Date(timeIntervalSince1970: 0), finishedAt: Date(timeIntervalSince1970: 1), settleQuietMilliseconds: 250,
                appBuildProvenance: provenance, screens: []
            )
        }

        #expect(manifest(hash: AppBuildIdentity.unreadOnDevice, provenance: nil).isDeviceWalk)
        #expect(manifest(hash: "a1b2c3d4", provenance: .installed).isDeviceWalk)
        #expect(!manifest(hash: "a1b2c3d4", provenance: nil).isDeviceWalk)
    }

    @Test
    func theRulesSplitTheBudgetsBetweenThem() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.writeWalk(in: directory, screens: [
            Fixture.ScreenSpec(id: "you", captures: [Fixture.Capture(screenID: "you", state: Self.light, tree: Tree.screen([]), motion: Self.motion(settle: 100))]),
        ])
        let motionOnly = try BundleAuditSummary(BundleAudit(bundle, budgets: ["you": Walkbook.Budgets(settleMs: 500)]).run(), of: bundle).render()
        let performanceOnly = try BundleAuditSummary(BundleAudit(bundle, budgets: ["you": Walkbook.Budgets(cpuMs: 500)]).run(), of: bundle, walkbookPassed: true, budgetsStated: true).render()

        #expect(motionOnly.contains("[motionBudget] clean — 1 check within budget"))
        #expect(motionOnly.contains("[performanceBudget] not run — no walkbook performance budgets (pass --walkbook)"))
        #expect(performanceOnly.contains("[motionBudget] not run"))
        #expect(performanceOnly.contains("[performanceBudget] 1 unreachable"))
        #expect(!performanceOnly.contains("no motion record"))
        // A walkbook with performance budgets alone does not state "no budgets", and the reverse names its kind too.
        #expect(performanceOnly.contains("[motionBudget] not run — no walkbook motion budgets (the walkbook states no motion budgets)"))
        let motionOnlyPassed = try BundleAuditSummary(BundleAudit(bundle, budgets: ["you": Walkbook.Budgets(settleMs: 500)]).run(), of: bundle, walkbookPassed: true, budgetsStated: true).render()
        #expect(motionOnlyPassed.contains("[performanceBudget] not run — no walkbook performance budgets (the walkbook states no performance budgets)"))
        let none = try BundleAuditSummary(BundleAudit(bundle).run(), of: bundle, walkbookPassed: true).render()
        #expect(none.contains("[motionBudget] not run — no walkbook budgets (the walkbook states no budgets)"))
    }
}
