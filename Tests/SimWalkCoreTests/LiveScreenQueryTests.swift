//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `simwalk inspect`'s answer over a live read (SimWalk#49): `bundle screen`'s listing and `--match`, a refusal when the app was not running, and the file the runner writes read back only as this run's.
struct LiveScreenQueryTests {
    @Test
    func aliveReadListsTheScreensIdentifierAndTextInAccessibilityOrder() throws {
        let answer = try LiveScreenQuery(Self.screen()).answer()

        #expect(answer.text.hasPrefix("live: app: com.example.live  runner: abc1234d  device: iPhone 18 Pro (26.0)\n"))
        #expect(answer.verdict.line.contains("live read of com.example.live — root 'WelcomeScreen', 2 text elements on screen; 1 off screen, omitted"))
        let first = try #require(answer.text.range(of: "Welcome to Health · StaticText · 16,100 370×40"))
        let second = try #require(answer.text.range(of: "Get Started · Button · 16,700 370×50"))

        #expect(first.lowerBound < second.lowerBound)
        #expect(answer.text.contains("still need a screenshot (--screenshot on this read, or screenshot: true over MCP)"))
        #expect(answer.text.contains("1 screenshot ("))
    }

    @Test
    func aScreenshotLineSitsRightAfterTheScreenLineAndNothingElseMoves() throws {
        let outcome = ScreenshotFit.Outcome.written(path: "/tmp/x.png", width: 402, height: 874, scale: 1, label: nil)
        let line = ScreenshotFit.line(outcome)
        let without = try LiveScreenQuery(Self.screen()).answer()
        let with = try LiveScreenQuery(Self.screen()).answer(screenshot: outcome)

        #expect(with.residue.first?.hasPrefix("screen ") == true)
        #expect(with.residue[1] == line)
        // Only the closing hint moves: a written screenshot is what it pointed to.
        #expect(Array(with.residue.dropFirst(2).dropLast()) == Array(without.residue.dropFirst().dropLast()))
        #expect(with.verdict == without.verdict)
    }

    /// A read of a screen whose tree has no text says its hash includes a pixel hash, on a line of its own after the screen line, so the `screen <hash>` line a guard is copied from keeps its form (SimWalk#223).
    @Test
    func aTextlessReadSaysItsHashIncludesAPixelHash() throws {
        let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let canvas = AXNode(type: "Application", frame: frame, children: [AXNode(type: "Other", frame: frame)])
        let pixels = try #require(PixelSignature(png: PixelSignatureTests.png()))

        let textless = try LiveScreenQuery(Self.screen(tree: canvas, pixels: pixels)).answer()
        let withText = try LiveScreenQuery(Self.screen()).answer()

        #expect(textless.residue.first?.split(separator: " ").count == 2)
        #expect(textless.residue[1] == "pixels: hashed (the tree has no text, so the screen hash includes a pixel hash), so a picture that moves moves the hash")
        #expect(!withText.text.contains("pixels:"))
    }

    /// A written screenshot answers the visual question, so the text no longer says it still needs one and the read is not credited with one saved.
    @Test
    func aWrittenScreenshotChangesTheHintAndWeighsNoScreenshot() throws {
        let written = ScreenshotFit.Outcome.written(path: "/tmp/x.png", width: 402, height: 874, scale: 1, label: nil)
        let refused = ScreenshotFit.Outcome.refused("the runner sent no image")

        let answer = try LiveScreenQuery(Self.screen()).answer(screenshot: written)
        let kept = try LiveScreenQuery(Self.screen()).answer(screenshot: refused)

        #expect(answer.text.contains("still need a look at the screenshot it wrote"))
        #expect(!answer.text.contains("--screenshot on this read"))
        #expect(answer.weighing == nil)
        #expect(!answer.text.contains("1 screenshot ("))
        #expect(kept.text.contains("still need a screenshot (--screenshot on this read, or screenshot: true over MCP)"))
        #expect(kept.text.contains("1 screenshot ("))
    }

