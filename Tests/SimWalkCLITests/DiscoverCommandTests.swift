//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `simwalk discover` against a fake runner process: no simulator, no `xcodebuild`.
struct DiscoverCommandTests {
    /// An `--output` that is already there is refused before a runner is built or spawned, and left as it was.
    @Test
    func anExistingOutputIsRefusedBeforeAnySessionStarts() throws {
        let fixture = try SessionCommandTests.Fixture()
        let output = fixture.directory.url.appendingPathComponent("draft.walkbook.json")
        try Data("mine\n".utf8).write(to: output)

        #expect(throws: DiscoverError.outputExists(path: output.path)) {
            try discover(fixture, output: output)
        }

        #expect(fixture.processes.spawned.isEmpty)
        #expect(try String(contentsOf: output, encoding: .utf8) == "mine\n")
    }

    /// A discover whose environment alone injects `SIMWALK_USAGE_LOG` starts its session against that log: the progress file beside it, the runner handed it (SimWalk#196).
    @Test
    func discoverNamesTheUsageLogItsEnvironmentInjects() throws {
        let fixture = try SessionCommandTests.Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(SessionCommandTests.ready) }
        fixture.onPause = { Self.answer(fixture.channel("s1"), screen: Self.notRunning) }
        let injectedDirectory = fixture.directory.url.appendingPathComponent("injected", isDirectory: true)
        let injected = injectedDirectory.appendingPathComponent("usage.jsonl").path

        // The crawl is refused (the app is not running); what is checked was handed over when the session started.
        _ = try? discover(fixture, output: fixture.directory.url.appendingPathComponent("draft.walkbook.json"), environment: [UsageLog.overrideVariable: injected])
        let progress = try WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: ProgressLocation.progressURL(session: nil, slot: 2, in: injectedDirectory)))
        let command = try #require(fixture.processes.spawned.first)

        #expect(progress.logPath == injected)
        #expect(command.environment["TEST_RUNNER_SIMWALK_LOG"] == injected)
    }

    /// A crawl that throws still ends its session: the runner is stopped and the session removed, and the crawl's refusal is what is thrown.
    @Test
    func aCrawlThatThrowsStillEndsTheSession() throws {
        let fixture = try SessionCommandTests.Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(SessionCommandTests.ready) }
        fixture.onPause = { Self.answer(fixture.channel("s1"), screen: Self.notRunning) }
        let output = fixture.directory.url.appendingPathComponent("draft.walkbook.json")

        #expect(throws: DiscoverError.appNotRunning) {
            try discover(fixture, output: output)
        }

        #expect(fixture.processes.signalled.map(\.group) == [fixture.processes.nextPID])
        #expect(fixture.store.record(id: "s1") == nil)
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    /// The adapter's `relaunch` is a `relaunch` request, and answers with the screen the runner read.
    @Test
    func relaunchSendsARelaunchRequestAndAnswersItsScreen() throws {
        let fixture = try SessionCommandTests.Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        fixture.onPause = { Self.answer(fixture.channel("s1"), screen: SessionCommandTests.screen) }
        let record = try #require(fixture.store.record(id: "s1"))
        let session = LiveDiscoverySession(
            record: record, store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(), cancellation: nil, pause: fixture.pause, now: fixture.now
        )

        let screen = try session.relaunch()

        #expect(try fixture.channel("s1").request(1) == LiveSessionRequest(n: 1, action: .relaunch))
        #expect(screen == SessionCommandTests.screen)
    }

    /// A relaunch the runner answered with a note (it turned the device) hands the note on as `⚠ …` (SimWalk#225).
    @Test
    func relaunchPrintsTheNotesTheRunnerAnsweredWith() throws {
        let fixture = try SessionCommandTests.Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        fixture.onPause = {
            let channel = fixture.channel("s1")
            try? channel.respond(LiveSessionResponse(n: 1, action: .relaunch, screen: SessionCommandTests.screen, notes: [DeviceAlignment.note()]))
        }
        let record = try #require(fixture.store.record(id: "s1"))
        let printed = Printed()
        let session = LiveDiscoverySession(
            record: record, store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(), cancellation: nil, pause: fixture.pause, now: fixture.now, note: { printed.lines.append($0) }
        )

        _ = try session.relaunch()

        #expect(printed.lines == ["⚠ " + DeviceAlignment.note()])
    }

    /// The adapter's `scroll` is a `scroll` request carrying the direction and the box, and answers with the screen the runner read.
    @Test
    func scrollSendsAScrollRequestAndAnswersItsScreen() throws {
        let fixture = try SessionCommandTests.Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        fixture.onPause = { Self.answer(fixture.channel("s1"), screen: SessionCommandTests.screen) }
        let record = try #require(fixture.store.record(id: "s1"))
        let session = LiveDiscoverySession(
            record: record, store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(), cancellation: nil, pause: fixture.pause, now: fixture.now
        )
        let scroll = LiveSessionScroll(direction: .down, container: AXNode.Frame(x: 0, y: 100, width: 390, height: 600))

        let screen = try session.scroll(scroll)

        #expect(try fixture.channel("s1").request(1) == LiveSessionRequest(n: 1, action: .scroll, scroll: scroll))
        #expect(screen == SessionCommandTests.screen)
    }

    /// A runner that answers the scroll with a failure and no screen gives `nil`; the crawl goes on rather than throwing.
    @Test
    func aScrollTheRunnerCouldNotServeAnswersNil() throws {
        let fixture = try SessionCommandTests.Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        fixture.onPause = {
            let channel = fixture.channel("s1")
            try? channel.respond(LiveSessionResponse(n: 1, action: .scroll, failure: "the container is under 40 points tall"))
        }
        let record = try #require(fixture.store.record(id: "s1"))
        let session = LiveDiscoverySession(
            record: record, store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(), cancellation: nil, pause: fixture.pause, now: fixture.now
        )

        let screen = try session.scroll(LiveSessionScroll(direction: .up, container: AXNode.Frame(x: 0, y: 0, width: 10, height: 10)))

        #expect(screen == nil)
    }

    /// A cancelled run sends nothing more.
    @Test
    func aCancelledRunSendsNoRequest() throws {
        let fixture = try SessionCommandTests.Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        let record = try #require(fixture.store.record(id: "s1"))
        let cancellation = Cancellation()
        cancellation.cancel()
        let session = LiveDiscoverySession(
            record: record, store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(), cancellation: cancellation, pause: fixture.pause, now: fixture.now
        )

        #expect(throws: DiscoverError.cancelled) {
            try session.send(.back)
        }

        #expect(try fixture.channel("s1").request(1) == nil)
    }
}

