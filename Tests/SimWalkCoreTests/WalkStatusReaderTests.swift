//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `walk_status` read from the progress files alone: the precedence table's rows 1–12 (`Docs/Reference.md`, "Bounded walks").
///
/// Also the handle grammar, the dead-process rule and the shapes of the answers. No test sleeps: the wait runs on a fake clock.
struct WalkStatusReaderTests {
    private static let startedAt = Date(timeIntervalSince1970: 1_700_000_000.123)
    private static var handle: String {
        "s@4242-1700000000123"
    }

    // MARK: Handle

    @Test
    func aHandleOfTheGrammarParsesAndPrintsAsItWasSpelled() {
        let accepted = ["default@1-2", "abc_D-1@10-20", "s.2@4242-1700000000123"]

        for text in accepted {
            #expect(WalkHandle(parsing: text)?.text == text)
        }
        #expect(WalkHandle(parsing: "s.2@4242-1700000000123")?.stem == "s.2")
        #expect(WalkHandle(parsing: Self.handle)?.pid == 4242)
        #expect(WalkHandle(parsing: Self.handle)?.startedAtMs == 1_700_000_000_123)
    }

    @Test
    func aHandleOutsideTheGrammarDoesNotParse() {
        let refused = ["", "../x@1-2", "a/b@1-2", "a@1", "a@1-2\n", "@1-2", "a.b@1-2", "a.1.2@1-2", "a@x-2", "a@1-2-3", "a b@1-2", "a@99999999999-2"]
        for text in refused {
            #expect(WalkHandle(parsing: text) == nil, "\(text)")
        }
    }

    @Test
    func theSystemProbeFindsThisProcessStartedBeforeNowAndNoProcessAtAnImpossiblePid() throws {
        let started = try #require(WalkProcessProbe.system.startTime(ProcessInfo.processInfo.processIdentifier))

        #expect(started < Date())
        #expect(WalkProcessProbe.system.startTime(Int32.max) == nil)
    }

    /// A real zombie: a child that has exited and is not yet reaped, as a server killed mid-walk is until its parent reaps it.
    @Test
    func theSystemProbeFindsNoProcessAtAZombiePid() throws {
        var pid: pid_t = 0
        let name = strdup("true")
        defer { free(name) }
        let spawned = posix_spawn(&pid, "/usr/bin/true", nil, nil, [name, nil], nil)
        try #require(spawned == 0)
        defer { _ = waitpid(pid, nil, 0) }
        var info = siginfo_t()
        try #require(waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == 0)

        #expect(WalkProcessProbe.system.startTime(pid) == nil)
    }

    // MARK: Rows 1–6

    @Test
    func row1AMalformedHandleIsRefusedBeforeTheFilesystemIsTouched() async throws {
        let fixture = try Fixture()
        let outside = fixture.directory.url.appendingPathComponent("x@1-2.json")
        try Data("{}".utf8).write(to: outside)

        let status = await fixture.status("../x@1-2")

        #expect(status == WalkStatus(text: "refused — ../x@1-2 is not a walk handle", isError: true))
    }

    @Test
    func row2NoProgressFileIsRefused() async throws {
        let fixture = try Fixture()

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — no walk s@4242-1700000000123", isError: true))
    }

    @Test
    func row3AnUnreadableFileIsRefused() async throws {
        let fixture = try Fixture()
        try fixture.writeRaw("not json")

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the progress file for s@4242-1700000000123 is unreadable", isError: true))
    }

