//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// What the runner writes as it walks (`Docs/SIMWALK-PROGRESS.md` §2-§3): the screen in progress, the counts as each screen finishes, and the last screenshot filed.
struct WalkProgressScreenTests {
    private static let start = Date(timeIntervalSince1970: 1_790_931_600)
    private static let bundleURL = URL(fileURLWithPath: "/abs/Out.simwalk")
    private static let screens = ["home", "login", "settings"]

    /// Taking over makes the walk `running` on its first screen, and plans the screens where the host planned none.
    @Test
    func beginningScreensRunsTheFirstAndPlansTheRestWhereTheHostDidNot() {
        var progress = WalkProgress(tool: "walk", phase: .launching, pid: 1, startedAt: Self.start)
        progress.beginScreens(Self.screens)

        #expect(progress.phase == .running)
        #expect(progress.currentStep == WalkProgress.CurrentStep(index: 1, total: 3, action: "walk home", screen: "home"))
        #expect(progress.matches == WalkProgress.Matches(planned: 3))
    }

    /// The host's plan is the screens the run executes, so the runner keeps it rather than restating its own.
    @Test
    func beginningScreensKeepsTheHostsPlan() {
        var progress = WalkProgress(tool: "walk", phase: .launching, pid: 1, startedAt: Self.start)
        progress.matches = WalkProgress.Matches(planned: 5)
        progress.beginScreens(Self.screens)

        #expect(progress.matches == WalkProgress.Matches(planned: 5))
    }

    /// Each finished screen is counted under its outcome, names its first screenshot absolutely, and makes the next screen current; one that filed nothing leaves the last screenshot standing.
    @Test
    func finishingAScreenCountsItAndMovesToTheNext() {
        var progress = WalkProgress(tool: "walk", phase: .launching, pid: 1, startedAt: Self.start)
        progress.beginScreens(Self.screens)
        let home = CaptureManifest.StateCapture(screenID: "home", state: Walkbook.CaptureState(theme: .light))
        let homeShot = CaptureBundleLayout.url(forRelativePath: home.screenshotPath, in: Self.bundleURL).path

        progress.finishScreen(
            CaptureManifest.ScreenRecord(id: "home", outcome: .captured, routeTaken: [], captures: [home]),
            at: 0,
            of: Self.screens,
            in: Self.bundleURL
        )
        let afterHome = progress
        progress.finishScreen(
            CaptureManifest.ScreenRecord(id: "login", outcome: .unreachable(routeTried: [.tap(label: "Log in")]), routeTaken: []),
            at: 1,
            of: Self.screens,
            in: Self.bundleURL
        )

        #expect(afterHome.matches.map { [$0.planned, $0.passed, $0.failed, $0.pending] } == [3, 1, 0, 2])
        #expect(afterHome.currentStep == WalkProgress.CurrentStep(index: 2, total: 3, action: "walk login", screen: "login"))
        #expect(afterHome.lastScreenshotPath == homeShot)
        #expect(homeShot.hasPrefix(Self.bundleURL.path + "/"))
        #expect(progress.matches.map { [$0.planned, $0.passed, $0.failed, $0.pending] } == [3, 1, 1, 1])
        #expect(progress.currentStep?.index == 3)
        #expect(progress.lastScreenshotPath == homeShot)
    }

    /// The last screen finishing leaves it current: there is no screen after it to name.
    @Test
    func finishingTheLastScreenLeavesItCurrent() {
        var progress = WalkProgress(tool: "walk", phase: .running, pid: 1, startedAt: Self.start)
        progress.currentStep = WalkProgress.step(at: 2, of: Self.screens)
        progress.finishScreen(CaptureManifest.ScreenRecord(id: "settings", outcome: .captured, routeTaken: []), at: 2, of: Self.screens, in: Self.bundleURL)

        #expect(progress.currentStep == WalkProgress.CurrentStep(index: 3, total: 3, action: "walk settings", screen: "settings"))
        #expect(progress.matches.map { [$0.planned, $0.passed, $0.failed, $0.pending] } == [3, 1, 0, 2])
    }

    /// Read back from disk as a poller would, inside one throttle window: every screen's finish is on the file with the next screen already current.
    @Test
    func aPollerSeesEachScreenFinishAndTheNextOneStart() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let writer = ProgressWriter(url: directory.appendingPathComponent("s.json"), clock: clock.read, pid: 1)
        writer.begin(tool: "walk", phase: .launching)
        writer.commit { $0.beginScreens(Self.screens) }
        var seen: [WalkProgress] = try [Self.read(writer.url)]
        for (position, id) in Self.screens.enumerated() {
            clock.advance(0.01)
            writer.commit { $0.finishScreen(CaptureManifest.ScreenRecord(id: id, outcome: .captured, routeTaken: []), at: position, of: Self.screens, in: Self.bundleURL) }
            try seen.append(Self.read(writer.url))
        }

        #expect(seen.map(\.phase) == [.running, .running, .running, .running])
        #expect(seen.map { $0.currentStep?.index } == [1, 2, 3, 3])
        #expect(seen.map { $0.matches?.passed } == [0, 1, 2, 3])
        #expect(seen.map { $0.matches?.pending } == [3, 2, 1, 0])
    }

    private static func read(_ url: URL) throws -> WalkProgress {
        try WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: url))
    }
}
