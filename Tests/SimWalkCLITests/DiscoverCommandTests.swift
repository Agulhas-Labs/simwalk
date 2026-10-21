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
            case .read, .relaunch:
                try? channel.respond(LiveSessionResponse(n: number, action: request.action, screen: screen))
            case .end:
                try? channel.respond(LiveSessionResponse(n: number, action: .end))
                try? channel.markExit(LiveSessionExit(reason: .ended, detail: "sent end", served: number, stoppedAt: Date(timeIntervalSince1970: 0)))
            case .step:
                try? channel.respond(LiveSessionResponse(n: number, action: .step, failure: "not scripted"))
            }
        }
    }

    func discover(_ fixture: SessionCommandTests.Fixture, output: URL) throws {
        _ = try DiscoverCommand.parse(["--device", "UDID-1", "--app", "com.example.live", "--output", output.path]).perform(
            shell: Shell(script: { [script = fixture.script] in try script.run($0, $1, $2) }),
            pause: fixture.pause,
            now: fixture.now,
            id: { "s1" },
            runner: { RunnerSource(projectPath: "/runner/SimWalkRunner.xcodeproj", commit: "c0ffee", origin: .installed) },
            logFileURL: fixture.directory.url.appendingPathComponent("usage.jsonl"),
            builds: RunnerBuilds(directory: fixture.directory.url.appendingPathComponent("runner-builds", isDirectory: true)),
            leases: fixture.leases,
            store: fixture.store,
            processes: fixture.processes,
            environment: [:]
        )
    }
}