    @Test
    func row3AFileOfAnotherSchemaIsRefusedWithItsVersion() async throws {
        let fixture = try Fixture()
        try fixture.writeRaw(#"{"schemaVersion":2,"tool":"walk"}"#)

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the progress file for s@4242-1700000000123 is schema 2, and this server reads 1", isError: true))
    }

    @Test
    func row4AFileWhosePidOrStartDiffersWasReplaced() async throws {
        let fixture = try Fixture()
        let replaced = WalkStatus(text: "refused — the walk s@4242-1700000000123 was replaced by a later run under s", isError: true)
        try fixture.write(fixture.progress(phase: .running, pid: 4243))
        #expect(await fixture.status(Self.handle) == replaced)

        try fixture.write(fixture.progress(phase: .running, startedAt: Self.startedAt.addingTimeInterval(0.001)))
        #expect(await fixture.status(Self.handle) == replaced)
    }

    @Test
    func row5ASessionIsNotAWalk() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(tool: "session", phase: .running))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — s@4242-1700000000123 is a live session, not a walk", isError: true))
    }

    @Test
    func row6AnUnfinishedWalkWhoseProcessIsGoneIsRefused() async throws {
        let fixture = try Fixture(process: .dead)
        try fixture.write(fixture.progress(phase: .building))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the walk s@4242-1700000000123 ended without finishing: the process running it exited", isError: true))
    }

    @Test
    func aReusedPidIsNotTheWalksProcess() async throws {
        let fixture = try Fixture(process: .reused)
        try fixture.write(fixture.progress(phase: .building))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the walk s@4242-1700000000123 ended without finishing: the process running it exited", isError: true))
    }

    // MARK: Row 7

    @Test
    func row7ARunningWalkWaitsTheBudgetReadingOnceASecondThenAnswersRunning() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .building))

        let status = await fixture.status(Self.handle, budget: 3.5)

        #expect(status == WalkStatus(text: "running — s@4242-1700000000123: building; call walk_status with this handle", isError: false))
        #expect(fixture.waiter.slept == [1, 1, 1, 0.5])
    }

    @Test
    func row7ALaterRowMatchedMidWaitAnswersAtOnce() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .running))
        fixture.waiter.onSleep = { count in
            if count == 2 {
                try? fixture.write(fixture.progress(phase: .failed, error: "boom"))
            }
        }

        let status = await fixture.status(Self.handle, budget: 50)

        #expect(status == WalkStatus(text: "refused — the walk s@4242-1700000000123 ended: boom", isError: true))
        #expect(fixture.waiter.slept == [1, 1])
    }

    @Test
    func row7TheProcessDyingMidWaitAnswersTheExitedRefusal() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .running))
        fixture.waiter.onSleep = { count in
            if count == 1 {
                fixture.processes.alive = false
            }
        }

        let status = await fixture.status(Self.handle, budget: 50)

        #expect(status == WalkStatus(text: "refused — the walk s@4242-1700000000123 ended without finishing: the process running it exited", isError: true))
        #expect(fixture.waiter.slept == [1])
    }

    @Test
    func row7TheBudgetReachedAnswersTheLatestRunningLine() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .running))
        fixture.waiter.onSleep = { count in
            if count == 2 {
                var later = fixture.progress(phase: .matching)
                later.matches = WalkProgress.Matches(planned: 4)
                try? fixture.write(later)
            }
        }

        let status = await fixture.status(Self.handle, budget: 2)

        #expect(status == WalkStatus(text: "running — s@4242-1700000000123: matching, 0 failed, 0 of 4 passed; call walk_status with this handle", isError: false))
    }

    // MARK: The running line

    @Test
    func theRunningLineCarriesTheStepAndCountsOnlyWhenTheFileHasThem() throws {
        let handle = try #require(WalkHandle(parsing: Self.handle))
        var progress = WalkProgress(tool: "walk", phase: .running, pid: 4242, startedAt: Self.startedAt)
        #expect(WalkStatusReader.runningLine(handle, progress) == "running — s@4242-1700000000123: running; call walk_status with this handle")

        progress.currentStep = WalkProgress.CurrentStep(index: 3, total: 12, action: "walk login", screen: "login")
        #expect(WalkStatusReader.runningLine(handle, progress) == "running — s@4242-1700000000123: running, step 3/12 login; call walk_status with this handle")

        progress.currentStep = WalkProgress.CurrentStep(index: 3, total: 12)
        progress.matches = WalkProgress.Matches(planned: 12)
        progress.matches?.failed = 1
        progress.matches?.passed = 2
        #expect(WalkStatusReader.runningLine(handle, progress) == "running — s@4242-1700000000123: running, step 3/12, 1 failed, 2 of 12 passed; call walk_status with this handle")

        progress.currentStep = WalkProgress.CurrentStep(index: 0, total: 12, screen: "login")
        progress.matches = WalkProgress.Matches(planned: 0)
        #expect(WalkStatusReader.runningLine(handle, progress) == "running — s@4242-1700000000123: running; call walk_status with this handle")

        progress.currentStep = WalkProgress.CurrentStep(index: 2, total: nil, screen: "login")
        #expect(WalkStatusReader.runningLine(handle, progress) == "running — s@4242-1700000000123: running; call walk_status with this handle")
    }

    @Test
    func aFinalPhasePrintsAsFinishing() throws {
        let handle = try #require(WalkHandle(parsing: Self.handle))

        for phase in [WalkProgress.Phase.done, .failed] {
            let progress = WalkProgress(tool: "walk", phase: phase, pid: 4242, startedAt: Self.startedAt)
            #expect(WalkStatusReader.runningLine(handle, progress) == "running — s@4242-1700000000123: finishing; call walk_status with this handle")
        }
    }

    // MARK: Rows 8–12

    @Test
    func row8APassedWalkIsOkWithItsCounts() async throws {
        let fixture = try Fixture()
        let path = try fixture.writeResult(verdict: .passed, counts: WalkResult.Counts(planned: 3, passed: 3, failed: 0))
        try fixture.write(fixture.progress(phase: .done, resultPath: path))

        let status = await fixture.status(Self.handle)

        #expect(status.text == "walk: 'smoke'  app: com.example.app  device: iPhone 17 (26.0)\nok — 0 failed, 3 of 3 matched\nresult: \(path)")
        #expect(!status.isError)
    }

    @Test
    func row8AFailedWalkIsQualifiedAndNotAnError() async throws {
        let fixture = try Fixture()
        let path = try fixture.writeResult(verdict: .failed, counts: WalkResult.Counts(planned: 3, passed: 2, failed: 1))
        try fixture.write(fixture.progress(phase: .done, resultPath: path))

        let status = await fixture.status(Self.handle)

        #expect(status.text == "walk: 'smoke'  app: com.example.app  device: iPhone 17 (26.0)\nqualified — 1 failed, 2 of 3 matched\nresult: \(path)")
        #expect(!status.isError)
    }

    @Test
    func row8ARefusedWalkCarriesTheFirstFailuresReasonAndIsAnError() async throws {
        let fixture = try Fixture()
        let failure = WalkResult.Failure(index: 1, screen: "login", kind: "buildMismatch", reason: "the app is not the build walked")
        let path = try fixture.writeResult(verdict: .refused, counts: WalkResult.Counts(planned: 3, passed: 0, failed: 3), failures: [failure])
        try fixture.write(fixture.progress(phase: .failed, resultPath: path, error: "ignored beside a result"))

        let status = await fixture.status(Self.handle)

        #expect(status.text == "walk: 'smoke'  app: com.example.app  device: iPhone 17 (26.0)\nrefused — the app is not the build walked\nresult: \(path)")
        #expect(status.isError)
    }

    @Test
    func row8AResultFileThatCannotBeReadIsRefused() async throws {
        let fixture = try Fixture()
        let path = fixture.directory.url.appendingPathComponent("missing.result.json").path
        try fixture.write(fixture.progress(phase: .done, resultPath: path))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the result file for s@4242-1700000000123 is unreadable: \(path)", isError: true))
    }

    @Test
    func row9AnEndedWalkWithAnErrorAndNoResultIsRefusedWithIt() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .failed, error: "cancelled"))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the walk s@4242-1700000000123 ended: cancelled", isError: true))
    }

    @Test
    func row10AFinishedDryRunIsOkAndNotAnError() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(tool: "walk --dry-run", phase: .done))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "ok — the dry run s@4242-1700000000123 finished; a dry run keeps no result file", isError: false))
    }

    @Test
    func row11AFinishedPhysicalDeviceWalkIsOkAndNotAnError() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .done, device: WalkProgress.Device(name: "iPhone", udid: "UDID", osVersion: "26.5", physical: true)))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "ok — the walk s@4242-1700000000123 on a physical device finished; a device walk keeps no result file", isError: false))
    }

    @Test
    func row12ASimulatorWalkWithNoResultFileIsRefused() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .done, device: WalkProgress.Device(name: "iPhone 17", udid: "UDID", osVersion: "26.5")))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the walk s@4242-1700000000123 ended but its result file was not written", isError: true))
    }

    @Test
    func row12AnEndedWalkWithNoResultFileIsRefused() async throws {
        let fixture = try Fixture()
        try fixture.write(fixture.progress(phase: .done))

        let status = await fixture.status(Self.handle)

        #expect(status == WalkStatus(text: "refused — the walk s@4242-1700000000123 ended but its result file was not written", isError: true))
    }

    @Test
    func aFinishedWalkIsAnsweredWithoutWaitingEvenWhenItsProcessIsGone() async throws {
        let fixture = try Fixture(process: .dead)
        try fixture.write(fixture.progress(phase: .done))

        _ = await fixture.status(Self.handle)

        #expect(fixture.waiter.slept.isEmpty)
    }
}

