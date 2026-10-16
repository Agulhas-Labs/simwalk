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
        #expect(answer.text.contains("still need a screenshot (xcrun simctl io UDID-1 screenshot <file>.png)"))
        #expect(answer.text.contains("1 screenshot ("))
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

    private static func screen(state: LiveScreen.AppState = .foreground, tree: AXNode? = tree, settled: Bool? = true) -> LiveScreen {
        LiveScreen(
            appBundleID: "com.example.live",
            device: CaptureManifest.Device(name: "iPhone 18 Pro", udid: "UDID-1", osVersion: "26.0"),
            runnerCommit: "abc1234def",
            readAt: Date(timeIntervalSince1970: 1_790_000_000),
            nonce: "nonce-1",
            appState: state,
            tree: tree,
            settled: tree == nil ? nil : settled,
            screenPixels: LiveScreen.Pixels(width: 1206, height: 2622)
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
