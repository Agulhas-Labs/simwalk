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

    /// The bundle of two captures of `you` (light, dark) audited by a recogniser failing on paths containing `failingOn`; `removing` deletes the screenshots of those states first, so they have none to read.
    private static func report(in directory: TemporaryDirectory, failingOn: String, removing missing: [String] = []) throws -> (BundleAudit.Report, CaptureBundle) {
        let tree = Tree.screen([Tree.element("StaticText", label: "Notifications", y: 100)])
        let bundle = try Fixture.write(in: directory, captures: [
            Fixture.Capture(screenID: "you", state: light, tree: tree),
            Fixture.Capture(screenID: "you", state: dark, tree: tree),
        ])
        for screen in bundle.manifest.screens {
            for capture in screen.captures where missing.contains(where: { bundle.screenshotURL(for: capture).path.contains($0) }) {
                try FileManager.default.removeItem(at: bundle.screenshotURL(for: capture))
            }
        }
        let report = try BundleAudit(bundle, rules: [.truncatedText], recognizer: FlakyRecognizer(failingOn: failingOn)).run()
        return (report, bundle)
    }

    @Test
    func theVerdictAndTheHeadingNameTheCapturesNotChecked() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "dark")

        let text = BundleAuditSummary(report, of: bundle).render()

        #expect(text.contains("1 capture not checked by truncatedText (recognition failed: busy)"), "\(text)")
        #expect(text.contains("[truncatedText] clean — 1 on-screen text run and 0 drawn lines outside it examined across 2 captures; 1 capture not checked (recognition failed: busy)"), "\(text)")
    }

    @Test
    func aNotApplicableHeadingKeepsTheUncheckedCountAndSaysNoScreenshotCouldBeRead() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "never", removing: ["/"])

        let text = BundleAuditSummary(report, of: bundle).render()

        #expect(text.contains("[truncatedText] not applicable — no capture's screenshot could be read; 2 captures not checked (no screenshot read)"), "\(text)")
        #expect(text.contains("2 captures not checked by truncatedText (no screenshot read)"), "\(text)")
    }

    @Test
    func recognitionFailingOnEveryReadableCaptureNamesTheCauseAndWhatToRunAgain() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "/")

        let text = BundleAuditSummary(report, of: bundle).render()

        #expect(text.contains("[truncatedText] not applicable — text recognition failed on every capture (busy); the screenshots are there, so run the audit again rather than the walk; 2 captures not checked (recognition failed)"), "\(text)")
        #expect(text.contains("2 captures not checked by truncatedText (recognition failed: busy)"), "\(text)")
    }

    @Test
    func aMixOfMissingScreenshotsAndFailedRecognitionSplitsTheCount() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "dark", removing: ["light"])

        let text = BundleAuditSummary(report, of: bundle).render()
        let cases = JUnitAuditCases.report(report, of: bundle).cases

        #expect(text.contains("; 2 captures not checked (1 no screenshot read, 1 recognition failed: busy)"), "\(text)")
        #expect(text.contains("2 captures not checked by truncatedText (1 no screenshot read, 1 recognition failed: busy)"), "\(text)")
        #expect(cases.contains { $0.name == "truncatedText not checked" && $0.result == .skipped("2 of 2 captures not checked — 1 no screenshot read, 1 recognition failed: busy") }, "\(cases)")
    }

    @Test
    func someCapturesUncheckedAddASkippedCaseAndTheRuleStillPasses() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "dark")

        let cases = JUnitAuditCases.report(report, of: bundle).cases

        #expect(cases.contains { $0.name == "truncatedText" && $0.result == .passed }, "\(cases)")
        #expect(cases.contains { $0.name == "truncatedText not checked" && $0.result == .skipped("1 of 2 captures not checked — recognition failed: busy") }, "\(cases)")
    }

    @Test
    func noCaptureCheckedMeansNoPassingCase() throws {
        let directory = try TemporaryDirectory()
        let (report, bundle) = try Self.report(in: directory, failingOn: "never", removing: ["/"])

        let cases = JUnitAuditCases.report(report, of: bundle).cases.filter { $0.classname == "truncatedText" }

        #expect(!cases.contains { $0.result == .passed }, "\(cases)")
        #expect(cases.contains { $0.name == "truncatedText not checked" && $0.result == .skipped("2 of 2 captures not checked — no screenshot read") }, "\(cases)")
    }
}

extension UncheckedTruncationTests {
    /// A recognition failure naming its cause.
    struct Busy: ScreenTextRecognitionFailure {
        let cause = "busy"
    }

    /// A recogniser that fails on screenshots whose path contains `failingOn` and reads the same lines from the rest.
    struct FlakyRecognizer: ScreenTextRecognizing {
        let failingOn: String
        var lines: [MirrorTextLine] = []

        func lines(inPNGAt url: URL) throws -> [MirrorTextLine] {
            if url.path.contains(failingOn) {
                throw Busy()
            }
            return lines
        }
    }
}