// MARK: - Fixtures

private extension WalkStatusReaderTests {
    /// A progress directory in a temporary directory that removes itself, a fake clock and a fake process table.
    struct Fixture {
        let directory: TemporaryDirectory
        let waiter = FakeWaiter()
        let processes: FakeProcesses

        init(process: FakeProcess = .alive) throws {
            directory = try TemporaryDirectory()
            processes = FakeProcesses(process: process, startedAt: WalkStatusReaderTests.startedAt)
            try FileManager.default.createDirectory(at: progressDirectory, withIntermediateDirectories: true)
        }

        var progressDirectory: URL {
            directory.url.appendingPathComponent("progress", isDirectory: true)
        }

        func status(_ handle: String, budget: TimeInterval = 50) async -> WalkStatus {
            let processes = processes
            let waiter = waiter
            let reader = WalkStatusReader(directory: directory.url, process: WalkProcessProbe { processes.startTime(of: $0) })
            return await reader.status(of: handle, budget: budget, clock: { waiter.now }, sleep: { await waiter.sleep($0) })
        }

        func progress(
            tool: String = "walk",
            phase: WalkProgress.Phase,
            pid: Int32 = 4242,
            startedAt: Date = WalkStatusReaderTests.startedAt,
            resultPath: String? = nil,
            error: String? = nil,
            device: WalkProgress.Device? = nil
        ) -> WalkProgress {
            var progress = WalkProgress(tool: tool, phase: phase, pid: pid, startedAt: startedAt)
            progress.resultPath = resultPath
            progress.error = error
            progress.device = device
            return progress
        }

