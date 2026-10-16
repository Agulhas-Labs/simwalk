//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `session end`: a runner that will not stop is signalled only through its own group, and only when it provably is the runner the session started; the device is handed back however it ended.
struct LiveSessionStopTests {
    /// A runner leading its own group and named `xcodebuild` that ignores `end` gets `SIGTERM` to that group — the recorded pid's, and nobody else's.
    @Test
    func arunnerThatWillNotEndIsSignalledThroughItsOwnGroup() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)

        let report = fixture.stop()

        #expect(fixture.processes.signalled.map(\.group) == [Self.pid])
        #expect(fixture.processes.signalled.map(\.signal) == [SIGTERM])
        #expect(!report.stillRunning)
    }

    /// A pid that does not lead its own group is not the runner `start` spawned, and is never signalled — and since it is not that runner, the runner has exited.
    @Test
    func apidThatDoesNotLeadItsGroupIsNotSignalled() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid, group: 1)

        let report = fixture.stop()

        #expect(fixture.processes.signalled.isEmpty)
        #expect(!report.stillRunning)
        #expect(report.steps.contains { $0.contains("does not lead its own process group") })
    }

    /// A stale session's pid reused by another session's runner leads its group and is `xcodebuild`, but started after this session's record: it is left alone — not asked to end, not signalled.
    @Test
    func anxcodebuildThatStartedAfterTheRecordIsLeftAlone() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.processes.startTimes[Self.pid] = Date(timeIntervalSince1970: 5)

        let report = fixture.stop()

        #expect(fixture.processes.signalled.isEmpty)
        #expect(try LiveSessionChannel(layout: fixture.layout).request(1) == nil)
        #expect(!report.stillRunning)
        #expect(report.steps.first == "pid 4242 is running and was left alone: it started 5 s after this session's record was written, so it is not the runner this session started — that runner has exited")
    }

    /// A runner that outlives `SIGTERM` keeps its session, so `list` still shows it and its device stays held.
    @Test
    func arunnerLeftRunningKeepsItsSession() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.processes.diesOnSignal = false

        let report = fixture.stop()

        #expect(report.stillRunning)
        #expect(FileManager.default.fileExists(atPath: fixture.layout.directory.path))
        #expect(report.steps.contains { $0.hasPrefix("kept ") && $0.hasSuffix("the runner is still running, so the session stays listed — end it again once it has stopped") })
    }

    /// A group leader whose name is not `xcodebuild` — a pid reused since the runner died — is never signalled.
    @Test
    func agroupLeaderNamedOtherThanXcodebuildIsNotSignalled() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid, name: "Python")

        let report = fixture.stop()

        #expect(fixture.processes.signalled.isEmpty)
        #expect(report.steps.contains { $0.contains("it is Python, not xcodebuild") })
    }

    /// A runner that answers `end` and exits by itself is not signalled.
    @Test
    func arunnerThatExitsByItselfIsNotSignalled() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.onPause = {
            let channel = LiveSessionChannel(layout: fixture.layout)
            if let request = try? channel.request(1) {
                try? channel.respond(LiveSessionResponse(n: request.n, action: .end))
                try? channel.markExit(LiveSessionExit(reason: .ended, detail: "end", served: 1, stoppedAt: Date()))
                fixture.processes.alive.remove(Self.pid)
            }
        }

        let report = fixture.stop()

        #expect(fixture.processes.signalled.isEmpty)
        #expect(report.steps.first == "sent end (request 1); the runner answered")
        #expect(report.lines.contains("runner: ended on request after 1 request"))
    }

    /// Whether the runner had already gone, exited on `end`, was signalled, or its pid now belongs to another process, the device is handed back and the directory removed.
    @Test(arguments: [Path.alreadyExited, .exits, .signalled, .notSignalled])
    func thehandbackRunsOnEveryEndPath(_ path: Path) throws {
        let fixture = try Fixture()
        switch path {
        case .alreadyExited:
            break
        case .exits:
            fixture.processes.runner(Self.pid)
            fixture.onPause = { fixture.processes.alive.remove(Self.pid) }
        case .signalled:
            fixture.processes.runner(Self.pid)
        case .notSignalled:
            fixture.processes.runner(Self.pid, group: 1)
        }

        _ = fixture.stop()

        #expect(fixture.vectors.contains(AccessibilityPreference.enableArguments(udid: "UDID-1")[0]))
        #expect(fixture.vectors.contains(DeviceAppearance.setArguments(.light, udid: "UDID-1")))
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// SimWalk#75: a runner that exits as it is checked before the signal — after its name reads `xcodebuild`, before its start time is — has exited: it is not signalled, and the session is not kept as still running.
    @Test
    func arunnerThatExitsAsItIsCheckedHasExited() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.onPause = {
            fixture.processes.afterNameRead = { fixture.processes.alive.remove($0) }
        }

        let report = fixture.stop()

        #expect(fixture.processes.signalled.isEmpty)
        #expect(!report.stillRunning)
        #expect(report.steps.contains("the runner (pid 4242) exited as it was being checked, before it could be signalled"))
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// SimWalk#75: a runner that exits just before `SIGTERM` is sent, so the signal finds no group, has exited — not kept as still running.
    @Test
    func arunnerThatExitsJustBeforeTheSignalHasExited() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.processes.beforeSignal = { group in fixture.processes.alive.remove(group) }

        let report = fixture.stop()

        #expect(!report.stillRunning)
        #expect(report.steps.contains("the runner (pid 4242) exited before SIGTERM reached its process group"))
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// SimWalk#75: a pid reused while `end` waits for the runner's answer is the runner gone, not the runner still running — the wait ends there rather than running out its grace.
    @Test
    func apidReusedWhileEndWaitsEndsTheWait() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.onPause = { fixture.processes.startTimes[Self.pid] = Date(timeIntervalSince1970: 5) }

        let report = fixture.stop()

        #expect(report.steps.first == "sent end: the session's runner stopped before answering request 1, leaving no exit record")
        #expect(fixture.processes.signalled.isEmpty)
        #expect(!report.stillRunning)
    }

    /// SimWalk#77: a pid reused once the runner has answered `end` is the runner gone — the wait for it to exit ends there, and it is not taken for a runner that will not stop.
    @Test
    func apidReusedAfterEndIsAnsweredEndsTheExitWait() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.onPause = {
            let channel = LiveSessionChannel(layout: fixture.layout)
            if let request = try? channel.request(1), (try? channel.response(to: 1)) == nil {
                try? channel.respond(LiveSessionResponse(n: request.n, action: .end))
                fixture.processes.startTimes[Self.pid] = Date(timeIntervalSince1970: 5)
            }
        }

        let report = fixture.stop()

        #expect(report.steps == ["sent end (request 1); the runner answered", "the runner (pid 4242) exited", "removed \(fixture.layout.directory.path)"])
        #expect(fixture.processes.signalled.isEmpty)
        #expect(fixture.paused < LiveSessionStop.grace)
    }

    /// SimWalk#77: a pid reused during the grace after `SIGTERM` is the runner gone — not the runner left running, with a `kill -TERM` aimed at the stranger now holding its number.
    @Test
    func apidReusedDuringTheSignalGraceIsTheRunnerGone() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.processes.diesOnSignal = false
        fixture.processes.beforeSignal = { _ in
            fixture.onPause = { fixture.processes.startTimes[Self.pid] = Date(timeIntervalSince1970: 5) }
        }

        let report = fixture.stop()

        #expect(!report.stillRunning)
        #expect(report.steps.contains("pid 4242 was still running 10 s after end: sent SIGTERM to its process group; it exited"))
        #expect(!report.steps.contains { $0.contains("kill -TERM") })
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// SimWalk#77: a `SIGTERM` that is not delivered because the pid was reused as it was sent is the runner gone, not the runner left running.
    @Test
    func apidReusedAsTheSignalIsRefusedIsTheRunnerGone() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.processes.refusesSignal = true
        fixture.processes.beforeSignal = { _ in fixture.processes.startTimes[Self.pid] = Date(timeIntervalSince1970: 5) }

        let report = fixture.stop()

        #expect(!report.stillRunning)
        #expect(report.steps.contains("the runner (pid 4242) exited before SIGTERM reached its process group"))
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// A `SIGTERM` the runner's group refuses while the runner is still running leaves it running: the session is kept, and the step says the signal was not delivered.
    @Test
    func arunnerWhoseGroupRefusesTheSignalKeepsItsSession() throws {
        let fixture = try Fixture()
        fixture.processes.runner(Self.pid)
        fixture.processes.refusesSignal = true

        let report = fixture.stop()

        #expect(report.stillRunning)
        #expect(fixture.processes.signalled.map(\.group) == [Self.pid])
        #expect(report.steps.contains("pid 4242 is still running 10 s after end, and SIGTERM to its process group was not delivered"))
        #expect(report.qualifications.contains("the runner is still running"))
        #expect(FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// SimWalk#91: a runner gone before `end` whose `exit.json` stopped it long ago is handed back from then — a device already back on needs no wait, no write and no qualification.
    @Test
    func arunnerThatExitedLongAgoIsHandedBackFromItsExitRecord() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try LiveSessionChannel(layout: fixture.layout).markExit(.idle(after: 900, served: 3, stoppedAt: Date(timeIntervalSince1970: 100)))

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .alreadyOn)
        #expect(report.qualifications.isEmpty)
        #expect(fixture.paused == 0)
        #expect(!fixture.wroteAccessibility)
    }

    /// SimWalk#91: a runner killed long before `end`, with no `exit.json`, is handed back from its heartbeat's bound, as `session list` hands it back.
    @Test
    func arunnerKilledLongAgoIsHandedBackFromItsHeartbeat() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try LiveSessionChannel(layout: fixture.layout).markHeartbeat(LiveSessionHeartbeat(writtenAt: Date(timeIntervalSince1970: 100)))

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .alreadyOn)
        #expect(report.qualifications.isEmpty)
        #expect(fixture.paused == 0)
        #expect(!fixture.wroteAccessibility)
    }

    /// A runner gone before `end` that left neither file — one from before the heartbeat — still gets the teardown's whole wait from now, and a restore that never saw the teardown says a later one may undo it.
    @Test
    func arunnerThatLeftNoStopIsHandedBackFromNow() throws {
        let fixture = try Fixture.stoppedLongAgo()

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restoredWithoutTeardown)
        #expect(report.qualifications.contains("a device accessibility restore a later teardown may undo"))
        #expect(fixture.paused >= 10)
    }

    /// SimWalk#91: when `session list` already switched accessibility back on for a runner gone before `end` and recorded it, `end` reports the record and touches the device's accessibility no more — but still puts its appearance back, which `list` does not.
    @Test
    func arestoreSessionListRecordedIsReportedNotMadeAgain() throws {
        let fixture = try Fixture.stoppedLongAgo()
        let recorded = AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored)
        try fixture.listed(recorded.state, coveredStop: Date(timeIntervalSince1970: 900))

        let report = fixture.stop()

        #expect(report.handback?.accessibility == recorded)
        #expect(report.qualifications.isEmpty)
        #expect(fixture.paused == 0)
        #expect(!fixture.vectors.contains(AccessibilityPreference.readArguments(udid: "UDID-1")))
        #expect(!fixture.wroteAccessibility)
        #expect(fixture.vectors.contains(DeviceAppearance.setArguments(.light, udid: "UDID-1")))
        #expect(report.lines.contains { $0.hasPrefix("accessibility:") && $0.contains("`session list` switched it back on") })
    }

    /// A restore `session list` recorded as failed is made again: this `end` is the last handback before the record goes with the session's directory.
    @Test
    func arestoreSessionListRecordedAsFailedIsMadeAgain() throws {
        let fixture = try Fixture.stoppedLongAgo()
        fixture.accessibility = "0"
        try JSONEncoder().encode(AccessibilityPreference.Restoration(udid: "UDID-1", state: .failed(reason: "rebooting"))).write(to: fixture.layout.accessibilityHandback)

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restored)
        #expect(fixture.wroteAccessibility)
        #expect(report.lines.contains { $0.contains("this session switched it back on") })
    }

    /// SimWalk#92: a restore `session list` made without seeing the teardown is what restoring again would clear, so `end` does not report it as recorded.
    @Test
    func arestoreThatNeverSawTheTeardownIsMadeAgain() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try fixture.listed(.restoredWithoutTeardown, coveredStop: Date(timeIntervalSince1970: 900))

        let report = fixture.stop()

        #expect(!report.steps.contains { $0.contains("reported as recorded") })
        #expect(report.handback?.accessibility.state == .alreadyOn)
        #expect(fixture.vectors.contains(AccessibilityPreference.readArguments(udid: "UDID-1")))
        #expect(report.lines.contains { $0.hasPrefix("accessibility:") && $0.contains("already read on") })
    }

    /// A runner `end` saw running is not handed back from a heartbeat written long before: it was alive after that beat, so the bound would place its stop too early — the wait runs from now.
    @Test
    func arunnerEndSawRunningIsNotHandedBackFromAnOldHeartbeat() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try LiveSessionChannel(layout: fixture.layout).markHeartbeat(LiveSessionHeartbeat(writtenAt: Date(timeIntervalSince1970: 100)))
        try JSONEncoder().encode(AccessibilityPreference.Restoration(udid: "UDID-1", state: .alreadyOn)).write(to: fixture.layout.accessibilityHandback)
        fixture.processes.runner(Self.pid)
        fixture.onPause = { fixture.processes.alive.remove(Self.pid) }

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restoredWithoutTeardown)
        #expect(fixture.wroteAccessibility)
    }

    /// A runner `end` saw running is not handed back from its own `exit.json` either: that is written before XCTest's teardown and before `xcodebuild` returns, so a runner slow to exit after it would have its teardown taken as long past — the wait runs from the exit `end` saw.
    @Test
    func arunnerEndSawRunningIsNotHandedBackFromItsExitRecord() throws {
        let fixture = try Fixture.stoppedLongAgo()
        fixture.processes.runner(Self.pid)
        fixture.onPause = {
            let channel = LiveSessionChannel(layout: fixture.layout)
            if let request = try? channel.request(1) {
                try? channel.respond(LiveSessionResponse(n: request.n, action: .end))
                try? channel.markExit(LiveSessionExit(reason: .ended, detail: "end", served: 1, stoppedAt: Date(timeIntervalSince1970: 100)))
                fixture.processes.alive.remove(Self.pid)
            }
        }

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restoredWithoutTeardown)
        #expect(fixture.wroteAccessibility)
        #expect(fixture.paused >= 10)
    }

    /// SimWalk#92: `list` dated its one restore from an older session's stop on the device and recorded it into this session too; this session stopped later, so the record does not vouch for its teardown and the restore is made again.
    @Test
    func arecordDatedFromAnOlderSessionsStopIsNotReused() throws {
        let fixture = try Fixture.stoppedLongAgo()
        fixture.accessibility = "0"
        try fixture.stopped(at: 995)
        try fixture.sibling("older", stoppedAt: 100)
        try fixture.listed(.alreadyOn, coveredStop: Date(timeIntervalSince1970: 100))

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restored)
        #expect(fixture.wroteAccessibility)
        #expect(report.steps.contains { $0.hasSuffix("— restored again") })
    }

    /// SimWalk#92: a record made before another session on the device stopped does not cover that session's teardown, so it is not reused — and the restore made instead is dated from the later stop, not this session's own, so it waits for that teardown rather than reading the key on before it lands.
    @Test
    func arecordThatPredatesALaterSessionsStopIsNotReused() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try fixture.listed(.alreadyOn, coveredStop: Date(timeIntervalSince1970: 100))
        try fixture.sibling("later", stoppedAt: 998)
        var tornDown = false
        fixture.onPause = {
            if !tornDown, fixture.paused >= 3 {
                fixture.accessibility = "0"
                tornDown = true
            }
        }

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restored)
        #expect(fixture.wroteAccessibility)
    }

    /// A record whose stop is no earlier than every stopped session's on the device is still reported, not made again.
    @Test
    func arecordCoveringEveryStopOnTheDeviceIsReused() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try fixture.listed(.restored, coveredStop: Date(timeIntervalSince1970: 500))
        try fixture.sibling("other", stoppedAt: 500)

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restored)
        #expect(fixture.paused == 0)
        #expect(!fixture.wroteAccessibility)
        #expect(!fixture.vectors.contains(AccessibilityPreference.readArguments(udid: "UDID-1")))
    }

    /// A stopped session on the device with no stop and no record could have stopped as late as now, so no record covers it: the restore is made again, from now.
    @Test
    func anunknownStopOnTheDeviceForbidsReuse() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try fixture.listed(.restored, coveredStop: Date(timeIntervalSince1970: 500))
        try fixture.sibling("unknown", stoppedAt: nil)

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .restoredWithoutTeardown)
        #expect(fixture.wroteAccessibility)
        #expect(fixture.paused >= 10)
    }

    /// A record from before SimWalk#92 names no stop, so `end` cannot tell what it covers: it makes the restore again rather than trusting it.
    @Test
    func arecordInTheOldShapeIsNotReused() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try JSONEncoder().encode(AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored)).write(to: fixture.layout.accessibilityHandback)

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .alreadyOn)
        #expect(fixture.vectors.contains(AccessibilityPreference.readArguments(udid: "UDID-1")))
        #expect(report.steps.contains { $0.hasSuffix("— restored again") })
    }

    /// SimWalk#92, end to end: `list` ran while A was the only stopped session on the device; B stopped after, so the record `list` wrote does not cover B's teardown and `end A` restores again rather than reusing it.
    @Test
    func arecordListWroteBeforeALaterStopIsNotReusedByEnd() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try fixture.list(at: 500)
        try fixture.sibling("later", stoppedAt: 998)

        let report = fixture.stop()

        #expect(report.steps.contains { $0.hasSuffix("— restored again") })
        #expect(fixture.vectors.contains(AccessibilityPreference.readArguments(udid: "UDID-1")))
    }

    /// SimWalk#92, end to end: `list` ran after both sessions stopped, so its record covers every stop on the device and `end A` reuses it without a second restore.
    @Test
    func arecordListWroteAfterEveryStopIsReusedByEnd() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try fixture.sibling("other", stoppedAt: 998)
        let handbacks = try fixture.list(at: 1000, accessibility: "0")

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == handbacks["s1"]?.state)
        #expect(fixture.paused == 0)
        #expect(!fixture.vectors.contains(AccessibilityPreference.readArguments(udid: "UDID-1")))
        #expect(!fixture.wroteAccessibility)
        #expect(!report.steps.contains { $0.hasSuffix("— restored again") })
    }

    /// A restore `session list` could not confirm is made again: this `end` is the last handback before the record goes with the directory.
    @Test
    func anUnconfirmedRecordIsRestoredAgain() throws {
        let fixture = try Fixture.stoppedLongAgo()
        try fixture.stopped(at: 100)
        try fixture.listed(.unconfirmed(reason: "read timed out"), coveredStop: Date(timeIntervalSince1970: 900))

        let report = fixture.stop()

        #expect(!report.steps.contains { $0.contains("reported as recorded") })
        #expect(report.handback?.accessibility.state == .alreadyOn)
        #expect(fixture.vectors.contains(AccessibilityPreference.readArguments(udid: "UDID-1")))
        #expect(report.lines.contains { $0.hasPrefix("accessibility:") && $0.contains("already read on") })
    }

    /// A pid that is not this session's runner is the runner gone, so the handback is dated from the stop it left (`latestStop()`), not made from now.
    @Test
    func aStrangerAtTheRunnersPidIsHandedBackFromItsLatestStop() throws {
        let fixture = try Fixture.stoppedLongAgo()
        fixture.processes.runner(Self.pid, group: 1)
        try fixture.stopped(at: 100)

        let report = fixture.stop()

        #expect(report.handback?.accessibility.state == .alreadyOn)
        #expect(report.qualifications.isEmpty)
        #expect(fixture.paused == 0)
        #expect(!fixture.wroteAccessibility)
    }

    /// SimWalk#96: a device something else is using is not written to — no accessibility write, no appearance write — and the answer says why and is qualified; the session is still removed.
    @Test
    func aBusyDeviceIsNotHandedBack() throws {
        let fixture = try Fixture.stoppedLongAgo()
        fixture.accessibility = "0"

        let report = fixture.stop(isDeviceBusy: { _ in true })

        #expect(report.handback == nil)
        #expect(fixture.vectors.isEmpty)
        #expect(report.steps.contains { $0.hasPrefix("did not hand UDID-1 back") })
        #expect(report.qualifications == ["the device was not handed back: something else is using it"])
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }
}

