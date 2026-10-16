//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The resident runner's loop: requests served in order, the device handed back before an `end` is answered, and an exit record on every way out.
struct LiveSessionLoopTests {
    /// Requests are answered in number order; an `end` hands the device back before it is answered, and the session ends saying so.
    @Test
    func requestsAreServedInOrderAndEndHandsTheDeviceBackFirst() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: true)
        _ = try channel.send(.read)
        _ = try channel.send(.read)
        _ = try channel.send(.end)
        let script = Script()

        let exit = Self.loop(channel, idle: 900).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(script.events == ["start app.example", "read 1", "read 2", "hand back", "end 3"])
        #expect(exit.reason == .ended)
        #expect(exit.served == 3)
        #expect(try channel.exitRecord() == exit)
        #expect(try channel.readyRecord() == Self.ready)
        #expect(try channel.response(to: 3) == LiveSessionResponse(n: 3, action: .end))
    }

    /// With no request for the whole timeout the session stops on its own, handing the device back and recording why.
    @Test
    func asessionWithNoRequestGoesIdle() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: true)
        let script = Script()

        let exit = Self.loop(channel, idle: 20).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(exit.reason == .idle)
        #expect(exit.served == 0)
        #expect(exit.stoppedAt == Self.start.addingTimeInterval(20))
        #expect(script.events == ["start app.example", "hand back"])
        #expect(try channel.exitRecord() == exit)
    }

    /// Each request restarts the idle clock: a read at 15 s keeps a 20 s session alive until 35 s.
    @Test
    func arequestRestartsTheIdleClock() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: true)
        let script = Script(sendingReadAt: 15, on: channel)

        let exit = Self.loop(channel, idle: 20).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(exit.reason == .idle)
        #expect(exit.served == 1)
        #expect(exit.stoppedAt == Self.start.addingTimeInterval(35))
    }

    /// A request the runner cannot read — an action it does not know — is answered as a failure under its number, and the session serves on; so is a request whose answer threw.
    @Test
    func anunreadableOrFailedRequestIsAnsweredAsAFailureAndServingGoesOn() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: true)
        try Data("{\"n\": 1, \"action\": \"fly\"}".utf8).write(to: channel.layout.request(1))
        _ = try channel.send(.read)
        _ = try channel.send(.end)
        let script = Script(failingReads: true)

        let exit = Self.loop(channel, idle: 900).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )
        let unknown = try #require(try channel.response(to: 1))
        let failed = try #require(try channel.response(to: 2))

        #expect(unknown.action == nil)
        #expect(unknown.failure?.contains("fly") == true)
        #expect(failed == LiveSessionResponse(n: 2, action: .read, failure: "the read failed"))
        #expect(exit.reason == .ended)
        #expect(exit.served == 3)
    }

    /// A session with nothing to launch fails at once, still handing the device back and writing why — never a runner gone without a word.
    @Test
    func asessionWithNoLaunchRecordFailsAndSaysWhy() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: false)
        let script = Script()

        let exit = Self.loop(channel, idle: 900).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(exit.reason == .failed)
        #expect(exit.detail.contains(channel.layout.launch.path))
        #expect(script.events == ["hand back"])
        #expect(try channel.exitRecord() == exit)
        #expect(try channel.readyRecord() == nil)
    }

    /// A launch that throws is the session's failure, in the launch's own words, and the runner never claims to be ready.
    @Test
    func alaunchThatThrowsFailsTheSessionInItsOwnWords() throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: true)
        let script = Script(failingStart: true)

        let exit = Self.loop(channel, idle: 900).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(exit == LiveSessionExit(reason: .failed, detail: "the launch failed", served: 0, stoppedAt: Self.start))
        #expect(try channel.exitRecord() == exit)
        #expect(try channel.readyRecord() == nil)
    }

    /// The heartbeat is stopped on every way out — `end`, the idle timeout, a failure — and only once `exit.json`, which supersedes it, is down (SimWalk#91 item 10).
    @Test(arguments: [Way.end, .idle, .failure])
    func theHeartbeatStopsOnceTheExitRecordIsWritten(way: Way) throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: way != .failure)
        if way == .end {
            _ = try channel.send(.end)
        }
        let script = Script()

        let exit = Self.loop(channel, idle: 20).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(exit.reason == way.reason)
        #expect(script.schedule?.stops == [.afterExitRecord])
    }

    /// An exit record that cannot be written leaves the heartbeat beating, on every way out: stopped, its last beat would bound the stop a few seconds after the loop returned, before whatever the runner does next has finished (SimWalk#91 item 10).
    @Test(arguments: [Way.end, .idle, .failure])
    func anexitRecordThatCannotBeWrittenLeavesTheHeartbeatBeating(way: Way) throws {
        let directory = try TemporaryDirectory()
        let channel = try Self.channel(in: directory, launch: way != .failure)
        if way == .end {
            _ = try channel.send(.end)
        }
        // A directory in the record's place: the rename of the record over it fails, as a full disk's write would.
        try FileManager.default.createDirectory(at: channel.layout.exit, withIntermediateDirectories: false)
        let script = Script()

        let exit = Self.loop(channel, idle: 20).run(
            heartbeat: script.heartbeat(on: channel),
            start: script.start,
            answer: script.answer,
            handBack: script.handBack,
            now: script.now,
            pause: script.pause
        )

        #expect(exit.reason == .failed)
        #expect(script.schedule?.stops == [])
    }

    fileprivate static let start = Date(timeIntervalSince1970: 1_000_000)

    fileprivate static let ready = LiveSessionReady(
        device: CaptureManifest.Device(name: "iPhone17,1", udid: "UDID-1", osVersion: "27.0"),
        runnerCommit: "c0ffee",
        readyAt: start
    )

    private static func loop(_ channel: LiveSessionChannel, idle timeout: TimeInterval) -> LiveSessionLoop {
        LiveSessionLoop(channel: channel, idle: LiveSessionIdle(timeout: timeout))
    }

    private static func channel(in directory: TemporaryDirectory, launch: Bool) throws -> LiveSessionChannel {
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url.appendingPathComponent("session", isDirectory: true)))
        try channel.prepare()
        if launch {
            try channel.writeLaunch(LiveSessionLaunch(appBundleID: "app.example", state: nil))
        }
        return channel
    }
}