        func write(_ progress: WalkProgress) throws {
            try WalkProgress.encoder().encode(progress).write(to: progressDirectory.appendingPathComponent("s.json"))
        }

        func writeRaw(_ text: String) throws {
            try Data(text.utf8).write(to: progressDirectory.appendingPathComponent("s.json"))
        }

        /// Writes `s.result.json` and returns its path.
        func writeResult(verdict: WalkResult.Verdict, counts: WalkResult.Counts, failures: [WalkResult.Failure] = []) throws -> String {
            let result = WalkResult(
                schemaVersion: 1,
                tool: "walk",
                verdict: verdict,
                walkName: "smoke",
                app: "com.example.app",
                device: WalkProgress.Device(name: "iPhone 17", udid: "UDID", osVersion: "26.0"),
                bundlePath: "/tmp/bundle",
                timings: PhaseTimings(),
                counts: counts,
                steps: [],
                failures: failures,
                truncated: WalkResult.Truncated(omittedSteps: 0)
            )
            let url = progressDirectory.appendingPathComponent("s.result.json")
            try WalkResult.encoder().encode(result).write(to: url)
            return url.path
        }
    }

    /// Where the fake pid 4242 stands against the file's `startedAt`.
    enum FakeProcess {
        case alive, dead, reused
    }

    /// A clock that only moves when it is slept on, and a hook to change the world while it does.
    final class FakeWaiter: @unchecked Sendable {
        private(set) var now: TimeInterval = 0
        private(set) var slept: [TimeInterval] = []
        var onSleep: (Int) -> Void = { _ in }

        func sleep(_ seconds: TimeInterval) async {
            slept.append(seconds)
            now += seconds
            onSleep(slept.count)
        }
    }

    /// The process table: pid 4242 only, started before, after or never relative to the file's `startedAt`.
    final class FakeProcesses: @unchecked Sendable {
        var alive: Bool
        let started: Date

        init(process: FakeProcess, startedAt: Date) {
            alive = process != .dead
            started = process == .reused ? startedAt.addingTimeInterval(60) : startedAt.addingTimeInterval(-60)
        }

        func startTime(of pid: Int32) -> Date? {
            pid == 4242 && alive ? started : nil
        }
    }
}