extension LiveSessionStopTests {
    enum Path: CaseIterable, Sendable {
        case alreadyExited, exits, signalled, notSignalled
    }

    static let pid: Int32 = 4242

    /// A session directory, a fake runner, a device that switches accessibility back on when written, and a clock that moves only when the procedure pauses.
    final class Fixture {
        let directory: TemporaryDirectory
        let store: LiveSessionStore
        let layout: LiveSessionLayout
        let processes = FakeSessionProcesses()
        var onPause: () -> Void = {}
        private(set) var vectors: [[String]] = []
        private var elapsed: TimeInterval = 0
        /// When the clock starts, in seconds since 1970.
        var origin: TimeInterval = 0
        /// What the device's accessibility key reads until a restore writes it: off, the teardown having just landed.
        var accessibility = "0"

        init() throws {
            directory = try TemporaryDirectory()
            store = LiveSessionStore(directory: directory.url)
            layout = try store.create(id: "s1")
        }

        /// A runner gone long ago, from a device something has already switched back on: the clock starts at 1000 s.
        static func stoppedLongAgo() throws -> Fixture {
            let fixture = try Fixture()
            fixture.origin = 1000
            fixture.accessibility = "1"
            return fixture
        }

        /// How long the procedure has paused, in all.
        var paused: TimeInterval {
            elapsed
        }

