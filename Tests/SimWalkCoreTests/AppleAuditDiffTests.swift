//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle diff` over Apple's accessibility-audit records (E1b): an issue the run has and the reference lacks is a flag, by identity and never frame.
struct AppleAuditDiffTests {
    private typealias Fixture = CaptureBundleFixture
    private typealias Tree = LabelTreeFixture

    private static let light = Walkbook.CaptureState(theme: .light)
    private static let dark = Walkbook.CaptureState(theme: .dark)

    private static func issue(_ type: String = "contrast", label: String = "General", elementType: String? = "StaticText", description: String = "Contrast nearly passed", y: Double = 100) -> AppleAuditRecord.Issue {
        AppleAuditRecord.Issue(
            type: type,
            compactDescription: description,
            detailedDescription: "details",
            element: elementType.map { AppleAuditRecord.Element(type: $0, identifier: "", label: label, frame: AXNode.Frame(x: 0, y: y, width: 100, height: 20)) }
        )
    }

    private static func record(_ issues: [AppleAuditRecord.Issue] = [], error: String? = nil, elementsRead: Bool? = nil) -> AppleAuditRecord {
        AppleAuditRecord(milliseconds: 1500, error: error, issues: issues, elementsRead: elementsRead)
    }

    private static func capture(_ state: Walkbook.CaptureState, _ record: AppleAuditRecord?) -> Fixture.Capture {
        Fixture.Capture(screenID: "root", state: state, tree: Tree.screen([Tree.element("Button", label: "Save", y: 100)]), appleAudit: record)
    }

    private static func diff(reference: [AppleAuditRecord?], run: [AppleAuditRecord?]) throws -> BundleDiff {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let states = [light, dark]
        let referenceBundle = try Fixture.write(in: referenceDirectory, captures: zip(states, reference).map { capture($0, $1) })
        let runBundle = try Fixture.write(in: runDirectory, captures: zip(states, run).map { capture($0, $1) })
        return BundleDiff.compare(run: runBundle, against: referenceBundle)
    }

    private static func lines(_ diff: BundleDiff) -> [String] {
        (diff.screens.first.map(BundleDiffRendering.appleLines) ?? []) + BundleDiffRendering.appleBundleLine(diff)
    }

    // MARK: G1

    @Test
    func aBundleAgainstItselfFlagsNothing() throws {
        let directory = try TemporaryDirectory()
        let records = [Self.record([Self.issue(), Self.issue("hitRegion", label: "Edit")]), Self.record([Self.issue(description: "Contrast failed")])]
        let bundle = try Fixture.write(in: directory, captures: zip([Self.light, Self.dark], records).map { Self.capture($0, $1) })
        let diff = BundleDiff.compare(run: bundle, against: bundle)

        #expect(diff.flagCount == 0)
        #expect(diff.screens.first?.appleFlags == [])
        #expect(diff.screens.first?.appleNotes == nil)
        #expect(Self.lines(diff).isEmpty)
    }

    // MARK: G2

