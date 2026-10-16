//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The session runner's heartbeat (SimWalk#91 item 10): the file it writes, the stop it bounds, and the beats a started one writes.
struct LiveSessionHeartbeatTests {
    /// A beat reads back as written, in the protocol's shape: `at` to the millisecond and the interval in whole seconds.
    @Test
    func abeatRoundTripsInTheProtocolsShape() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        let beat = LiveSessionHeartbeat(writtenAt: Date(timeIntervalSince1970: 1_000_000.5))

        try channel.markHeartbeat(beat)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: channel.layout.heartbeat)) as? [String: Any])

        #expect(try channel.heartbeat() == beat)
        #expect(json["at"] as? String == "1970-01-12T13:46:40.500Z")
        #expect(json["interval"] as? Int == 2)
    }

    /// A session directory with no beat — a runner from before the heartbeat — has none to read.
    @Test
    func asessionWithNoBeatHasNone() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)

        #expect(try channel.heartbeat() == nil)
    }

    /// The stop is bounded at three intervals past the beat: the one the runner promised, and two of tolerance for a timer that fired late.
    @Test
    func thelatestStopIsThreeIntervalsPastTheBeat() {
        let beat = Date(timeIntervalSince1970: 1_000_000)

        #expect(LiveSessionHeartbeat(writtenAt: beat).latestStop == beat.addingTimeInterval(6))
        #expect(LiveSessionHeartbeat(writtenAt: beat, interval: 5).latestStop == beat.addingTimeInterval(15))
    }

    /// Starting writes the first beat at once — before anything the caller does next, the app's launch in the runner — then one per scheduled tick, each stamped with the clock; stopping cancels the schedule.
    @Test
    func startingBeatsAtOnceThenOnEachTick() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let schedule = ScriptedHeartbeatSchedule(channel: channel)

        let running = LiveSessionHeartbeat.start(on: channel, now: clock.now, schedule: schedule.schedule)
        let first = try channel.heartbeat()
        clock.advance(2)
        schedule.fire()
        let second = try channel.heartbeat()
        running.stop(LiveSessionExitRecorded())

        #expect(first == LiveSessionHeartbeat(writtenAt: Date(timeIntervalSince1970: 1_000_000)))
        #expect(second == LiveSessionHeartbeat(writtenAt: Date(timeIntervalSince1970: 1_000_002)))
        #expect(schedule.interval == LiveSessionHeartbeat.interval)
        #expect(schedule.stops == [.beforeExitRecord])
    }

    /// A beat that cannot be written takes the last one away rather than leaving it to bound the stop too early.
    @Test
    func abeatThatCannotBeWrittenLeavesNoStaleOne() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory)
        let schedule = ScriptedHeartbeatSchedule(channel: channel)
        let running = LiveSessionHeartbeat.start(on: channel, now: { Date(timeIntervalSince1970: 1_000_000) }, schedule: schedule.schedule)
        defer { running.stop(LiveSessionExitRecorded()) }
        // A directory in the file's place: the rename of the next beat over it fails, as a full disk's write would.
        try FileManager.default.removeItem(at: channel.layout.heartbeat)
        try FileManager.default.createDirectory(at: channel.layout.heartbeat, withIntermediateDirectories: false)

        schedule.fire()

        #expect(!FileManager.default.fileExists(atPath: channel.layout.heartbeat.path))
    }

    /// The runner's own timer beats on a queue of its own, never the main thread: an XCUITest query holds that for as long as a step takes, and a beat that waited on it would bound a runner killed mid-step at its last beat before the step, long before its stop.
    @Test
    func thebackgroundTimerBeatsOffTheMainThread() {
        let beats = Beats()
        let stop = LiveSessionHeartbeat.backgroundTimer(every: 0.2, beats.beat)
        defer { stop() }

        // Bounded, so a timer on a queue nothing drains fails here rather than hanging.
        #expect(beats.started.wait(timeout: .now() + 5) == .success)
        #expect(beats.started.wait(timeout: .now() + 5) == .success)

        #expect(beats.count.started >= 2)
        #expect(!beats.onMainThread)
    }

    /// Stopping the runner's own timer waits out a beat being written, and none starts after: a beat landing after `exit.json` would leave a stale bound beside the record, and one landing after the loop returned would outlive the stop it was meant to bound.
    @Test
    func thebackgroundTimerWritesNoBeatOnceStopReturns() throws {
        // A beat that takes four intervals, so `stop` is all but certain to arrive in the middle of one.
        let beats = Beats(lasting: 0.2)
        let stop = LiveSessionHeartbeat.backgroundTimer(every: 0.2, beats.beat)
        try #require(beats.started.wait(timeout: .now() + 5) == .success)

        stop()
        let atStop = beats.count
        Thread.sleep(forTimeInterval: 0.3)

        #expect(atStop.finished == atStop.started)
        #expect(beats.count == atStop)
    }

    /// The runner's own timer beats on once every reference to its stop is gone: the loop leaves a heartbeat running when it could not write `exit.json`, and the runner holds it only for the loop's call, so a timer freed with its last reference would stop beating then rather than when the process died.
    ///
    /// Nothing can stop this one, which is the point: it outlives the test, beating into a counter nothing reads.
    @Test
    func thebackgroundTimerBeatsOnWithNothingHoldingIt() {
        let beats = Beats()
        _ = LiveSessionHeartbeat.backgroundTimer(every: 0.2, beats.beat)

        #expect(beats.started.wait(timeout: .now() + 5) == .success)
        #expect(beats.started.wait(timeout: .now() + 5) == .success)
    }

    private static func channel(in directory: TemporaryDirectory) throws -> LiveSessionChannel {
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url.appendingPathComponent("session", isDirectory: true)))
        try channel.prepare()
        return channel
    }
}

extension LiveSessionHeartbeatTests {
    /// A clock that moves only when told.
    final class Clock: @unchecked Sendable {
        private var current: Date

        init(_ start: Date) {
            current = start
        }

        func now() -> Date {
            current
        }

        func advance(_ seconds: TimeInterval) {
            current = current.addingTimeInterval(seconds)
        }
    }

    /// Beats from a real timer, counted as they start and finish, with whether any ran on the main thread; each start is signalled on ``started``.
    final class Beats: @unchecked Sendable {
        let started = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private let duration: TimeInterval
        private var counted = Count(started: 0, finished: 0)
        private var sawMainThread = false

        /// `duration` is how long each beat takes, as a slow write would.
        init(lasting duration: TimeInterval = 0) {
            self.duration = duration
        }

        var count: Count {
            lock.withLock { counted }
        }

        var onMainThread: Bool {
            lock.withLock { sawMainThread }
        }

        @Sendable
        func beat() {
            lock.withLock {
                counted.started += 1
                sawMainThread = sawMainThread || Thread.isMainThread
            }
            started.signal()
            if duration > 0 {
                Thread.sleep(forTimeInterval: duration)
            }
            lock.withLock { counted.finished += 1 }
        }
    }

    /// Beats started and finished.
    struct Count: Equatable {
        var started: Int
        var finished: Int
    }
}
