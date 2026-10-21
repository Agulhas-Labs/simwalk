//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// A capture `truncatedText` could not check reaches the heading, the verdict and the JUnit report, so an unreadable screenshot is never read as a clean one.
struct UncheckedTruncationTests {
    private typealias Fixture = CaptureBundleFixture
    private typealias Tree = LabelTreeFixture

    private static let light = Walkbook.CaptureState(theme: .light)
    private static let dark = Walkbook.CaptureState(theme: .dark)

    private static func report(in directory: TemporaryDirectory, failingOn: String) throws -> (BundleAudit.Report, CaptureBundle) {
        let tree = Tree.screen([Tree.element("StaticText", label: "Notifications", y: 100)])
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "you", state: light, tree: tree),
            Fixture.Capture(screenID: "you", state: dark, tree: tree),
        ])
        let report = try BundleAudit(bundle, rules: [.truncatedText], recognizer: FlakyRecognizer(failingOn: failingOn)).run()
        return (report, bundle)
    }

    @Test
    func theVerdictAndTheHeadingNameTheCapturesNotChecked() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "dark")

        let text = BundleAuditSummary(report, of: bundle).render()

        #expect(text.contains("1 capture not checked by truncatedText (no screenshot read)"), "\(text)")
        #expect(text.contains("[truncatedText] clean — 1 text run examined across 2 captures; 1 capture not checked (no screenshot read)"), "\(text)")
    }

    @Test
    func aNotApplicableHeadingKeepsTheUncheckedCountAndSaysNoScreenshotCouldBeRead() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "/")

        let text = BundleAuditSummary(report, of: bundle).render()

        #expect(text.contains("[truncatedText] not applicable — no capture's screenshot could be read; 2 captures not checked (no screenshot read)"), "\(text)")
        #expect(text.contains("2 captures not checked by truncatedText (no screenshot read)"), "\(text)")
    }

    @Test
    func someCapturesUncheckedAddASkippedCaseAndTheRuleStillPasses() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "dark")

        let cases = JUnitAuditCases.report(report, of: bundle).cases

        #expect(cases.contains { $0.name == "truncatedText" && $0.result == .passed }, "\(cases)")
        #expect(cases.contains { $0.name == "truncatedText not checked" && $0.result == .skipped("1 of 2 captures not checked — no screenshot read") }, "\(cases)")
    }

    @Test
    func noCaptureCheckedMeansNoPassingCase() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "/")

        let cases = JUnitAuditCases.report(report, of: bundle).cases.filter { $0.classname == "truncatedText" }

        #expect(!cases.contains { $0.result == .passed }, "\(cases)")
        #expect(cases.contains { $0.name == "truncatedText not checked" && $0.result == .skipped("2 of 2 captures not checked — no screenshot read") }, "\(cases)")
    }
}

extension UncheckedTruncationTests {
    /// A recogniser that fails on screenshots whose path contains `failingOn` and reads the same lines from the rest.
    struct FlakyRecognizer: ScreenTextRecognizing {
        let failingOn: String
        var lines: [MirrorTextLine] = []

        func lines(inPNGAt url: URL) throws -> [MirrorTextLine] {
            if url.path.contains(failingOn) {
                throw CocoaError(.fileReadCorruptFile)
            }
            return lines
        }
    }
}
