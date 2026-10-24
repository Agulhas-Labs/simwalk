//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `session start`'s half of the session's progress file (SimWalk#83): begun as `session` with no total, named for the runner once it is spawned, handed to it with its claim, and ended `failed` by a refusal or a cancel.
struct SessionStartProgressTests {
    /// A ready start leaves the file `launching` under the runner's pid — the process whose death ends the session — and hands the runner the file and the claim's descriptor.
    @Test
    func startBeginsASessionFileNamingTheRunnerAndHandsItOver() throws {
        let fixture = try SessionCommandTests.Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(SessionCommandTests.ready) }

        _ = try fixture.start(["--device", "UDID-1", "--app", "com.example.live"])
        let written = try Self.read(fixture)
        let command = try #require(fixture.processes.spawned.first)

        #expect(written.tool == "session")
        #expect(written.phase == .launching)
        #expect(written.pid == fixture.processes.nextPID)
        #expect(written.pid == fixture.store.record(id: "s1")?.pid)
        #expect(written.app == "com.example.live")
        #expect(written.currentStep == nil)
        #expect(command.environment["TEST_RUNNER_SIMWALK_PROGRESS"] == Self.url(fixture).path)
        #expect(command.inheritedDescriptor != nil)
    }

    /// A start whose environment alone injects `SIMWALK_USAGE_LOG` puts the progress file beside that log and hands the runner that same file, never the machine's own (SimWalk#196).
    @Test
    func startNamesTheUsageLogItsEnvironmentInjects() throws {
        let fixture = try SessionCommandTests.Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(SessionCommandTests.ready) }
        let injectedDirectory = fixture.directory.url.appendingPathComponent("injected", isDirectory: true)
        let injected = injectedDirectory.appendingPathComponent("usage.jsonl").path

        _ = try fixture.start(["--device", "UDID-1", "--app", "com.example.live"], environment: [UsageLog.overrideVariable: injected])
        let progress = try WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: ProgressLocation.progressURL(session: nil, slot: 2, in: injectedDirectory)))
        let command = try #require(fixture.processes.spawned.first)

        #expect(progress.logPath == injected)
        #expect(command.environment["TEST_RUNNER_SIMWALK_LOG"] == injected)
    }

    /// A runner that never becomes ready ends the start `failed`, saying why.
    @Test
    func aStartThatFailsEndsTheFileFailed() throws {
        let fixture = try SessionCommandTests.Fixture()

        #expect(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live"])
        }
        let written = try Self.read(fixture)

        #expect(written.phase == .failed)
        #expect(written.error?.contains("no ready.json") == true)
    }

    /// A cancel while the runner launches ends the file `failed` / `cancelled` and leaves the marker the runner looks for, the pid then still moving to the runner's.
    @Test
    func aCancelDuringStartEndsTheFileCancelled() throws {
        let fixture = try SessionCommandTests.Fixture()
        let cancellation = Cancellation()
        fixture.processes.onSpawn = { _ in
            cancellation.cancel()
            try? fixture.channel("s1").markReady(SessionCommandTests.ready)
        }

        _ = try SessionStartCommand.parse(["--device", "UDID-1", "--app", "com.example.live"]).perform(
            shell: Shell(script: fixture.script.run),
            pause: fixture.pause,
            now: fixture.now,
            id: { "s1" },
            runner: { RunnerSource(projectPath: "/runner/SimWalkRunner.xcodeproj", commit: "c0ffee", origin: .installed) },
            builds: RunnerBuilds(directory: fixture.directory.url.appendingPathComponent("runner-builds", isDirectory: true)),
            leases: fixture.leases,
            store: fixture.store,
            processes: fixture.processes,
            environment: [UsageLog.overrideVariable: fixture.directory.url.appendingPathComponent("usage.jsonl").path],
            cancellation: cancellation
        )
        let written = try Self.read(fixture)

        #expect(written.phase == .failed)
        #expect(written.error == "cancelled")
        #expect(written.pid == fixture.processes.nextPID)
        #expect(FileManager.default.fileExists(atPath: Self.url(fixture).path + ".cancel"))
    }

    /// With slot 1 free, a session takes slot 2: `<session>.json` stays a walk's, so a walk while the session lives lands where a mod polls (SimWalk#83).
    @Test
    func aSessionTakesSlotTwoWithSlotOneFree() throws {
        let directory = try TemporaryDirectory()

        let session = Self.start(in: directory)

        #expect(session.claim.progressURL.lastPathComponent == "s.2.json")
        #expect(session.claim.resultURL.lastPathComponent == "s.2.result.json")
    }

    /// A walk while a session holds slot 2 takes slot 1, the session's own name.
    @Test
    func aWalkBesideASessionTakesSlotOne() throws {
        let directory = try TemporaryDirectory()
        let session = Self.start(in: directory)

        let walk = ProgressClaim.take(session: "s", in: directory.url)

        #expect(walk.progressURL.lastPathComponent == "s.json")
        withExtendedLifetime(session) {}
    }

    /// Once the runner is spawned the slot is its, not the start's: a start letting go while the runner's copy of the descriptor is open leaves the slot held, and the next session takes slot 3.
    @Test
    func aSpawnedSessionKeepsItsSlotAfterTheStartLetsGo() throws {
        let directory = try TemporaryDirectory()
        var session: SessionStartProgress? = Self.start(in: directory)
        let runnersCopy = try dup(#require(session?.claim.descriptorForChild))
        defer { close(runnersCopy) }
        session?.spawned(4242)
        session = nil

        let next = Self.start(in: directory)

        #expect(next.claim.progressURL.lastPathComponent == "s.3.json")
    }

    private static func start(in directory: TemporaryDirectory) -> SessionStartProgress {
        SessionStartProgress(
            environment: [WalkCommand.sessionVariable: "s"],
            logFileURL: directory.url.appendingPathComponent("usage.jsonl"),
            cancellation: nil
        )
    }

    private static func url(_ fixture: SessionCommandTests.Fixture) -> URL {
        ProgressLocation.progressURL(session: nil, slot: 2, in: fixture.directory.url)
    }

    private static func read(_ fixture: SessionCommandTests.Fixture) throws -> WalkProgress {
        try WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: url(fixture)))
    }
}