        /// Whether the procedure wrote the device's accessibility preference.
        var wroteAccessibility: Bool {
            vectors.contains { $0.contains("write") && $0.contains(AccessibilityPreference.domain) }
        }

        /// Records this session's runner as having exited idle at `seconds` since 1970.
        func stopped(at seconds: TimeInterval) throws {
            try LiveSessionChannel(layout: layout).markExit(.idle(after: 900, served: 1, stoppedAt: Date(timeIntervalSince1970: seconds)))
        }

        /// Writes the restore `session list` recorded for this session, dated from `coveredStop`.
        func listed(_ state: AccessibilityPreference.Restoration.State, coveredStop: Date) throws {
            let record = LiveSessionAccessibilityHandback.Record(restoration: AccessibilityPreference.Restoration(udid: "UDID-1", state: state), coveredStop: coveredStop)
            try record.write(to: layout.accessibilityHandback)
        }

        /// Another session on this device whose runner is gone, never ended; `stoppedAt`, in seconds since 1970, is its idle exit, and `nil` leaves it no stop at all.
        func sibling(_ id: String, stoppedAt: TimeInterval?) throws {
            let layout = try store.create(id: id)
            try store.write(LiveSessionRecord(id: id, pid: 11, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light))
            if let stoppedAt {
                try LiveSessionChannel(layout: layout).markExit(.idle(after: 900, served: 1, stoppedAt: Date(timeIntervalSince1970: stoppedAt)))
            }
        }

