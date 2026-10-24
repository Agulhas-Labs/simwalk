//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The recorder a `--parallel` walk's marks and its one `walk.parallel` line go through, driven from two threads at once as an interruption's handler and the walk's own end drive it.
struct ShardTimingRecorderTests {
    /// SimWalk#189: of two writers at once, the first writes the line and the second writes none and does not return until the first's line is on disk — an interruption's handler that returned earlier would let the signal end the process with the line unwritten.
    ///
    /// The first writer is held inside its write, at the usage log's clock read, until the second has returned, so a second that does not wait returns with the file still empty. One that waits is blocked on the recorder's lock, so the hold ends at ``hold`` instead: that bound is the only time the test waits on, and it is long enough for a second that does not wait to have returned, not an ordering a pass depends on.
    @Test
    func theSecondOfTwoWritersWritesNothingAndReturnsOnlyOnceTheFirstsLineIsOnDisk() throws {
        let directory = try TemporaryDirectory()
        let logURL = directory.url.appendingPathComponent("usage.jsonl")
        let telemetry = WalkTelemetry(writer: ProgressWriter(url: directory.url.appendingPathComponent("progress.json"), clock: { Date() }, pid: 1), resultURL: nil, clock: { 1 })
        telemetry.begin(tool: "walk")
        let recorder = try #require(ShardTimingRecorder(telemetry: telemetry, shards: []))
        let race = Race()
        let held = UsageLog(fileURL: logURL, now: {
            race.firstInWrite.signal()
            _ = race.secondStarted.wait(timeout: .now() + Self.hangGuard)
            _ = race.secondReturned.wait(timeout: .now() + Self.hold)
            return Date()
        })
        let plain = UsageLog(fileURL: logURL, now: { Date() })
        let finished = DispatchGroup()

        DispatchQueue.global().async(group: finished) {
            recorder.writeLine(to: held, target: nil, succeeded: false, error: "interrupted")
        }
        _ = race.firstInWrite.wait(timeout: .now() + Self.hangGuard)
        DispatchQueue.global().async(group: finished) {
            race.secondStarted.signal()
            recorder.writeLine(to: plain, target: nil, succeeded: false, error: "the walk's own")
            race.linesAtSecondsReturn = Self.lines(at: logURL)
            race.secondReturned.signal()
        }
        _ = finished.wait(timeout: .now() + Self.hangGuard)

        #expect(race.linesAtSecondsReturn?.count == 1)
        let lines = Self.lines(at: logURL)
        #expect(lines.count == 1)
        #expect(lines.first?.error == "interrupted")
    }

    /// SimWalk#189: the walk's own end can write the line after the cancel was heard, and it ends the line at the cancel too, not at the clock's reading as it asks.
    @Test
    func aWalkSideWriteAfterTheCancelEndsTheLineAtTheCancel() throws {
        let fixture = try Fixture()
        fixture.clock.milliseconds = 400
        fixture.interruption.mark()
        fixture.clock.milliseconds = 900

        fixture.recorder.writeLine(to: fixture.log, target: nil, succeeded: false, error: "x")

        #expect(fixture.lines.first?.milliseconds == 400)
    }

    /// SimWalk#189: a runner the cancel's stop ended marks its end after the cancel; the line, which ends at the cancel, holds no mark past its `ms`, and the start before the cancel stays.
    @Test
    func aRunnerEndMarkedAfterTheCancelIsLeftOutOfTheLine() throws {
        let fixture = try Fixture()
        fixture.clock.milliseconds = 100
        fixture.recorder.runner(0, .started)
        fixture.clock.milliseconds = 400
        fixture.interruption.mark()
        fixture.clock.milliseconds = 500
        fixture.recorder.runner(0, .ended)

        fixture.recorder.writeLine(to: fixture.log, target: nil, succeeded: false, error: "interrupted")

        let line = fixture.lines.first

        #expect(line?.milliseconds == 400)
        #expect(line?.parallel?.shards.first?.runnerStartMs == 100)
        #expect(line?.parallel?.shards.first?.runnerEndMs == nil)
    }

