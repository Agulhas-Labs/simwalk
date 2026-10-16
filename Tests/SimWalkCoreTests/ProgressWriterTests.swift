//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The progress file's cadence and lifecycle (`Docs/SIMWALK-PROGRESS.md` §3), read back from disk after every step — what a polling reader would see, not what the writer holds.
struct ProgressWriterTests {
    private static let start = Date(timeIntervalSince1970: 1_790_931_600)

    /// Many updates inside one 500 ms window are one write; the ones it skipped ride in the next write.
    @Test
    func updatesInsideTheIntervalAreOneWriteAndTheNextWriteCarriesThem() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = FakeClock(Self.start)
        let writer = ProgressWriter(url: directory.appendingPathComponent("s.json"), clock: clock.read, pid: 1)
        writer.begin(tool: "walk")
        clock.advance(0.6)
        var seen: [WalkProgress] = []
        for index in 1 ... 10 {
            writer.update { $0.currentStep = WalkProgress.CurrentStep(index: index) }
            try seen.append(Self.read(writer.url))
            clock.advance(0.04)
        }
        let distinct = seen.map(\.currentStep).reduce(into: [WalkProgress.CurrentStep?]()) { kept, step in
            if kept.last != step {
                kept.append(step)
            }
        }
        writer.commit { $0.app = "com.example.App" }
        let committed = try Self.read(writer.url)

