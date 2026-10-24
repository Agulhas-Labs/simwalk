//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The seven `apple*` rules of `bundle audit`: Apple's own findings, read from each state's record and never from the tree.
///
/// A capture is audited, failed, unreadable or not recorded; only the first is evidence, and no other is ever read as clean.
struct AppleAuditRuleTests {
    private typealias Fixture = CaptureBundleFixture
    private typealias Tree = LabelTreeFixture

    private static let light = Walkbook.CaptureState(theme: .light)
    private static let dark = Walkbook.CaptureState(theme: .dark)
    private static let appleRules = AuditRuleName.allCases.filter(\.isApple)
    private static let types = ["contrast", "textClipped", "dynamicType", "hitRegion", "elementDetection", "trait", "sufficientElementDescription"]

    private static func issue(_ type: String, label: String = "General", identifier: String = "", elementType: String? = "StaticText", description: String = "Contrast nearly passed", y: Double = 100) -> AppleAuditRecord.Issue {
        AppleAuditRecord.Issue(
            type: type,
            compactDescription: description,
            detailedDescription: "details",
            element: elementType.map { AppleAuditRecord.Element(type: $0, identifier: identifier, label: label, frame: AXNode.Frame(x: 0, y: y, width: 100, height: 20)) }
        )
    }

    private static func capture(_ state: Walkbook.CaptureState, screen: String = "you", record: AppleAuditRecord?) -> Fixture.Capture {
        Fixture.Capture(screenID: screen, state: state, tree: Tree.screen([Tree.element("Button", label: "Save", y: 100)]), appleAudit: record)
    }

    private static func screen(_ id: String, _ captures: [Fixture.Capture]) -> Fixture.ScreenSpec {
        Fixture.ScreenSpec(id: id, captures: captures)
    }

    private static func record(_ issues: [AppleAuditRecord.Issue] = [], error: String? = nil, elementsRead: Bool? = nil) -> AppleAuditRecord {
        AppleAuditRecord(milliseconds: 1500, error: error, issues: issues, elementsRead: elementsRead)
    }

    private static func text(_ captures: [Fixture.Capture], only rules: [AuditRuleName] = Self.appleRules, in directory: TemporaryDirectory) throws -> Run {
        let bundle = try Fixture.write(in: directory, captures: captures)
        let report = try BundleAudit(bundle, rules: rules).run()
        let summary = BundleAuditSummary(report, of: bundle)
        return Run(text: summary.render(), answer: summary.answer(), bundle: bundle, report: report)
    }

    // MARK: G1, G2

    @Test(arguments: zip(types, appleRules))
    func aRecordWithOneIssueOfATypeFiresExactlyItsRule(type: String, rule: AuditRuleName) throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([Self.capture(Self.light, record: Self.record([Self.issue(type)]))], in: directory)