extension DiscoverCommandTests {
    static let notRunning = LiveScreen(
        appBundleID: "com.example.live",
        device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "UDID-1", osVersion: "26.5"),
        runnerCommit: nil,
        readAt: Date(timeIntervalSince1970: 0),
        nonce: "s1",
        appState: .notRunning,
        tree: nil,
        settled: nil,
        screenPixels: LiveScreen.Pixels(width: 1206, height: 2622)
    )

    /// Answers the first unanswered request as a runner would: a `read` or `relaunch` with `screen`, an `end` with its acknowledgement and exit record.
    static func answer(_ channel: LiveSessionChannel, screen: LiveScreen) {
        for number in channel.layout.requestNumbers() {
            guard let request = try? channel.request(number), (try? channel.response(to: number)) == nil else { continue }
            switch request.action {
            case .read, .relaunch, .scroll:
                try? channel.respond(LiveSessionResponse(n: number, action: request.action, screen: screen))
            case .end:
                try? channel.respond(LiveSessionResponse(n: number, action: .end))
                try? channel.markExit(LiveSessionExit(reason: .ended, detail: "sent end", served: number, stoppedAt: Date(timeIntervalSince1970: 0)))
            case .step:
                try? channel.respond(LiveSessionResponse(n: number, action: .step, failure: "not scripted"))
            }
        }
    }

    func discover(_ fixture: SessionCommandTests.Fixture, output: URL, environment: [String: String]? = nil) throws {
        _ = try DiscoverCommand.parse(["--device", "UDID-1", "--app", "com.example.live", "--output", output.path]).perform(
            shell: Shell(script: { [script = fixture.script] in try script.run($0, $1, $2) }),
            pause: fixture.pause,
            now: fixture.now,
            id: { "s1" },
            runner: { RunnerSource(projectPath: "/runner/SimWalkRunner.xcodeproj", commit: "c0ffee", origin: .installed) },
            builds: RunnerBuilds(directory: fixture.directory.url.appendingPathComponent("runner-builds", isDirectory: true)),
            leases: fixture.leases,
            store: fixture.store,
            processes: fixture.processes,
            environment: environment ?? [UsageLog.overrideVariable: fixture.directory.url.appendingPathComponent("usage.jsonl").path]
        )
    }

    private final class Printed {
        var lines: [String] = []
    }
}
