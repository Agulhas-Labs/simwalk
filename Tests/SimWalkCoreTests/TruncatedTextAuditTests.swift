//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// `truncatedText`: text drawn cut short with an ellipsis, judged from the recognised pixels against the tree's label.
struct TruncatedTextAuditTests {
    /// A 400 x 800 screen holding one 150-point title at the top left, labelled `Notifications`.
    private static func capture(label: String = "Notifications", screenshot: URL) -> BundleAuditScope.Capture {
        let title = AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 150, height: 20), label: label)
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 800), children: [title])
        return BundleAuditScope.Capture(screenID: "settings", stateSlug: "dark-dt_uictcontentsizecategoryaccessibilityxl", tree: screen, screenshotURL: screenshot)
    }

    /// Runs `body` with a file on disk to stand for a screenshot (the fake recognisers never decode it, but the rule only asks a recogniser about a file it can read), and removes it after.
    private static func withScreenshot<Value>(_ body: (URL) -> Value) -> Value {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("truncated-text-\(UUID().uuidString).png")
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))
        defer { try? FileManager.default.removeItem(at: url) }
        return body(url)
    }

    /// A path no file is at, for a capture whose screenshot is missing.
    private static let missingScreenshot = URL(fileURLWithPath: "/nonexistent/screen.png")

    /// A recognised line whose centre lies in `capture()`'s title frame unless `y` says otherwise.
    private static func line(_ text: String, x: Double = 0.2, y: Double = 0.125) -> MirrorTextLine {
        MirrorTextLine(text: text, centreX: x, centreY: y, width: 0.2, height: 0.02, confidence: 1)
    }

    private static func evaluate(_ lines: [MirrorTextLine], label: String = "Notifications") -> LabelRuleResult {
        withScreenshot { TruncatedTextAudit(recognizer: FakeRecognizer(recognised: lines)).evaluate([capture(label: label, screenshot: $0)]) }
    }

    /// A two-line title: the frame is tall enough for both lines at y 0.1 and 0.15 of an 800-pt screen.
    private static func evaluateWrapped(_ lines: [MirrorTextLine], label: String) -> LabelRuleResult {
        let title = AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 60, width: 150, height: 80), label: label)
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 800), children: [title])
        return withScreenshot { url in
            let capture = BundleAuditScope.Capture(screenID: "timeline", stateSlug: "light", tree: screen, screenshotURL: url)
            return TruncatedTextAudit(recognizer: FakeRecognizer(recognised: lines)).evaluate([capture])
        }
    }

    @Test
    func aPrefixAndAnEllipsisOverALongerLabelFires() {
        let result = Self.evaluate([Self.line("Notific…")])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note == "reads \"Notific…\"")
        #expect(result.examined == 1)
    }

    @Test
    func theWholeLabelIsNotAFinding() {
        let result = Self.evaluate([Self.line("Notifications")])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    @Test
    func anEllipsisThatIsNotAtTheEndOfAPrefixIsNotAFinding() {
        #expect(Self.evaluate([Self.line("Notif…cations")]).findings.isEmpty)
        #expect(Self.evaluate([Self.line("Langu…")]).findings.isEmpty)
        #expect(Self.evaluate([Self.line("Notifications…")]).findings.isEmpty)
        #expect(Self.evaluate([Self.line("…")]).findings.isEmpty)
    }

    @Test
    func aLabelThatEndsInAnEllipsisOfItsOwnDrawnWholeIsNotAFinding() {
        // Settings: the label is `... Learn\u{00A0}more…` and Vision reads the drawn ellipsis as three dots.
        #expect(Self.evaluate([Self.line("Learn more...")], label: "Learn\u{00A0}more…").findings.isEmpty)
        #expect(Self.evaluate([Self.line("Learn…")], label: "Learn\u{00A0}more…").findings.count == 1)
    }

    @Test
    func threeDotsAreAnEllipsisToo() {
        let result = Self.evaluate([Self.line("Notific...")])

        #expect(result.findings.count == 1)
    }

    /// The recogniser reads a headline's curly quotes and apostrophes as straight ones (SimWalk#232); it does not pin which mark the label uses elsewhere.
    @Test
    func aStraightQuoteReadOverACurlyQuoteLabelFires() {
        let label = "The Verge’s Duo Review: ‘Apple’s Folding Phone Is a Messy, Expensive Good Time’"
        let lines = [Self.line("The Verge's Duo", y: 0.1), Self.line("Review: 'Apple's Fo...", y: 0.15)]

        let result = Self.evaluateWrapped(lines, label: label)

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note == "reads \"The Verge's Duo Review: 'Apple's Fo...\"")
    }

    /// A row's unread dot read into the first line of its title (SimWalk#232); it does not pin a mark other than `•`.
    @Test
    func anUnreadDotReadIntoTheTitlesFirstLineStillFires() {
        let label = "How We Got Duo Support in NetNewsWire for iOS"
        let lines = [Self.line("• How We Got Duo", y: 0.1), Self.line("Support in NetNew...", y: 0.15)]

        let result = Self.evaluateWrapped(lines, label: label)

        #expect(result.findings.count == 1)
    }

    @Test
    func aCurlyQuoteReadOverAStraightQuoteLabelFires() {
        let result = Self.evaluate([Self.line("It’s a long ti…")], label: "It's a long time to wait")

        #expect(result.findings.count == 1)
    }

    @Test
    func aReadThatDiffersAfterQuoteFoldingIsNotAFinding() {
        let result = Self.evaluate([Self.line("It's a lone ti…")], label: "It’s a long time to wait")

        #expect(result.findings.isEmpty)
    }

    @Test
    func aLineOutsideTheElementsFrameIsNotAttributedToIt() {
        let result = Self.evaluate([Self.line("Notific…", y: 0.5), Self.line("Notific…", x: 0.9)])

        #expect(result.findings.isEmpty)
    }

    @Test
    func linesOfAWrappedElementAreJoinedInReadingOrder() {
        let tall = AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 150, height: 60), label: "Background app refresh")
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 800), children: [tall])
        let lines = [Self.line("refr…", y: 0.15), Self.line("Background app", y: 0.125)]

        let result = Self.withScreenshot { url in
            let capture = BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: screen, screenshotURL: url)
            return TruncatedTextAudit(recognizer: FakeRecognizer(recognised: lines)).evaluate([capture])
        }

        #expect(result.findings.first?.note == "reads \"Background app refr…\"")
    }

    @Test
    func withoutARecognizerTheRuleDoesNotRunAndIsNeverClean() {
        let audit = TruncatedTextAudit(recognizer: nil)
        let captures = [Self.capture(screenshot: Self.missingScreenshot)]

        let result = audit.evaluate(captures)

        #expect(result.examined == 0)
        #expect(result.findings.isEmpty)
        #expect(audit.notApplicableReason(over: captures, result: result) == "no text recognizer on this face, so the rule did not run")
    }

    @Test
    func aCaptureWithoutAScreenshotIsCountedAsNotChecked() {
        let bare = BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: Self.capture(screenshot: Self.missingScreenshot).tree)

        let result = Self.withScreenshot { TruncatedTextAudit(recognizer: FakeRecognizer(recognised: [Self.line("Notific…")])).evaluate([bare, Self.capture(screenshot: $0)]) }

        #expect(result.unchecked == 1)
        #expect(result.recognitionFailed == 0)
        #expect(result.findings.count == 1)
    }

    @Test
    func aScreenshotThatIsNotThereIsNoScreenshotReadWhateverTheRecognizerWouldSay() {
        let audit = TruncatedTextAudit(recognizer: ThrowingRecognizer())
        let captures = [Self.capture(screenshot: Self.missingScreenshot), Self.capture(screenshot: Self.missingScreenshot)]

        let result = audit.evaluate(captures)

        #expect(result.unchecked == 2)
        #expect(result.recognitionFailed == 0)
        #expect(result.recognitionFailure == nil)
        #expect(audit.notApplicableReason(over: captures, result: result) == "no capture's screenshot could be read")
    }

    @Test
    func aRecognizerThatThrowsOnReadableFilesLeavesTheCapturesUncheckedAndKeepsTheFirstCause() {
        Self.withScreenshot { url in
            let audit = TruncatedTextAudit(recognizer: ThrowingRecognizer())
            let captures = [Self.capture(screenshot: url), Self.capture(screenshot: url)]

            let result = audit.evaluate(captures)

            #expect(result.unchecked == 2)
            #expect(result.recognitionFailed == 2)
            #expect(result.examined == 0)
            #expect(result.findings.isEmpty)
            #expect(result.recognitionFailure == "busy")
            #expect(audit.notApplicableReason(over: captures, result: result) == "text recognition failed on every capture (busy)")
        }
    }

    @Test
    func anErrorWithoutACauseIsDescribed() {
        Self.withScreenshot { url in
            let result = TruncatedTextAudit(recognizer: PlainThrowingRecognizer()).evaluate([Self.capture(screenshot: url)])

            #expect(result.recognitionFailure == String(describing: PlainFailure.broken))
        }
    }

    @Test
    func theReasonComesFromTheCountsNotTheFiles() {
        let reading = TruncatedTextAudit(recognizer: FakeRecognizer(recognised: []))
        Self.withScreenshot { url in
            let noText = BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 800)), screenshotURL: url)
            #expect(reading.notApplicableReason(over: [noText], result: reading.evaluate([noText])) == "no text runs on any screen")
            // One capture read and none of its text is a run: not every capture is unchecked.
            let mixed = [noText, BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: noText.tree)]
            #expect(reading.notApplicableReason(over: mixed, result: reading.evaluate(mixed)) == "no text runs on any screen")
        }
    }
}

private extension TruncatedTextAuditTests {
    /// A recognition failure that names its cause.
    private struct Busy: ScreenTextRecognitionFailure {
        let cause = "busy"
    }

    /// An error that is not a `ScreenTextRecognitionFailure`.
    private enum PlainFailure: Error {
        case broken
    }

    /// A recogniser whose every read fails, saying why.
    private struct ThrowingRecognizer: ScreenTextRecognizing {
        func lines(inPNGAt _: URL) throws -> [MirrorTextLine] {
            throw Busy()
        }
    }

    /// A recogniser whose every read fails with an error that carries no cause.
    private struct PlainThrowingRecognizer: ScreenTextRecognizing {
        func lines(inPNGAt _: URL) throws -> [MirrorTextLine] {
            throw PlainFailure.broken
        }
    }

    /// A recogniser that answers the same lines for every screenshot.
    private struct FakeRecognizer: ScreenTextRecognizing {
        let recognised: [MirrorTextLine]

        func lines(inPNGAt _: URL) throws -> [MirrorTextLine] {
            recognised
        }
    }
}