    @Test
    func aNewIssueIsOneFlagWithTheExactLine() throws {
        let diff = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record([Self.issue()]), Self.record()])

        #expect(diff.flagCount == 1)
        #expect(Self.lines(diff) == ["  apple  appleContrast  root/light: StaticText 'General' — Contrast nearly passed, not in reference"])
    }

    @Test
    func anIssueWithNoElementAndOneOfATypeNoRuleReadsAreNamedPlainly() throws {
        let diff = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record([Self.issue("unknown(99)", elementType: nil, description: "Odd")]), Self.record()])

        #expect(Self.lines(diff) == ["  apple  unknown(99)  root/light: (no element) — Odd, not in reference"])
    }

    @Test
    func aFlagSaysWhyThereIsNoElementAsFarAsTheRecordCanTell() throws {
        let bare = Self.issue(elementType: nil)
        var lost = bare
        lost.elementUnreadable = "snapshot failed"
        let old = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record([bare]), Self.record()])
        let none = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record([bare], elementsRead: true), Self.record()])
        let unreadable = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record([lost], elementsRead: true), Self.record()])

        #expect(Self.lines(old) == ["  apple  appleContrast  root/light: (no element) — Contrast nearly passed, not in reference"])
        #expect(Self.lines(none) == ["  apple  appleContrast  root/light: Apple named no element — Contrast nearly passed, not in reference"])
        #expect(Self.lines(unreadable) == ["  apple  appleContrast  root/light: the element could not be read after the audit (snapshot failed) — Contrast nearly passed, not in reference"])
    }

    @Test
    func anIssueWithAnUnreadableElementIsTheSameIssueAsOneWithNoElementInTheReference() throws {
        let bare = Self.issue(elementType: nil)
        var lost = bare
        lost.elementUnreadable = "snapshot failed"
        let diff = try Self.diff(reference: [Self.record([bare]), Self.record()], run: [Self.record([lost]), Self.record()])

        #expect(diff.flagCount == 0)
    }

    @Test
    func theSameIssueAtAnotherFrameIsNoFlag() throws {
        let diff = try Self.diff(reference: [Self.record([Self.issue(y: 100)]), Self.record()], run: [Self.record([Self.issue(y: 640)]), Self.record()])

        #expect(diff.flagCount == 0)
        #expect(Self.lines(diff).isEmpty)
    }

    @Test
    func aDescriptionChangeOnOneElementIsOneFlag() throws {
        let diff = try Self.diff(reference: [Self.record([Self.issue(description: "Contrast nearly passed")]), Self.record()], run: [Self.record([Self.issue(description: "Contrast failed")]), Self.record()])

        #expect(diff.flagCount == 1)
        #expect(Self.lines(diff) == ["  apple  appleContrast  root/light: StaticText 'General' — Contrast failed, not in reference"])
    }

    @Test
    func twoEqualIssuesInTheRunAgainstOneInTheReferenceAreOneFlag() throws {
        let diff = try Self.diff(reference: [Self.record([Self.issue()]), Self.record()], run: [Self.record([Self.issue(y: 10), Self.issue(y: 20)]), Self.record()])

        #expect(diff.flagCount == 1)
    }

    @Test
    func anIssueOnlyTheReferenceHasIsNotAFlag() throws {
        let diff = try Self.diff(reference: [Self.record([Self.issue()]), Self.record()], run: [Self.record(), Self.record()])

        #expect(diff.flagCount == 0)
        #expect(diff.screens.first?.appleFlags == [])
    }

    // MARK: G3

    @Test
    func neitherSideAuditedPrintsNothingAndStoresNothing() throws {
        let diff = try Self.diff(reference: [nil, nil], run: [nil, nil])
        let screen = try #require(diff.screens.first)

        #expect(screen.appleFlags == nil)
        #expect(screen.appleNotes == nil)
        #expect(diff.appleNotAudited == nil)
        #expect(Self.lines(diff).isEmpty)
    }

    @Test(arguments: [(true, "reference"), (false, "run")])
    func oneSideAuditedAtAllIsOneBundleLevelLine(referenceAudited: Bool, missing: String) throws {
        let audited: [AppleAuditRecord?] = [Self.record([Self.issue()]), Self.record()]
        let diff = try Self.diff(reference: referenceAudited ? [nil, nil] : audited, run: referenceAudited ? audited : [nil, nil])

        #expect(Self.lines(diff) == ["apple audit: not compared — the \(missing) was not audited"])
        #expect(diff.screens.first?.appleFlags == nil)
        #expect(diff.screens.first?.appleNotes == nil)
        #expect(diff.flagCount == 0)
    }

    @Test
    func aStateWhoseAuditFailedIsOneNoteAndTheOtherStateIsStillCompared() throws {
        let diff = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record(error: "timed out"), Self.record([Self.issue()])])

        #expect(Self.lines(diff) == [
            "  apple  appleContrast  root/dark: StaticText 'General' — Contrast nearly passed, not in reference",
            "  root/light: apple audit not compared: the run's audit failed",
        ])
        #expect(diff.flagCount == 1)
    }

    @Test
    func aStateNotAuditedOnOneSideOfAnAuditedPairIsANote() throws {
        let diff = try Self.diff(reference: [nil, Self.record()], run: [Self.record(), Self.record()])

        #expect(Self.lines(diff) == ["  root/light: apple audit not compared: the reference has no audit record"])
    }

    // MARK: G4

    @Test
    func junitReportsAnAppleFlagAsAFailedCaseAndACleanStateAsPassed() throws {
        let diff = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record([Self.issue()]), Self.record()])
        let cases = JUnitDiffCases.report(diff).cases

        let failed = cases.filter {
            if case .failed = $0.result {
                true
            } else {
                false
            }
        }

        #expect(failed.map(\.name) == ["light · apple · appleContrast · StaticText 'General'"])
        #expect(failed.map(\.classname) == ["root"])
        #expect(cases.contains { $0.name == "dark" && $0.result == .passed })
        #expect(!cases.contains { $0.name == "light" })
    }

    // MARK: Review fixes (E1b)

    private static func summary(reference: [AppleAuditRecord?], run: [AppleAuditRecord?]) throws -> (text: String, verdict: String) {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let states = [light, dark]
        let referenceBundle = try Fixture.write(in: referenceDirectory, captures: zip(states, reference).map { capture($0, $1) })
        let runBundle = try Fixture.write(in: runDirectory, captures: zip(states, run).map { capture($0, $1) })
        let diff = BundleDiff.compare(run: runBundle, against: referenceBundle)
        let text = BundleDiffSummary(diff, reference: referenceBundle, run: runBundle).answer().text
        let verdict = text.components(separatedBy: "\n").first { $0.hasPrefix("ok") || $0.hasPrefix("qualified") } ?? ""
        return (text, verdict)
    }

    @Test
    func statesWhoseAuditsWereNotComparedQualifyTheVerdict() throws {
        let failed = Self.record(error: "timed out")
        let (text, verdict) = try Self.summary(reference: [failed, failed], run: [failed, failed])

        #expect(verdict.hasPrefix("qualified — 2 states' Apple audits not compared"))
        #expect(text.contains("  root/light: apple audit not compared: both sides' audits failed"))
    }

    @Test
    func oneStateNotComparedIsSingular() throws {
        let (_, verdict) = try Self.summary(reference: [Self.record(), Self.record()], run: [Self.record(error: "x"), Self.record()])

        #expect(verdict.hasPrefix("qualified — 1 state's Apple audits not compared"))
    }

    @Test
    func aBundleAuditedOnOneSideOnlyQualifiesWithEveryPairedStateAndPrintsTheBundleLine() throws {
        let (text, verdict) = try Self.summary(reference: [Self.record(), Self.record()], run: [nil, nil])

        #expect(verdict.hasPrefix("qualified — 2 states' Apple audits not compared"))
        #expect(text.components(separatedBy: "\n").contains("apple audit: not compared — the run was not audited"))
    }

    @Test
    func neitherSideAuditedAddsNoClause() throws {
        let (_, verdict) = try Self.summary(reference: [nil, nil], run: [nil, nil])

        #expect(verdict.hasPrefix("ok"))
    }

    @Test
    func junitSkipsEachStateWhoseAuditsWereNotComparedAndKeepsItsOtherCases() throws {
        let failed = Self.record(error: "timed out")
        let diff = try Self.diff(reference: [failed, Self.record()], run: [failed, Self.record()])
        let cases = JUnitDiffCases.report(diff).cases
        let skipped = cases.filter { $0.name == "light · apple · not compared" }

        #expect(skipped.map(\.classname) == ["root"])
        #expect(skipped.map(\.result) == [.skipped("apple audit not compared — both sides' audits failed")])
        #expect(cases.contains { $0.name == "light" && $0.result == .passed })
        #expect(!cases.contains { $0.name.hasPrefix("dark · apple") })
    }

    @Test
    func junitSkipsEveryPairedStateWhenOneBundleWasNotAudited() throws {
        let diff = try Self.diff(reference: [nil, nil], run: [Self.record(), Self.record()])
        let skipped = JUnitDiffCases.report(diff).cases.filter { $0.name.hasSuffix("· apple · not compared") }

        #expect(skipped.map(\.name) == ["light · apple · not compared", "dark · apple · not compared"])
        #expect(skipped.allSatisfy { $0.result == .skipped("apple audit not compared — the reference was not audited") })
    }

    @Test
    func aFailedRecordWithIssuesStaysOutOfTheDiff() throws {
        let diff = try Self.diff(reference: [Self.record(), Self.record()], run: [Self.record([Self.issue()], error: "timed out"), Self.record()])

        #expect(diff.flagCount == 0)
        #expect(Self.lines(diff) == ["  root/light: apple audit not compared: the run's audit failed"])
    }

    @Test
    func bothSidesUnreadableIsOneNoteAndMixedReasonsNameEachSide() throws {
        let failed = Self.record(error: "x")
        let mixed = try Self.diff(reference: [nil, Self.record()], run: [failed, Self.record()])

        #expect(Self.lines(mixed) == ["  root/light: apple audit not compared: the reference has no audit record; the run's audit failed"])
    }

    @Test
    func anEntryWhoseFileIsMissingIsNotedUnreadable() throws {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let records = [Self.record(), Self.record()]
        let referenceBundle = try Fixture.write(in: referenceDirectory, captures: zip([Self.light, Self.dark], records).map { Self.capture($0, $1) })
        let runBundle = try Fixture.write(in: runDirectory, captures: zip([Self.light, Self.dark], records).map { Self.capture($0, $1) })
        let entry = try #require(runBundle.manifest.screens.first?.captures.first?.appleAudit)
        try FileManager.default.removeItem(at: CaptureBundleLayout.url(forRelativePath: entry.path, in: runBundle.url))
        let diff = BundleDiff.compare(run: runBundle, against: referenceBundle)

        #expect(Self.lines(diff) == ["  root/light: apple audit not compared: the run's audit record could not be read"])
    }
}