        #expect(distinct == [WalkProgress.CurrentStep(index: 1)])
        #expect(committed.currentStep == WalkProgress.CurrentStep(index: 10))
        #expect(committed.app == "com.example.App")
    }

    @Test
    func anUpdateIsWrittenOnceTheIntervalHasPassed() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = FakeClock(Self.start)
        let writer = ProgressWriter(url: directory.appendingPathComponent("s.json"), clock: clock.read, pid: 1)
        writer.begin(tool: "walk")
        clock.advance(0.1)
        writer.update { $0.app = "early" }
        let early = try Self.read(writer.url)
        clock.advance(0.4)
        writer.update { $0.app = "due" }

        #expect(early.app == nil)
        #expect(try Self.read(writer.url).app == "due")
    }

    /// Every phase change is written, even through `update` and inside the interval.
    @Test
    func aPhaseChangeIsWrittenThroughTheThrottle() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = FakeClock(Self.start)
        let writer = ProgressWriter(url: directory.appendingPathComponent("s.json"), clock: clock.read, pid: 1)
        writer.begin(tool: "walk")
        clock.advance(0.1)
        writer.update { $0.phase = .installing }

        #expect(try Self.read(writer.url).phase == .installing)
    }

    @Test
    func aCommitIsWrittenAtTheSameInstantAsTheWriteBeforeIt() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = FakeClock(Self.start)
        let writer = ProgressWriter(url: directory.appendingPathComponent("s.json"), clock: clock.read, pid: 1)
        writer.begin(tool: "walk")
        writer.commit { $0.matches = WalkProgress.Matches(planned: 3) }

        #expect(try Self.read(writer.url).matches == WalkProgress.Matches(planned: 3))
    }

    @Test
    func beginOverwritesTheLastRunFromBooting() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = FakeClock(Self.start)
        let writer = ProgressWriter(url: directory.appendingPathComponent("progress/s.json"), clock: clock.read, pid: 42)
        writer.begin(tool: "walk")
        writer.finish(.failed, error: "boom", resultPath: "/r.json")
        clock.advance(5)
        writer.begin(tool: "session")
        let read = try Self.read(writer.url)

        #expect(read == WalkProgress(tool: "session", phase: .booting, pid: 42, startedAt: Self.start.addingTimeInterval(5)))
    }

    @Test
    func finishWritesTheTerminalPhaseWithItsResultPath() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = ProgressWriter(url: directory.appendingPathComponent("s.json"), clock: FakeClock(Self.start).read, pid: 1)
        writer.begin(tool: "walk")
        writer.finish(.done, resultPath: "/abs/s.result.json")
        let read = try Self.read(writer.url)

        #expect(read.phase == .done)
        #expect(read.resultPath == "/abs/s.result.json")
        #expect(read.error == nil)
    }

    @Test
    func cancelWritesFailedCancelledAndLeavesAnEndedRunAlone() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ProgressWriter(url: directory.appendingPathComponent("a.json"), clock: FakeClock(Self.start).read, pid: 1)
        first.begin(tool: "walk")
        first.update { $0.phase = .running }
        first.cancel()
        let second = ProgressWriter(url: directory.appendingPathComponent("b.json"), clock: FakeClock(Self.start).read, pid: 1)
        second.begin(tool: "walk")
        second.finish(.done)
        second.cancel()

        #expect(try Self.read(first.url).phase == .failed)
        #expect(try Self.read(first.url).error == "cancelled")
        #expect(try Self.read(second.url).phase == .done)
        #expect(try Self.read(second.url).error == nil)
    }

    /// A host whose `begin` could not write — the file is the previous run's and still readable — cancels its own run, never taking the previous run's state as another writer's (SimWalk#89).
    @Test
    func aCancelAfterAFailedBeginKeepsTheNewRunsState() throws {
        let directory = try Self.scratchDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let clock = FakeClock(Self.start)
        let url = directory.appendingPathComponent("s.json")
        let previous = ProgressWriter(url: url, clock: clock.read, pid: 7)
        previous.begin(tool: "walk")
        previous.finish(.done, resultPath: "/previous.result.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        clock.advance(60)
        let writer = ProgressWriter(url: url, clock: clock.read, pid: 42)
        writer.begin(tool: "session")
        writer.cancel()

        #expect(writer.current.tool == "session")
        #expect(writer.current.pid == 42)
        #expect(writer.current.startedAt == Self.start.addingTimeInterval(60))
        #expect(writer.current.resultPath == nil)
        #expect(writer.current.error == "cancelled")
        #expect(try Self.read(url).resultPath == "/previous.result.json")
    }

    /// A cancelled MCP walk carries on, so its later writes — the host's phases, its end, and what it reloads after the runner wrote — must all keep `failed` / `cancelled` rather than make the run look alive (SimWalk#83).
    @Test
    func aCancelledRunStaysCancelledThroughEveryLaterWriteAndReload() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 1)
        host.begin(tool: "walk")
        host.cancel()
        clock.advance(1)
        host.update { $0.phase = .building }
        let afterUpdate = try Self.read(url)
        ProgressWriter.adopting(url: url, clock: clock.read).commit { $0.phase = .running }
        host.reload()
        let reloaded = host.current
        host.commit { $0.phase = .matching }
        let afterCommit = try Self.read(url)
        host.finish(.done)
        let ended = try Self.read(url)

        #expect(afterUpdate.phase == .failed)
        #expect(afterUpdate.error == "cancelled")
        #expect(reloaded.phase == .failed)
        #expect(reloaded.error == "cancelled")
        #expect(afterCommit.phase == .failed)
        #expect(afterCommit.error == "cancelled")
        #expect(ended.phase == .failed)
        #expect(ended.error == "cancelled")
    }

    /// The run object going away unfinished writes `failed` / `interrupted`.
    @Test
    func anAbandonedRunIsWrittenFailedInterrupted() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        do {
            let run = ProgressRun(writer: ProgressWriter(url: url, clock: FakeClock(Self.start).read, pid: 1))
            run.writer.begin(tool: "walk")
            run.writer.commit { $0.phase = .launching }
        }
        let read = try Self.read(url)

        #expect(read.phase == .failed)
        #expect(read.error == "interrupted")
    }

    @Test
    func aFinishedOrCancelledRunGoingAwayIsLeftAsItEnded() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let done = directory.appendingPathComponent("done.json")
        let cancelled = directory.appendingPathComponent("cancelled.json")
        do {
            let finished = ProgressRun(writer: ProgressWriter(url: done, clock: FakeClock(Self.start).read, pid: 1))
            finished.writer.begin(tool: "walk")
            finished.writer.finish(.done, resultPath: "/r.json")
            let stopped = ProgressRun(writer: ProgressWriter(url: cancelled, clock: FakeClock(Self.start).read, pid: 1))
            stopped.writer.begin(tool: "walk")
            stopped.writer.cancel()
        }

        #expect(try Self.read(done).phase == .done)
        #expect(try Self.read(done).error == nil)
        #expect(try Self.read(cancelled).error == "cancelled")
    }

    /// A run refused before it began — its writer made, then dropped or cancelled — leaves the previous run's end in place (SimWalk#83).
    @Test
    func aWriterThatNeverBeganLeavesThePreviousRunsEndAlone() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let previous = ProgressWriter(url: url, clock: FakeClock(Self.start).read, pid: 1)
        previous.begin(tool: "walk")
        previous.finish(.done, resultPath: "/r.json")
        let ended = try Self.read(url)
        do {
            let refused = ProgressRun(writer: ProgressWriter(url: url, clock: FakeClock(Self.start.addingTimeInterval(60)).read, pid: 2))
            refused.writer.cancel()
        }

        #expect(try Self.read(url) == ended)
    }

    /// The hand-over: the runner adopts what the host wrote, the host reloads what the runner wrote.
    @Test
    func theRunnerAdoptsTheHostsStateAndTheHostReloadsTheRunners() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 4242)
        host.begin(tool: "walk")
        host.commit { progress in
            progress.phase = .launching
            progress.app = "com.example.App"
        }
        let handedOver = host.current
        let runner = ProgressWriter.adopting(url: url, clock: clock.read)
        let adopted = runner.current
        clock.advance(1)
        runner.commit { progress in
            progress.phase = .running
            progress.matches = WalkProgress.Matches(planned: 2)
            progress.matches?.record(.captured)
        }
        let reloaded = host.reload()

        #expect(adopted == handedOver)
        #expect(adopted.pid == 4242)
        #expect(reloaded)
        #expect(host.current == runner.current)
        #expect(host.current.matches?.passed == 1)
    }

    @Test
    func adoptingNoFileStartsAFreshStateOwnedByThisProcess() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("missing.json")
        try Data("{ torn".utf8).write(to: directory.appendingPathComponent("torn.json"))
        let fresh = ProgressWriter.adopting(url: url, clock: FakeClock(Self.start).read)
        let unreadable = ProgressWriter.adopting(url: directory.appendingPathComponent("torn.json"), clock: FakeClock(Self.start).read)

        #expect(fresh.current == WalkProgress(tool: "walk", phase: .idle, pid: ProcessInfo.processInfo.processIdentifier, startedAt: Self.start))
        #expect(unreadable.current.phase == .idle)
        #expect(!fresh.reload())
    }

    /// Progress never fails a walk: a file that cannot be written is left unwritten, and nothing throws or traps.
    @Test
    func aWriteThatCannotHappenIsSilent() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("file")
        try Data().write(to: blocker)
        let writer = ProgressWriter(url: blocker.appendingPathComponent("progress/s.json"), clock: FakeClock(Self.start).read, pid: 1)
        writer.begin(tool: "walk")
        writer.finish(.done)

        #expect(writer.current.phase == .done)
        #expect(!FileManager.default.fileExists(atPath: writer.url.path))
    }

    static func read(_ url: URL) throws -> WalkProgress {
        try WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: url))
    }

    static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-progress-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension ProgressWriterTests {
    /// A clock a test moves by hand.
    final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var now: Date

        init(_ start: Date) {
            now = start
        }

        var read: @Sendable () -> Date {
            { [self] in lock.withLock { now } }
        }

        func advance(_ seconds: TimeInterval) {
            lock.withLock { now = now.addingTimeInterval(seconds) }
        }
    }
}
