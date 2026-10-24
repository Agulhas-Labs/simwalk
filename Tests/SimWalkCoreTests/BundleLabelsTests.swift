//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO
@testable import SimWalkCore
import SimWalkTestSupport
import Testing
import UniformTypeIdentifiers

/// `bundle labels`: what a bundle holds, fails and lacks for each Accessibility Nutrition Label claim, over bundles whose answer is known before it is asked.
struct BundleLabelsTests {
    private static var ax3: String {
        "UICTContentSizeCategoryAccessibilityXL"
    }

    private static var ax2: String {
        "UICTContentSizeCategoryAccessibilityL"
    }

    private static var contrastSetup: String {
        "Increase Contrast enabled, found disabled (set, unverified: nothing captured reports it)"
    }

    /// A bundle with everything the claims need holds every claim it can check, and nothing is missing.
    @Test
    func aBundleWithEveryNeededStateHoldsEveryCheckableClaim() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root", "general"], states: [Self.light(), Self.dark(), Self.light(size: Self.ax3)], setup: false)

        let report = try BundleLabels(bundle).run()

        let checkable = report.claims.filter { !$0.claim.isManualOnly }

        #expect(checkable.count == 3)
        #expect(checkable.map(\.holds) == [true, true, true], "\(checkable.map(\.fails))")
        #expect(checkable.map(\.fails.count).reduce(0, +) == 0)
        #expect(checkable.map(\.missing.count) == [0, 0, 0])
        #expect(report.claims.count == 4)
    }

    /// One bundle, one claim in each state: dark holds, larger text fails, sufficient contrast is incomplete, and the colour claim is manual only.
    @Test
    func eachClaimIsHoldsFailsIncompleteOrManualOnly() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.dark(), Self.light(size: Self.ax3)], setup: true, tree: { $0.dynamicTypeSize == nil ? CaptureBundleFixture.plainScreen() : Self.overflowing() })

        let report = try BundleLabels(bundle).run()
        let summary = BundleLabelsSummary(report, of: bundle).render()

        #expect(report.claims.map(\.status) == [.fails, .holds, .incomplete, .manualOnly])
        #expect(summary.contains("[larger-text] fails"))
        #expect(summary.contains("[dark-interface] holds"))
        #expect(summary.contains("[sufficient-contrast] incomplete"))
        #expect(summary.contains("[differentiate-without-color] manual only"))
        #expect(summary.contains("1 hold, 1 fail, 1 incomplete, 1 manual only"))
    }

    /// A claim with a failure and a gap is failing: the failure is an answer already.
    @Test
    func aClaimWithFailuresAndGapsIsFails() {
        #expect(BundleLabels.ClaimReport(claim: .darkInterface, fails: ["a"], missing: ["b"]).status == .fails)
        #expect(BundleLabels.ClaimReport(claim: .darkInterface, missing: ["b"]).status == .incomplete)
        #expect(BundleLabels.ClaimReport(claim: .darkInterface).status == .holds)
    }

    /// The overflow audit's own finding, and Apple's Dynamic Type finding, count at an accessibility size and nowhere else; Apple's `textClipped` is a manual line there, not a fail.
    @Test
    func largeTypeFindingsFailLargerTextOnlyAtAnAccessibilitySize() throws {
        let directory = try TemporaryDirectory()
        let clipped = Self.issue("textClipped", description: "Text clipped")
        let bundle = try Self.bundle(
            in: directory,
            screens: ["root"],
            states: [Self.light(), Self.light(size: Self.ax3)],
            setup: true,
            tree: { _ in Self.overflowing() },
            audit: { _ in AppleAuditRecord(milliseconds: 1, issues: [clipped]) }
        )

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText]).run().claims.first)

        let slug = "light-dt_uictcontentsizecategoryaccessibilityxl"

        #expect(larger.status == .fails)
        #expect(larger.fails.count == 1, "\(larger.fails)")
        #expect(larger.fails.contains { $0.hasPrefix("root: largeTypeOverflow") && $0.hasSuffix("[\(slug)]") }, "\(larger.fails)")
        #expect(!larger.fails.contains { $0.contains("appleTextClipped") }, "\(larger.fails)")
        #expect(larger.manual.contains("Apple's audit reports 1 textClipped finding at accessibility sizes on root; its textClipped check proved unreliable, so check them by hand"), "\(larger.manual)")
    }

    /// The textClipped manual line counts findings and names every screen they are on, in the plural.
    @Test
    func textClippedFindingsOnSeveralScreensAreOneManualLineWithTheirCount() throws {
        let directory = try TemporaryDirectory()
        let clipped = Self.issue("textClipped", description: "Text clipped")
        let bundle = try Self.bundle(
            in: directory,
            screens: ["root", "general"],
            states: [Self.light(size: Self.ax3)],
            setup: true,
            audit: { _ in AppleAuditRecord(milliseconds: 1, issues: [clipped]) }
        )

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText]).run().claims.first)

        #expect(larger.manual.contains("Apple's audit reports 2 textClipped findings at accessibility sizes on root, general; its textClipped check proved unreliable, so check them by hand"), "\(larger.manual)")
    }

    /// Text drawn truncated fails Larger Text at an accessibility size only, in the overflow line's shape.
    @Test
    func truncatedTextFailsLargerTextAtAnAccessibilitySizeOnly() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })
        let recognizer = StubRecognizer(lines: [MirrorTextLine(text: "Notific...", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)], readsOnlyFromPathsContaining: "accessibility")

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: recognizer).run().claims.first)

        #expect(larger.status == .fails)
        #expect(larger.fails == ["root: truncatedText — 'Notifications' reads \"Notific...\" [light-dt_uictcontentsizecategoryaccessibilityxl]"], "\(larger.fails)")
        #expect(!larger.manual.contains { $0.hasPrefix("whether text is drawn truncated") }, "\(larger.manual)")
    }

    @Test
    func truncationBelowAnAccessibilitySizeDoesNotFailLargerText() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })
        let recognizer = StubRecognizer(lines: [MirrorTextLine(text: "Notific...", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)], readsNothingFromPathsContaining: "accessibility")

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: recognizer).run().claims.first)

        #expect(larger.fails.isEmpty, "\(larger.fails)")
    }

    /// A label drawn truncated at the default size too was not cut by the larger type: one manual line per screen, no fail.
    @Test
    func truncationThatReadsTheSameAtTheDefaultSizeIsAManualLineNotAFail() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root", "general"], states: [Self.light(), Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })
        let recognizer = StubRecognizer(lines: [MirrorTextLine(text: "Notific...", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)])

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: recognizer).run().claims.first)

        #expect(larger.fails.isEmpty, "\(larger.fails)")
        #expect(larger.manual.contains("root: 'Notifications' reads truncated at the default size too, so larger type did not cause it; check whether that is by design"), "\(larger.manual)")
        #expect(larger.manual.contains("general: 'Notifications' reads truncated at the default size too, so larger type did not cause it; check whether that is by design"), "\(larger.manual)")
    }

    /// SimWalk#219: the drawn text differs by size ("Notific..." beside "Noti..."), yet it is one control truncated at the default size too, so it stays a manual line.
    @Test
    func truncationThatReadsDifferentlyAtEachSizeIsStillAManualLineNotAFail() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })
        let recognizer = PerSizeRecognizer(accessibilityText: "Noti...", otherwiseText: "Notific...")

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: recognizer).run().claims.first)

        #expect(larger.fails.isEmpty, "\(larger.fails)")
        #expect(larger.manual.contains("root: 'Notifications' reads truncated at the default size too, so larger type did not cause it; check whether that is by design"), "\(larger.manual)")
    }

    /// A label cut at a larger non-accessibility size but whole at the default size is not by design: the default size is the only comparison that clears larger type.
    @Test
    func truncationThatAppearsAtALargerNonAccessibilitySizeButNotTheDefaultStillFails() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.light(size: "UICTContentSizeCategoryXXXL"), Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })
        let recognizer = StubRecognizer(lines: [MirrorTextLine(text: "Notific...", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)], readsOnlyFromPathsContaining: "dt_")

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: recognizer).run().claims.first)

        #expect(larger.status == .fails)
        #expect(larger.fails.contains { $0.hasPrefix("root: truncatedText — 'Notifications'") }, "\(larger.fails)")
        #expect(!larger.manual.contains { $0.contains("at the default size too") }, "\(larger.manual)")
    }

    @Test
    func severalLabelsOnOneScreenTruncatedAtTheDefaultSizeShareOneManualLine() throws {
        let directory = try TemporaryDirectory()
        let tree = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 150, height: 20), label: "Notifications"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 200, width: 150, height: 20), label: "Language"),
            ]
        )
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.light(size: Self.ax3)], setup: true, tree: { _ in tree })
        let recognizer = StubRecognizer(lines: [
            MirrorTextLine(text: "Notific...", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1),
            MirrorTextLine(text: "Langu...", centreX: 0.236, centreY: 0.240, width: 0.2, height: 0.02, confidence: 1),
        ])

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: recognizer).run().claims.first)

        #expect(larger.fails.isEmpty, "\(larger.fails)")
        #expect(larger.manual.contains("root: 'Notifications', 'Language' read truncated at the default size too, so larger type did not cause it; check whether that is by design"), "\(larger.manual)")
    }

    /// Larger Text recognises text on the accessibility-size captures, and on a smaller one only of a screen with a finding there.
    @Test
    func onlyAccessibilitySizeCapturesAreReadUnlessTheirScreenHasAFinding() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root", "general"], states: [Self.light(), Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })
        let whole = MirrorTextLine(text: "Notifications", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)
        let cut = MirrorTextLine(text: "Notific...", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)
        let clean = RecordingRecognizer(lines: [whole])
        let cutAtAccessibilitySizes = RecordingRecognizer(lines: [cut], readsOnlyFromPathsContaining: "accessibility")

        _ = try BundleLabels(bundle, claims: [.largerText], recognizer: clean).run()
        _ = try BundleLabels(bundle, claims: [.largerText], recognizer: cutAtAccessibilitySizes).run()

        #expect(clean.reads.count == 2, "\(clean.reads)")
        #expect(clean.reads.allSatisfy { $0.contains("accessibility") }, "\(clean.reads)")
        #expect(cutAtAccessibilitySizes.reads.count == 4, "\(cutAtAccessibilitySizes.reads)")
    }

    /// A smaller size's unreadable screenshot is not a gap in the claim: only the accessibility-size captures are counted as not checked.
    @Test
    func onlyAccessibilitySizeCapturesCountAsNotChecked() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })
        let whole = MirrorTextLine(text: "Notifications", centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)

        let smallerFails = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: RecordingRecognizer(lines: [whole], failsOnPathsNotContaining: "accessibility")).run().claims.first)
        let largerFails = try #require(try BundleLabels(bundle, claims: [.largerText], recognizer: RecordingRecognizer(lines: [whole], failsOnPathsContaining: "accessibility")).run().claims.first)

        #expect(!smallerFails.manual.contains { $0.hasPrefix("whether text is drawn truncated") }, "\(smallerFails.manual)")
        #expect(largerFails.manual.contains("whether text is drawn truncated on 1 capture: no readable screenshot"), "\(largerFails.manual)")
    }

    /// With no recognizer the claim says truncation was not checked, never silence.
    @Test
    func noRecognizerLeavesTruncationAManualCheck() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(size: Self.ax3)], setup: true, tree: { _ in Self.titled() })

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText]).run().claims.first)

        #expect(larger.manual.contains("whether text is drawn truncated: no text recognizer on this face, so truncatedText did not run"), "\(larger.manual)")
    }

    @Test
    func anAppleContrastFindingFailsSufficientContrast() throws {
        let directory = try TemporaryDirectory()
        let contrast = Self.issue("contrast", description: "Contrast failed")
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.dark()], setup: true, audit: { $0.theme == .light ? AppleAuditRecord(milliseconds: 1, issues: [contrast]) : AppleAuditRecord(milliseconds: 1) })

        let claim = try #require(try BundleLabels(bundle, claims: [.sufficientContrast]).run().claims.first)

        #expect(claim.status == .fails)
        #expect(claim.fails == ["root: appleContrast — StaticText 'General' — Contrast failed [light]"])
    }

    /// Two findings with no element on one screen and state print as one line with a count, and the headline still counts both.
    @Test
    func identicalFailLinesCollapseWithACountAndTheFindingCountStaysTrue() throws {
        let directory = try TemporaryDirectory()
        let nearly = Self.issue("contrast", description: "Contrast nearly passed", element: false)
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light()], setup: true, audit: { _ in AppleAuditRecord(milliseconds: 1, issues: [nearly, nearly], elementsRead: true) })

        let report = try BundleLabels(bundle, claims: [.sufficientContrast]).run()
        let claim = try #require(report.claims.first)

        #expect(claim.fails == ["root: appleContrast — Apple named no element — Contrast nearly passed ×2 [light]"])
        #expect(claim.findingCount == 2)
        #expect(BundleLabelsSummary(report, of: bundle).render().contains("2 findings"))
    }

    /// An Apple audit of the large-type capture that is unreadable or threw is not an audit of it, and advises walking again; none at all advises the flag.
    @Test
    func anUnauditedLargeTypeCaptureNamesWhatToDo() throws {
        let (first, second, third) = try (TemporaryDirectory(), TemporaryDirectory(), TemporaryDirectory())
        let unreadable = try Self.bundle(in: first, screens: ["root"], states: [Self.light(size: Self.ax3)], setup: true)
        let entry = try #require(unreadable.manifest.screens.flatMap(\.captures).first?.appleAudit)
        try Data("not json".utf8).write(to: CaptureBundleLayout.url(forRelativePath: entry.path, in: unreadable.url))
        let thrown = try Self.bundle(in: second, screens: ["root"], states: [Self.light(size: Self.ax3)], setup: true, audit: { _ in AppleAuditRecord(milliseconds: 1, error: "Error \"timed out\"") })
        let absent = try Self.bundle(in: third, screens: ["root"], states: [Self.light(size: Self.ax3)], setup: true, audit: { _ in nil })

        let manual = try [unreadable, thrown, absent].map { try #require(try BundleLabels($0, claims: [.largerText]).run().claims.first).manual.joined(separator: "\n") }

        #expect(manual[0].contains("Apple's Dynamic Type check on root: its audit of the large-type capture failed or could not be read (walk again)"))
        #expect(manual[0].contains("failed or could not be read (walk again)") && !manual[0].contains("--apple-audit"))
        #expect(manual[1].contains("failed or could not be read (walk again)") && !manual[1].contains("--apple-audit"))
        #expect(manual[2].contains("(walk with --apple-audit)") && !manual[2].contains("walk again"))
    }

    /// A screen with no capture at an accessibility size is named, with the state to add, and larger text is not held over what was captured.
    @Test
    func aBundleWithNoAccessibilitySizeNamesEachScreenAsMissing() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root", "general"], states: [Self.light(), Self.dark()], setup: true)

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText]).run().claims.first)

        #expect(!larger.holds)
        #expect(larger.evidence.isEmpty)
        #expect(larger.missing == [
            "root: add a state with \"dynamicTypeSize\": \"\(Self.ax3)\"",
            "general: add a state with \"dynamicTypeSize\": \"\(Self.ax3)\"",
        ])
    }

    /// AX2 is 194% of Body, so a capture there is named as below 200% and not counted.
    @Test
    func aCaptureAtAX2IsNamedBelowTwoHundredPercentAndNotCounted() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(size: Self.ax2)], setup: true)

        let larger = try #require(try BundleLabels(bundle, claims: [.largerText]).run().claims.first)

        #expect(!larger.holds)
        #expect(larger.evidence.isEmpty)
        #expect(larger.missing.count == 1)
        #expect(larger.missing.first?.contains("\(Self.ax2), below 200%") == true)
    }

    @Test
    func aDarkCaptureAboveTheCeilingFailsTheDarkInterface() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.dark()], setup: true, darkGrey: 0.9)

        let dark = try #require(try BundleLabels(bundle, claims: [.darkInterface]).run().claims.first)

        #expect(!dark.holds)
        #expect(dark.fails.count == 1)
        #expect(dark.fails.first?.contains("root [dark]: mean brightness 0.9") == true)
        #expect(dark.evidence.isEmpty)
    }

    /// A screenshot that would not decode was not measured, which is not a pass.
    @Test
    func aDarkScreenshotThatDoesNotDecodeIsNotMeasured() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.dark()], setup: true, darkGrey: nil)

        let dark = try #require(try BundleLabels(bundle, claims: [.darkInterface]).run().claims.first)

        #expect(!dark.holds)
        #expect(dark.evidence.isEmpty)
        #expect(dark.missing.first?.contains("not measured") == true)
    }

    /// An audit that threw checked nothing: listed as not checked, and the theme it was meant to cover is uncovered.
    @Test
    func aFailedAppleAuditIsNotCheckedAndNeverPasses() throws {
        let directory = try TemporaryDirectory()
        let failed = AppleAuditRecord(milliseconds: 1, error: "Error Domain=XCTest \"Audit failed to complete in time\"")
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.dark()], setup: true, audit: { $0.theme == .dark ? failed : AppleAuditRecord(milliseconds: 1) })

        let contrast = try #require(try BundleLabels(bundle, claims: [.sufficientContrast]).run().claims.first)

        #expect(!contrast.holds)
        #expect(contrast.missing.contains { $0.contains("root [dark]") && $0.contains("Audit failed to complete in time") && $0.contains("not checked") })
        #expect(!contrast.evidence.contains { $0.contains("dark audited") })
    }

    /// Apple's criteria ask for the ratios by default and suggest testing with Increase Contrast on as well, so a bundle walked without it can hold the claim: the second walk is a manual check, not a gap.
    @Test
    func increaseContrastNotRecordedIsAManualCheckNotAGap() throws {
        let directory = try TemporaryDirectory()
        let without = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.dark()], setup: false)

        let contrast = try #require(try BundleLabels(without, claims: [.sufficientContrast]).run().claims.first)

        #expect(contrast.missing.isEmpty)
        #expect(contrast.manual.contains { $0.contains("\"increaseContrast\": true") })
        #expect(contrast.manual.contains { $0.contains("Bold Text") })
        #expect(contrast.status == .holds)
    }

    /// Recorded, Increase Contrast is evidence, and every audit was taken with it on, so the default appearance is what is missing: such a bundle never holds the claim alone.
    @Test
    func increaseContrastRecordedIsEvidenceAndLeavesTheDefaultAppearanceMissing() throws {
        let directory = try TemporaryDirectory()
        let with = try Self.bundle(in: directory, screens: ["root"], states: [Self.light(), Self.dark()], setup: true)

        let contrast = try #require(try BundleLabels(with, claims: [.sufficientContrast]).run().claims.first)

        #expect(contrast.evidence.contains { $0.contains("every audit in this bundle was taken with Increase Contrast on") })
        #expect(!contrast.missing.contains { $0.contains("\"increaseContrast\": true") })
        #expect(contrast.missing == ["the default appearance was not audited: walk again without \"increaseContrast\" and run labels on that bundle too"])
        #expect(contrast.status == .incomplete)
    }

    @Test
    func differentiateWithoutColorIsAlwaysManual() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, screens: ["root"], states: [Self.light()], setup: true)

        let claim = try #require(try BundleLabels(bundle, claims: [.differentiateWithoutColor]).run().claims.first)

        #expect(!claim.holds)
        #expect(claim.evidence.isEmpty)
        #expect(claim.manual.count == 1)
    }

    // MARK: - Fixtures

    private static func light(size: String? = nil) -> Walkbook.CaptureState {
        Walkbook.CaptureState(theme: .light, dynamicTypeSize: size)
    }

    /// A text run that extends past the screen's width: `largeTypeOverflow` fires on it at an accessibility size.
    private static func overflowing() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 200, y: 100, width: 300, height: 20), label: "Resting heart rate")]
        )
    }

    /// A screen with one title at the top left, labelled `Notifications`.
    private static func titled() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 150, height: 20), label: "Notifications")]
        )
    }

    private static func issue(_ type: String, description: String, element: Bool = true) -> AppleAuditRecord.Issue {
        AppleAuditRecord.Issue(
            type: type,
            compactDescription: description,
            detailedDescription: "details",
            element: element ? AppleAuditRecord.Element(type: "StaticText", identifier: "", label: "General", frame: AXNode.Frame(x: 0, y: 100, width: 100, height: 20)) : nil
        )
    }

    private static func dark() -> Walkbook.CaptureState {
        Walkbook.CaptureState(theme: .dark)
    }

    /// A walk of `screens`, each captured in `states`, audited cleanly unless `audit` says otherwise, with dark screenshots of the given grey.
    private static func bundle(
        in directory: TemporaryDirectory,
        screens: [String],
        states: [Walkbook.CaptureState],
        setup: Bool,
        darkGrey: Double? = 0.1,
        tree: (Walkbook.CaptureState) -> AXNode = { _ in CaptureBundleFixture.plainScreen() },
        audit: (Walkbook.CaptureState) -> AppleAuditRecord? = { _ in AppleAuditRecord(milliseconds: 1) }
    ) throws -> CaptureBundle {
        let specs = screens.map { id in
            CaptureBundleFixture.ScreenSpec(id: id, captures: states.map {
                CaptureBundleFixture.Capture(screenID: id, state: $0, tree: tree($0), appleAudit: audit($0))
            })
        }
        var bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: specs)
        for capture in bundle.manifest.screens.flatMap(\.captures) where capture.state.theme == .dark {
            let data = try darkGrey.map { try png(grey: $0) } ?? Data("not an image".utf8)
            try data.write(to: bundle.screenshotURL(for: capture))
        }
        if setup {
            bundle = try CaptureManifest.SetupRecord(made: [contrastSetup], handedBack: [], notHandedBack: []).write(into: bundle)
        }
        return bundle
    }

    private static func png(grey: Double, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), sourceLocation: sourceLocation)
        context.setFillColor(red: grey, green: grey, blue: grey, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage(), sourceLocation: sourceLocation)
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil), sourceLocation: sourceLocation)
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), sourceLocation: sourceLocation)
        return encoded as Data
    }
}