    @Test
    func matchNarrowsALiveReadAsItNarrowsACapturedScreen() throws {
        let answer = try LiveScreenQuery(Self.screen()).answer(match: "start")

        #expect(answer.verdict.line.contains("1 of 2 on-screen elements match 'start'"))
        #expect(answer.text.contains("Get Started · Button"))
        #expect(!answer.text.contains("Welcome to Health"))
    }

    @Test
    func anAppNotRunningIsRefusedNamingThatNothingIsLaunched() {
        let screen = Self.screen(state: .notRunning, tree: nil)

        #expect(throws: LiveScreenError.appNotRunning(bundleID: "com.example.live", udid: "UDID-1")) { try LiveScreenQuery(screen).answer() }
        #expect(LiveScreenError.appNotRunning(bundleID: "com.example.live", udid: "UDID-1").description
            == "com.example.live is not running on UDID-1 — inspect reads the app as it stands and never launches it; bring it to the screen you want (xcrun simctl launch UDID-1 com.example.live, or a walk), then inspect again")
    }

    @Test
    func areadStillChangingIsQualifiedAndOneBroughtForwardSaysSo() throws {
        let answer = try LiveScreenQuery(Self.screen(state: .background, settled: false)).answer()

        #expect(answer.verdict.isQualified)
        #expect(answer.verdict.line.contains("1 read taken while the tree was still changing"))
        #expect(answer.verdict.line.contains("(brought forward from the background)"))
    }

    @Test
    func afileWrittenIsReadBackOnlyUnderItsOwnNonce() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("live.json")
        let screen = Self.screen()

        try screen.write(to: url)

        #expect(try LiveScreen.read(at: url, appBundleID: "com.example.live", nonce: "nonce-1") == screen)
        #expect(throws: LiveScreenError.fromAnotherRun(path: url.path)) { try LiveScreen.read(at: url, appBundleID: "com.example.live", nonce: "nonce-2") }
    }

    @Test
    func aSystemAlertSurvivesTheRoundTripAndIsAbsentWhenThereIsNone() throws {
        let alert = LiveScreen.SystemAlert(title: "Allow?", buttons: [LiveScreen.SystemAlert.Button(label: "Allow", frame: AXNode.Frame(x: 0, y: 1, width: 2, height: 3))])
        let encoder = CaptureBundle.encoder()
        let decoder = CaptureBundle.decoder()

        let with = try decoder.decode(LiveScreen.self, from: encoder.encode(Self.screen(systemAlert: alert)))
        let withoutData = try encoder.encode(Self.screen())
        let without = try decoder.decode(LiveScreen.self, from: withoutData)

        #expect(with.systemAlert == alert)
        #expect(without.systemAlert == nil)
        #expect(try !#require(String(data: withoutData, encoding: .utf8)).contains("systemAlert"))
    }

    private static func screen(state: LiveScreen.AppState = .foreground, tree: AXNode? = tree, settled: Bool? = true, systemAlert: LiveScreen.SystemAlert? = nil, pixels: PixelSignature? = nil) -> LiveScreen {
        LiveScreen(
            appBundleID: "com.example.live",
            device: CaptureManifest.Device(name: "iPhone 18 Pro", udid: "UDID-1", osVersion: "26.0"),
            runnerCommit: "abc1234def",
            readAt: Date(timeIntervalSince1970: 1_790_000_000),
            nonce: "nonce-1",
            appState: state,
            tree: tree,
            settled: tree == nil ? nil : settled,
            screenPixels: LiveScreen.Pixels(width: 1206, height: 2622),
            systemAlert: systemAlert,
            pixels: pixels
        )
    }

    private static let tree = AXNode(
        type: "Application",
        frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
        label: "Health",
        children: [
            AXNode(
                type: "Window",
                frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                identifier: "WelcomeScreen",
                children: [
                    AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 40), label: "Welcome to Health"),
                    AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 700, width: 370, height: 50), label: "Get Started"),
                    AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 1200, width: 370, height: 40), label: "Below the fold"),
                ]
            ),
        ]
    )
}