        /// Runs the real `session list` handback at `seconds` since 1970 on a device reading `accessibility`, on its own clock and device, so what it writes is in the session records and nothing is in `vectors`.
        @discardableResult
        func list(at seconds: TimeInterval, accessibility reading: String = "1") throws -> [String: AccessibilityPreference.Restoration] {
            if store.all().compactMap(\.record).allSatisfy({ $0.id != "s1" }) {
                try store.write(LiveSessionRecord(id: "s1", pid: LiveSessionStopTests.pid, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light))
            }
            var key = reading
            var waited: TimeInterval = 0
            return LiveSessionAccessibilityHandback.perform(
                store: store,
                processes: processes,
                leases: LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in false },
                run: { _, arguments in
                    if arguments.contains("write") {
                        key = "1"
                    }
                    return Shell.Result(status: 0, standardOutput: "\(key)\n", standardError: "")
                },
                pause: { waited += $0 },
                now: { Date(timeIntervalSince1970: seconds + waited) }
            )
        }

        func stop(isDeviceBusy: @escaping (Date) -> Bool = { _ in false }) -> LiveSessionStop.Report {
            let record = LiveSessionRecord(id: "s1", pid: LiveSessionStopTests.pid, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light)
            return LiveSessionStop(record: record, store: store, processes: processes, isDeviceBusy: isDeviceBusy).perform(
                run: { [self] _, arguments in
                    vectors.append(arguments)
                    if arguments.contains("write") {
                        accessibility = "1"
                    }
                    let output = arguments.contains("appearance") ? "light" : accessibility
                    return Shell.Result(status: 0, standardOutput: "\(output)\n", standardError: "")
                },
                pause: { [self] seconds in
                    elapsed += seconds
                    onPause()
                },
                now: { [self] in Date(timeIntervalSince1970: origin + elapsed) }
            )
        }
    }
}