extension LiveSessionLoopTests {
    /// The ways a session stops.
    enum Way: Sendable {
        case end, idle, failure

        var reason: LiveSessionExit.Reason {
            switch self {
            case .end: .ended
            case .idle: .idle
            case .failure: .failed
            }
        }
    }

    /// The runner's half, scripted: what it was asked to do, in order, on a clock that moves only when the loop pauses.
    final class Script {
        private(set) var events: [String] = []
        private var clock = LiveSessionLoopTests.start
        private let failingStart: Bool
        private let failingReads: Bool
        private let sendAt: TimeInterval?
        private let channel: LiveSessionChannel?

        init(failingStart: Bool = false, failingReads: Bool = false) {
            self.failingStart = failingStart
            self.failingReads = failingReads
            sendAt = nil
            channel = nil
        }

        /// Sends one `read` once the clock reaches `seconds` past the start, as a host would mid-session.
        init(sendingReadAt seconds: TimeInterval, on channel: LiveSessionChannel) {
            failingStart = false
            failingReads = false
            sendAt = seconds
            self.channel = channel
        }

        /// The heartbeat handed to the loop, on a schedule fired only by hand; `nil` until ``heartbeat(on:)`` starts it.
        private(set) var schedule: ScriptedHeartbeatSchedule?

        /// Starts a heartbeat on `channel` whose beats are stamped with the session's start.
        func heartbeat(on channel: LiveSessionChannel) -> LiveSessionHeartbeat.Running {
            let schedule = ScriptedHeartbeatSchedule(channel: channel)
            self.schedule = schedule
            return LiveSessionHeartbeat.start(on: channel, now: { LiveSessionLoopTests.start }, schedule: schedule.schedule)
        }

        func start(_ launch: LiveSessionLaunch) throws -> LiveSessionReady {
            guard !failingStart else { throw Failure(description: "the launch failed") }
            events.append("start \(launch.appBundleID)")
            return LiveSessionLoopTests.ready
        }

        func answer(_ request: LiveSessionRequest) throws -> LiveSessionResponse {
            events.append("\(request.action.rawValue) \(request.n)")
            if failingReads, request.action == .read {
                throw Failure(description: "the read failed")
            }
            return LiveSessionResponse(n: request.n, action: request.action)
        }

        func handBack() {
            events.append("hand back")
        }

        func now() -> Date {
            clock
        }

        func pause(_: TimeInterval) {
            // Whole seconds, so a 20 s timeout takes 20 pauses rather than 400.
            clock = clock.addingTimeInterval(1)
            if let sendAt, let channel, clock == LiveSessionLoopTests.start.addingTimeInterval(sendAt) {
                _ = try? channel.send(.read)
            }
        }
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }
}
