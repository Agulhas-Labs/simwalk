//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// `truncatedText`: text drawn cut short with an ellipsis, judged from the recognised pixels against the tree's label.
struct TruncatedTextAuditTests {
    /// A 400 x 800 screen holding one 150-point title at the top left, labelled `Notifications`.
    private static func capture(label: String = "Notifications") -> BundleAuditScope.Capture {
        let title = AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 150, height: 20), label: label)
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 800), children: [title])
        return BundleAuditScope.Capture(screenID: "settings", stateSlug: "dark-dt_uictcontentsizecategoryaccessibilityxl", tree: screen, screenshotURL: URL(fileURLWithPath: "/nonexistent/screen.png"))
    }

    /// A recognised line whose centre lies in `capture()`'s title frame unless `y` says otherwise.
    private static func line(_ text: String, x: Double = 0.2, y: Double = 0.125) -> MirrorTextLine {
        MirrorTextLine(text: text, centreX: x, centreY: y, width: 0.2, height: 0.02, confidence: 1)
    }

    private static func evaluate(_ lines: [MirrorTextLine], label: String = "Notifications") -> LabelRuleResult {
        TruncatedTextAudit(recognizer: FakeRecognizer(recognised: lines)).evaluate([capture(label: label)])
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

    @Test
    func aLineOutsideTheElementsFrameIsNotAttributedToIt() {
        let result = Self.evaluate([Self.line("Notific…", y: 0.5), Self.line("Notific…", x: 0.9)])

        #expect(result.findings.isEmpty)
    }

    @Test
    func linesOfAWrappedElementAreJoinedInReadingOrder() {
        let tall = AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 150, height: 60), label: "Background app refresh")
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 800), children: [tall])
        let capture = BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: screen, screenshotURL: URL(fileURLWithPath: "/nonexistent/screen.png"))
        let lines = [Self.line("refr…", y: 0.15), Self.line("Background app", y: 0.125)]

        let result = TruncatedTextAudit(recognizer: FakeRecognizer(recognised: lines)).evaluate([capture])

        #expect(result.findings.first?.note == "reads \"Background app refr…\"")
    }

    @Test
    func withoutARecognizerTheRuleDoesNotRunAndIsNeverClean() {
        let audit = TruncatedTextAudit(recognizer: nil)
        let captures = [Self.capture()]

        let result = audit.evaluate(captures)

        #expect(result.examined == 0)
        #expect(result.findings.isEmpty)
        #expect(audit.notApplicableReason(over: captures, result: result) == "no text recognizer on this face, so the rule did not run")
    }

    @Test
    func aCaptureWithoutAScreenshotIsCountedAsNotChecked() {
        let bare = BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: Self.capture().tree)

        let result = TruncatedTextAudit(recognizer: FakeRecognizer(recognised: [Self.line("Notific…")])).evaluate([bare, Self.capture()])

        #expect(result.unchecked == 1)
        #expect(result.findings.count == 1)
    }

    @Test
    func aRecognizerThatThrowsLeavesTheCaptureUncheckedNotClean() {
        let audit = TruncatedTextAudit(recognizer: ThrowingRecognizer())
        let captures = [Self.capture(), Self.capture()]

        let result = audit.evaluate(captures)

        #expect(result.unchecked == 2)
        #expect(result.examined == 0)
        #expect(result.findings.isEmpty)
    }

    @Test
    func theReasonComesFromTheCountsNotTheFiles() {
        let captures = [Self.capture(), Self.capture()]
        let throwing = TruncatedTextAudit(recognizer: ThrowingRecognizer())
        let reading = TruncatedTextAudit(recognizer: FakeRecognizer(recognised: []))
        let noText = BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 800)), screenshotURL: URL(fileURLWithPath: "/nonexistent/screen.png"))

        #expect(throwing.notApplicableReason(over: captures, result: throwing.evaluate(captures)) == "no capture's screenshot could be read")
        #expect(reading.notApplicableReason(over: [noText], result: reading.evaluate([noText])) == "no text runs on any screen")
        // One capture read and none of its text is a run: not every capture is unchecked.
        let mixed = [noText, BundleAuditScope.Capture(screenID: "settings", stateSlug: "light", tree: noText.tree)]
        #expect(reading.notApplicableReason(over: mixed, result: reading.evaluate(mixed)) == "no text runs on any screen")
    }
}

private extension TruncatedTextAuditTests {
    /// A recogniser whose every read fails.
    private struct ThrowingRecognizer: ScreenTextRecognizing {
        func lines(inPNGAt _: URL) throws -> [MirrorTextLine] {
            throw CocoaError(.fileReadCorruptFile)
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