        #expect(rule.appleIssueType == type)
        for other in Self.appleRules {
            let heading = other == rule ? "[\(other.rawValue)] 1 found — 1 capture audited" : "[\(other.rawValue)] clean — 1 capture audited"
            #expect(run.text.contains(heading))
        }
        #expect(run.text.contains("    StaticText 'General' — Contrast nearly passed [light]"))
        #expect(run.answer.verdict.isQualified)
        #expect(run.text.contains("1 \(rule.rawValue) finding from Apple's audit"))
    }

    @Test
    func aCleanRecordFiresNothing() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([Self.capture(Self.light, record: Self.record())], in: directory)

        #expect(!run.answer.verdict.isQualified)
        #expect(run.text.contains("by 7 rules"))
        for rule in Self.appleRules {
            #expect(run.text.contains("[\(rule.rawValue)] clean — 1 capture audited"))
        }
    }

    // MARK: G3

    @Test
    func aBundleWithNoRecordSaysNotRecordedOnceForEveryRuleAndCountsNone() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([Self.capture(Self.light, record: nil)], in: directory)

        #expect(run.text.contains("[appleContrast, appleTextClipped, appleDynamicType, appleHitRegion, appleElementDetection, appleTrait, appleDescription] not recorded — the walk did not run Apple's accessibility audit (walkbook \"appleAudit\": true, or walk --apple-audit)"))
        #expect(!run.text.contains("clean"))
        #expect(run.text.contains("by 0 rules"))
    }

    @Test
    func someCapturesRecordedSaysHowManyWereAudited() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([Self.capture(Self.light, record: Self.record()), Self.capture(Self.dark, record: nil)], only: [.appleContrast], in: directory)

        #expect(run.text.contains("[appleContrast] clean — 1 of 2 captures audited"))
    }

    @Test
    func aFailedAuditIsNotCleanAndNamesHowManyWereNotChecked() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([Self.capture(Self.light, record: Self.record(error: "timed out")), Self.capture(Self.dark, record: Self.record())], only: [.appleTrait], in: directory)

        #expect(run.text.contains("[appleTrait] clean — 1 capture audited; 1 audit failed, not checked there"))
        #expect(run.answer.verdict.isQualified)
    }

    @Test
    func failedAuditsNameWhichStatesAndApplesOwnReasonOnce() throws {
        let directory = try TemporaryDirectory()
        let error = #"Error Domain=com.apple.xcode.xctest.accessibilityAudit Code=-56 "Audit failed to complete in time" UserInfo={NSLocalizedDescription=Audit failed to complete in time}"#
        let run = try Self.text([
            Self.capture(Self.light, screen: "display-text-size-lower", record: Self.record(error: error)),
            Self.capture(Self.dark, screen: "display-text-size-lower", record: Self.record(error: error)),
        ], in: directory)

        #expect(run.text.contains("apple audit: 2 captures failed, not checked there — Audit failed to complete in time: display-text-size-lower [light, dark]"))
        #expect(run.text.contains("[appleContrast] not checked — 0 captures audited; 2 audits failed, not checked there"))
    }

    @Test
    func anAllFailedBundleIsQualifiedNotClean() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([Self.capture(Self.light, record: Self.record(error: "timed out"))], only: [.appleTrait], in: directory)

        #expect(run.text.contains("[appleTrait] not checked — 0 captures audited; 1 audit failed, not checked there"))
        #expect(run.answer.verdict.isQualified)
    }

    @Test
    func anUnreadableRecordIsNamedWithItsPathAndNotCheckedThere() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Fixture.write(in: directory, captures: [Self.capture(Self.light, record: Self.record()), Self.capture(Self.dark, record: Self.record())])
        let missing = CaptureBundleLayout.appleAuditPath(screenID: "you", stateSlug: "light")
        let malformed = CaptureBundleLayout.appleAuditPath(screenID: "you", stateSlug: "dark")
        try FileManager.default.removeItem(at: CaptureBundleLayout.url(forRelativePath: missing, in: bundle.url))
        try Data("{".utf8).write(to: CaptureBundleLayout.url(forRelativePath: malformed, in: bundle.url))

        let report = try BundleAudit(bundle, rules: [.appleContrast, .appleTrait]).run()
        let text = BundleAuditSummary(report, of: bundle).render()

        #expect(text.contains("[appleContrast] not checked — 0 captures audited; 2 unreadable, not checked there"))
        #expect(text.contains("  unreadable: \(missing) (file missing)"))
        #expect(text.contains("  unreadable: \(malformed) (malformed)"))
        #expect(text.components(separatedBy: "unreadable: ").count == 3)
        #expect(BundleAuditSummary(report, of: bundle).answer().verdict.isQualified)
    }

    @Test
    func anIssueOfATypeNoRuleReadsIsNeverDropped() throws {
        let directory = try TemporaryDirectory()
        let unknown = Self.issue("unknown(4294967296)", label: "A")
        let other = Self.issue("unknown(4294967296)", label: "B")
        let run = try Self.text([Self.capture(Self.light, record: Self.record([unknown, other]))], in: directory)

        #expect(run.text.contains("apple audit: 2 issues of a type no rule reads — unknown(4294967296) ×2"))
        #expect(run.answer.verdict.isQualified)
    }

    // MARK: G4

    @Test
    func identityIgnoresTheFrameSoOneIssueSeenInTwoStatesIsOneRow() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([
            Self.capture(Self.light, record: Self.record([Self.issue("contrast", y: 100)])),
            Self.capture(Self.dark, record: Self.record([Self.issue("contrast", y: 340)])),
        ], only: [.appleContrast], in: directory)

        #expect(run.text.contains("[appleContrast] 1 found — 2 captures audited"))
        #expect(run.text.contains("    StaticText 'General' — Contrast nearly passed [light, dark]"))
    }

    @Test
    func twoEqualIssuesInOneCaptureStayTwoRowsAndAnIdentifierNamesALabellessElement() throws {
        let directory = try TemporaryDirectory()
        let twin = Self.issue("contrast", label: "")
        let named = Self.issue("contrast", label: "", identifier: "save-button", elementType: "Button")
        let bare = Self.issue("contrast", elementType: nil, description: "Contrast failed for SwiftUI.AccessibilityNode")
        let run = try Self.text([Self.capture(Self.light, record: Self.record([twin, twin, named, bare], elementsRead: true))], only: [.appleContrast], in: directory)

        #expect(run.text.contains("[appleContrast] 4 found"))
        #expect(run.text.contains("    Button #save-button — Contrast nearly passed [light]"))
        #expect(run.text.contains("    Apple named no element — Contrast failed for SwiftUI.AccessibilityNode [light]"))
    }

    @Test
    func anIssueWhoseElementCouldNotBeReadSaysSoWithTheErrorTruncated() throws {
        let directory = try TemporaryDirectory()
        let error = String(repeating: "x", count: 120)
        let lost = AppleAuditRecord.Issue(type: "contrast", compactDescription: "Contrast nearly passed", detailedDescription: "details", elementUnreadable: error)
        let run = try Self.text([Self.capture(Self.light, record: Self.record([lost], elementsRead: true))], only: [.appleContrast], in: directory)

        let reason = String(repeating: "x", count: 79) + "…"

        #expect(run.text.contains("    the element could not be read after the audit (\(reason)) — Contrast nearly passed [light]"))
        #expect(!run.text.contains("Apple named no element"))
    }

    /// The same issue with no element named in one state and a lost element in the other is two rows, each true of its own state.
    @Test
    func statesThatDisagreeOnWhyThereIsNoElementAreRowsOfTheirOwn() throws {
        let directory = try TemporaryDirectory()
        let none = AppleAuditRecord.Issue(type: "contrast", compactDescription: "Contrast nearly passed", detailedDescription: "details")
        var lost = none
        lost.elementUnreadable = "snapshot failed"
        let run = try Self.text([
            Self.capture(Self.light, record: Self.record([none], elementsRead: true)),
            Self.capture(Self.dark, record: Self.record([lost], elementsRead: true)),
        ], only: [.appleContrast], in: directory)

        #expect(run.text.contains("[appleContrast] 2 found"))
        #expect(run.text.contains("    Apple named no element — Contrast nearly passed [light]"))
        #expect(run.text.contains("    the element could not be read after the audit (snapshot failed) — Contrast nearly passed [dark]"))
    }

    @Test
    func anElementlessFindingIsNeverPairedAcrossStatesSoEachStateIsARowOfItsOwn() throws {
        let directory = try TemporaryDirectory()
        let none = AppleAuditRecord.Issue(type: "contrast", compactDescription: "Contrast nearly passed", detailedDescription: "details")
        let run = try Self.text([
            Self.capture(Self.light, record: Self.record([none], elementsRead: true)),
            Self.capture(Self.dark, record: Self.record([none], elementsRead: true)),
        ], only: [.appleContrast], in: directory)

        #expect(run.text.contains("[appleContrast] 2 found"))
        #expect(run.text.contains("    Apple named no element — Contrast nearly passed [light]"))
        #expect(run.text.contains("    Apple named no element — Contrast nearly passed [dark]"))
    }

    /// Five findings in light and three in dark, none naming an element, are one counted row per state, and the heading counts all eight (SimWalk#233).
    ///
    /// It pins the text and the row count, not the order of the rows.
    @Test
    func elementlessFindingsAreCountedPerStateAndNeverListedUnderBothStates() throws {
        let directory = try TemporaryDirectory()
        let none = AppleAuditRecord.Issue(type: "contrast", compactDescription: "Contrast nearly passed", detailedDescription: "details")
        let run = try Self.text([
            Self.capture(Self.light, record: Self.record(Array(repeating: none, count: 5), elementsRead: true)),
            Self.capture(Self.dark, record: Self.record(Array(repeating: none, count: 3), elementsRead: true)),
        ], only: [.appleContrast], in: directory)

        #expect(run.text.contains("[appleContrast] 8 found"))
        #expect(run.text.contains("    Apple named no element — Contrast nearly passed ×5 [light]"))
        #expect(run.text.contains("    Apple named no element — Contrast nearly passed ×3 [dark]"))
        #expect(!run.text.contains("light, dark"))
    }

    /// One element whose contrast is "nearly passed" in light and "failed" at AX3 is a row for each, each naming only its own state.
    ///
    /// It does not pin the order of the rows.
    @Test
    func aNamedElementWhoseDescriptionDiffersBetweenStatesIsARowPerDescription() throws {
        let directory = try TemporaryDirectory()
        let accessibilityXL = Walkbook.CaptureState(theme: .light, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityXL")
        let run = try Self.text([
            Self.capture(Self.light, record: Self.record([Self.issue("contrast", label: "App Version: 2.1.6", description: "Contrast nearly passed", y: 468)], elementsRead: true)),
            Self.capture(accessibilityXL, record: Self.record([Self.issue("contrast", label: "App Version: 2.1.6", description: "Contrast failed", y: 796)], elementsRead: true)),
        ], only: [.appleContrast], in: directory)

        #expect(run.text.contains("[appleContrast] 2 found"))
        #expect(run.text.contains("    StaticText 'App Version: 2.1.6' — Contrast nearly passed [light]"))
        #expect(run.text.contains("    StaticText 'App Version: 2.1.6' — Contrast failed [\(accessibilityXL.slug)]"))
    }

    /// A record from before the runner marked its records cannot say whether the element was named, so the old wording stands.
    @Test
    func anOldRecordWithNoElementReadsAsItDidBeforeAndANewOneSaysApplePassedNone() throws {
        let directory = try TemporaryDirectory()
        let none = AppleAuditRecord.Issue(type: "contrast", compactDescription: "Contrast nearly passed", detailedDescription: "details")
        let old = try Self.text([Self.capture(Self.light, record: Self.record([none]))], only: [.appleContrast], in: directory)
        let other = try TemporaryDirectory()
        let current = try Self.text([Self.capture(Self.light, record: Self.record([none], elementsRead: true))], only: [.appleContrast], in: other)

        #expect(old.text.contains("    (no element) — Contrast nearly passed [light]"))
        #expect(!old.text.contains("Apple named no element"))
        #expect(current.text.contains("    Apple named no element — Contrast nearly passed [light]"))
    }

    @Test
    func theIdentityKeyIsTheScreenTheIssueTypeTheElementTypeAndTheNameWithItsPlace() {
        let issues = [Self.issue("contrast", label: ""), Self.issue("contrast", label: ""), Self.issue("trait", label: "")]
        let keys = AppleAuditIdentity.identities(of: issues, screenID: "s")

        #expect(keys[0] != keys[1])
        #expect(keys[0].place == 0 && keys[1].place == 1)
        #expect(keys[2].place == 0)
        #expect(keys[0].name == "Contrast nearly passed")
        let moved = AppleAuditIdentity.identities(of: [Self.issue("contrast", label: "", y: 900)], screenID: "s")
        #expect(moved[0] == keys[0])
    }

    // MARK: G5

    @Test
    func junitReportsAnAppleFindingAsAFailedCaseAndAMissingRecordAsSkipped() throws {
        let directory = try TemporaryDirectory()
        let found = try Self.text([Self.capture(Self.light, record: Self.record([Self.issue("contrast")]))], in: directory)
        let report = JUnitAuditCases.report(found.report, of: found.bundle)

        let failure = try #require(report.cases.first { $0.classname == "appleContrast" })
        #expect(failure.name == "you · light · General")
        #expect(failure.result == .failed("StaticText 'General' — Contrast nearly passed"))
        #expect(report.cases.contains { $0.classname == "appleTrait" && $0.result == .passed })
        #expect(report.failures == 1)

        let none = try TemporaryDirectory()
        let missing = try Self.text([Self.capture(Self.light, record: nil)], in: none)
        let skipped = JUnitAuditCases.report(missing.report, of: missing.bundle)
        #expect(skipped.skipped == 7)
        #expect(skipped.cases.contains { $0.classname == "appleContrast" && $0.result == .skipped("not recorded — \(AppleAuditSection.notRecordedReason)") })
    }

    @Test
    func anAllFailedBundleIsNeverPassingInJUnit() throws {
        let directory = try TemporaryDirectory()
        let error = #"Error Domain=x Code=-56 "Audit failed to complete in time" UserInfo={}"#
        let bundle = try Fixture.writeWalk(in: directory, screens: [
            Self.screen("root", [Self.capture(Self.light, screen: "root", record: Self.record(error: error)), Self.capture(Self.dark, screen: "root", record: Self.record(error: error))]),
            Self.screen("other", [Self.capture(Self.light, screen: "other", record: Self.record(error: error))]),
            Self.screen("gone", [Self.capture(Self.dark, screen: "gone", record: Self.record())]),
            Self.screen("bad", [Self.capture(Self.light, screen: "bad", record: Self.record())]),
        ])
        let missing = CaptureBundleLayout.appleAuditPath(screenID: "gone", stateSlug: "dark")
        try FileManager.default.removeItem(at: CaptureBundleLayout.url(forRelativePath: missing, in: bundle.url))
        try Data("{".utf8).write(to: CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.appleAuditPath(screenID: "bad", stateSlug: "light"), in: bundle.url))
        let report = try JUnitAuditCases.report(BundleAudit(bundle, rules: Self.appleRules).run(), of: bundle)

        let apple = report.cases.filter { $0.classname.hasPrefix("apple") && $0.classname != "appleAudit" }
        #expect(apple.count == 7)
        #expect(apple.allSatisfy { $0.result == .skipped("not checked — no capture's audit completed") })
        let audit = report.cases.filter { $0.classname == "appleAudit" }
        #expect(audit.contains { $0.name == "root · light, dark · audit failed" && $0.result == .failed("Audit failed to complete in time") })
        #expect(audit.contains { $0.name == "other · light · audit failed" })
        #expect(audit.contains { $0.name == missing && $0.result == .failed("unreadable — file missing") })
        #expect(audit.count == 4)
        #expect(report.failures == 4)
    }

    @Test
    func anUnknownIssueTypeIsAFailingJUnitCaseAndAnAuditedRuleStillPasses() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.text([Self.capture(Self.light, record: Self.record([Self.issue("unknown(4294967296)"), Self.issue("unknown(4294967296)", label: "B")]))], in: directory)
        let report = JUnitAuditCases.report(run.report, of: run.bundle)

        #expect(report.cases.contains { $0.classname == "appleAudit" && $0.name == "unknown(4294967296)" && $0.result == .failed("2 issues of a type no rule reads") })
        #expect(report.cases.contains { $0.classname == "appleTrait" && $0.result == .passed })
    }

    @Test
    func failedAuditsSharingAReasonAcrossScreensArePrintedOnce() throws {
        let directory = try TemporaryDirectory()
        let error = #"Error Domain=x Code=-56 "Audit failed to complete in time" UserInfo={}"#
        let bundle = try Fixture.writeWalk(in: directory, screens: [
            Self.screen("root", [Self.capture(Self.light, screen: "root", record: Self.record(error: error)), Self.capture(Self.dark, screen: "root", record: Self.record(error: "boom"))]),
            Self.screen("other", [Self.capture(Self.light, screen: "other", record: Self.record(error: error))]),
        ])
        let text = try BundleAuditSummary(BundleAudit(bundle, rules: Self.appleRules).run(), of: bundle).render()

        #expect(text.contains("apple audit: 3 captures failed, not checked there — Audit failed to complete in time: root [light], other [light]; boom: root [dark]"))
    }
}

private extension AppleAuditRuleTests {
    private struct Run {
        let text: String
        let answer: Answer
        let bundle: CaptureBundle
        let report: BundleAudit.Report
    }
}