    /// SimWalk#189: `mergeMs` is a duration, so a merge is judged by where it ended: one that ended after the cancel is left out of the line, though its duration is shorter than the line's `ms`.
    @Test
    func aMergeThatEndedAfterTheCancelIsLeftOutOfTheLine() throws {
        let fixture = try Fixture()
        fixture.clock.milliseconds = 100
        fixture.recorder.mergeBegan()
        fixture.clock.milliseconds = 400
        fixture.interruption.mark()
        fixture.clock.milliseconds = 600
        fixture.recorder.mergeEnded()

        fixture.recorder.writeLine(to: fixture.log, target: nil, succeeded: false, error: "interrupted")

        let line = fixture.lines.first

        #expect(line?.milliseconds == 400)
        #expect(line?.parallel?.mergeMs == nil)
    }

    /// A merge that ended before the line's end keeps its duration.
    @Test
    func aMergeThatEndedBeforeTheLinesEndKeepsItsDuration() throws {
        let fixture = try Fixture()
        fixture.clock.milliseconds = 100
        fixture.recorder.mergeBegan()
        fixture.clock.milliseconds = 300
        fixture.recorder.mergeEnded()
        fixture.clock.milliseconds = 400
        fixture.interruption.mark()

        fixture.recorder.writeLine(to: fixture.log, target: nil, succeeded: false, error: "interrupted")

        let line = fixture.lines.first

        #expect(line?.milliseconds == 300)
        #expect(line?.parallel?.mergeMs == 200)
    }

    /// How long the first writer is held for a second that waits on the lock, in seconds.
    private static let hold: TimeInterval = 1

    /// Only a hang guard: every wait it bounds is met at once in a passing run, and in a failing one.
    private static let hangGuard: TimeInterval = 60

    static func lines(at url: URL) -> [UsageLog.Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(UsageLog.Entry.self, from: Data($0.utf8)) }
    }
}

extension ShardTimingRecorderTests {
    /// A recorder over a one-shard walk on a clock the test sets, and the log it writes to.
    struct Fixture {
        let clock = Clock()
        let interruption: InterruptionMark
        let recorder: ShardTimingRecorder
        let log: UsageLog
        private let directory: TemporaryDirectory

        init() throws {
            directory = try TemporaryDirectory()
            let clock = clock
            let telemetry = WalkTelemetry(writer: ProgressWriter(url: directory.url.appendingPathComponent("progress.json"), clock: { Date() }, pid: 1), resultURL: nil, clock: { TimeInterval(clock.milliseconds) / 1000 })
            telemetry.begin(tool: "walk")
            interruption = InterruptionMark(telemetry: telemetry)
            recorder = try #require(ShardTimingRecorder(telemetry: telemetry, shards: [ShardTiming(index: 0, device: "A", origin: .cloned)], interruption: interruption))
            log = UsageLog(fileURL: directory.url.appendingPathComponent("usage.jsonl"), now: { Date() })
        }

        /// The `walk.parallel` lines written so far.
        var lines: [UsageLog.Entry] {
            ShardTimingRecorderTests.lines(at: directory.url.appendingPathComponent("usage.jsonl"))
        }
    }

    /// The walk's monotonic clock, set by the test; the telemetry's start is the reading at its begin, 0.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        /// The reading, in milliseconds.
        var milliseconds: Int {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    /// The gates the two writers pass each other through, and what the second saw on disk as it returned.
    final class Race: @unchecked Sendable {
        let firstInWrite = DispatchSemaphore(value: 0)
        let secondStarted = DispatchSemaphore(value: 0)
        let secondReturned = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var seen: [UsageLog.Entry]?

        /// The `walk.parallel` lines on disk when the second writer returned; `nil` before it did.
        var linesAtSecondsReturn: [UsageLog.Entry]? {
            get { lock.withLock { seen } }
            set { lock.withLock { seen = newValue } }
        }
    }
}