private extension BundleLabelsTests {
    /// A recogniser that notes each screenshot it is asked to read, and can read only from, or fail on, paths containing a fragment.
    final class RecordingRecognizer: ScreenTextRecognizing, @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        let lines: [MirrorTextLine]
        var readsOnlyFromPathsContaining: String?
        var failsOnPathsContaining: String?
        var failsOnPathsNotContaining: String?

        init(lines: [MirrorTextLine], readsOnlyFromPathsContaining: String? = nil, failsOnPathsContaining: String? = nil, failsOnPathsNotContaining: String? = nil) {
            self.lines = lines
            self.readsOnlyFromPathsContaining = readsOnlyFromPathsContaining
            self.failsOnPathsContaining = failsOnPathsContaining
            self.failsOnPathsNotContaining = failsOnPathsNotContaining
        }

        var reads: [String] {
            lock.withLock { paths }
        }

        func lines(inPNGAt url: URL) throws -> [MirrorTextLine] {
            lock.withLock { paths.append(url.path) }
            if let fragment = failsOnPathsContaining, url.path.contains(fragment) {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let fragment = failsOnPathsNotContaining, !url.path.contains(fragment) {
                throw CocoaError(.fileReadCorruptFile)
            }
            if let only = readsOnlyFromPathsContaining, !url.path.contains(only) {
                return []
            }
            return lines
        }
    }

    /// A text recogniser that reads the same lines from every screenshot, except those whose path contains a fragment.
    struct StubRecognizer: ScreenTextRecognizing {
        let lines: [MirrorTextLine]
        var readsNothingFromPathsContaining: String?
        var readsOnlyFromPathsContaining: String?

        func lines(inPNGAt url: URL) throws -> [MirrorTextLine] {
            if let only = readsOnlyFromPathsContaining, !url.path.contains(only) {
                return []
            }
            guard let fragment = readsNothingFromPathsContaining else { return lines }
            return url.path.contains(fragment) ? [] : lines
        }
    }

    /// A text recogniser that reads one text from accessibility-size screenshots and another from the rest.
    struct PerSizeRecognizer: ScreenTextRecognizing {
        let accessibilityText: String
        let otherwiseText: String

        func lines(inPNGAt url: URL) throws -> [MirrorTextLine] {
            let text = url.path.contains("accessibility") ? accessibilityText : otherwiseText
            return [MirrorTextLine(text: text, centreX: 0.236, centreY: 0.126, width: 0.2, height: 0.02, confidence: 1)]
        }
    }
}
