//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `session list`'s accessibility handback for a session whose runner stopped without `end`: made once, and only on a device nothing else is using.
struct LiveSessionAccessibilityHandbackTests {
    /// A `session start` holding its claim — before its `session.json` exists, while it builds, settles or reboots the device — keeps a stale session's device from being handed back, and the `list` after the claim goes makes the restore (#73 item 4).
    @Test
    func astartHoldingItsClaimDefersTheHandbackUntilItsClaimantIsGone() throws {
        let fixture = try Fixture()
        try fixture.staleSession("stale")
        fixture.processes.alive.insert(777)
        _ = try LiveSessionStart(store: fixture.store, processes: fixture.processes).claim(udid: "UDID-1", holder: 777)

        let whileClaimed = fixture.perform()
        let touchedWhileClaimed = fixture.device.calls
        fixture.processes.alive.remove(777)
        let afterward = fixture.perform()

        #expect(whileClaimed.isEmpty)
        #expect(touchedWhileClaimed.isEmpty)
        #expect(afterward["stale"]?.state == .restored)
    }

    /// A walk holds a lease on its device for as long as it runs, and may reboot it: a stale session's device under a live lease is not handed back (#73 item 4).
    @Test
    func adeviceUnderALiveLeaseIsNotHandedBack() throws {
        let fixture = try Fixture()
        try fixture.staleSession("stale")
        _ = try fixture.leases.acquire(udid: "UDID-1", ttl: 60, holderPID: Fixture.walkPID, now: Date(timeIntervalSince1970: 0))

        let handbacks = fixture.perform()

        #expect(handbacks.isEmpty)
        #expect(fixture.device.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.layout(id: "stale").accessibilityHandback.path))
    }

    /// A session started with `--lease T` has T held by its own caller: `list` hands its device back, while a lease with another token still keeps it from doing so.
    @Test(arguments: [("LEASE-1", true), ("LEASE-2", false)])
    func asessionsOwnLeaseDoesNotKeepListFromHandingItsDeviceBack(held: String, handedBack: Bool) throws {
        let fixture = try Fixture()
        _ = try fixture.store.create(id: "stale")
        try fixture.store.write(LiveSessionRecord(id: "stale", pid: 11, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light, leaseToken: "LEASE-1"))
        _ = try fixture.leases.acquire(udid: "UDID-1", ttl: 60, holderPID: Fixture.walkPID, now: Date(timeIntervalSince1970: 0), token: held)

        let handbacks = fixture.perform()

        #expect(handbacks.isEmpty != handedBack)
        #expect(fixture.device.calls.isEmpty != handedBack)
    }

    /// A walk under the stopped session's own lease token is still a walk: the token's exemption does not cover its claim, so `list` leaves the device alone until the walk ends (SimWalk#128).
    @Test
    func awalkUnderTheSessionsOwnLeaseKeepsListFromHandingItsDeviceBack() throws {
        let fixture = try Fixture()
        _ = try fixture.store.create(id: "stale")
        try fixture.store.write(LiveSessionRecord(id: "stale", pid: 11, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light, leaseToken: "LEASE-1"))
        _ = try fixture.leases.acquire(udid: "UDID-1", ttl: 60, holderPID: Fixture.walkPID, now: Date(timeIntervalSince1970: 0), token: "LEASE-1")
        fixture.processes.alive.insert(Fixture.walkPID)
        _ = try WalkClaim.take(udid: "UDID-1", in: fixture.leases, holder: Fixture.walkPID, isAlive: fixture.processes.isAlive)

        let whileWalking = fixture.perform()
        let touchedWhileWalking = fixture.device.calls
        fixture.processes.alive.remove(Fixture.walkPID)
        let afterward = fixture.perform()

        #expect(whileWalking.isEmpty)
        #expect(touchedWhileWalking.isEmpty)
        #expect(afterward["stale"]?.state == .restored)
    }

    /// A `session start` building on the device has no `session.json` yet, so no record names it: its claim is still read, for a device the records handed to `busyDevices` do not include (SimWalk#128).
    @Test
    func astartClaimOnADeviceNoRecordNamesIsSeenAsBusy() throws {
        let fixture = try Fixture()
        fixture.processes.alive.insert(777)
        _ = try LiveSessionStart(store: fixture.store, processes: fixture.processes).claim(udid: "UDID-1", holder: 777)

        let busy = LiveSessionAccessibilityHandback.busyDevices(of: [], store: fixture.store, processes: fixture.processes, leases: fixture.leases, now: Date(timeIntervalSince1970: 0))

        #expect(busy == ["UDID-1"])
    }

    /// A session that stopped long ago on a device whose accessibility something else has since switched back on — a walk's handback, another session's `end` — has nothing to hand back: `list` neither waits out the teardown budget for a teardown that landed an hour ago nor writes, and records no "a later teardown may undo" qualification for good (#73 item 3).
    @Test
    func adeviceFoundOnLongAfterItsSessionStoppedIsNotWaitedOnOrQualified() throws {
        let fixture = try Fixture(accessibility: "1", start: Date(timeIntervalSince1970: 3600))
        try fixture.staleSession("stale", stoppedAt: Date(timeIntervalSince1970: 0))

        let handback = try #require(fixture.perform()["stale"])

        #expect(handback.qualification == nil)
        #expect(fixture.device.writes.isEmpty)
        #expect(fixture.paused < 1)
        #expect(LiveSessionAccessibilityHandback.line(handback).hasSuffix("nothing to hand back"))
    }

    /// A session whose runner crashed or was killed, leaving no exit record, gets the whole teardown wait however long ago its directory was last written, and keeps the "a later teardown may undo" qualification.
    ///
    /// The last write bounds the stop only from below. Two minutes is a runner idle since its last request, past the teardown budget but inside the idle timeout, killed a moment before `list` with its teardown still to come — taken as long past, the key reading on would be recorded `.alreadyOn` and the teardown would leave the device off under it. An hour is past the standard idle timeout, which a `start` override can lengthen and a step that has not returned outlasts (#76 item 6).
    @Test(arguments: [1, 120, 3600] as [TimeInterval])
    func acrashedSessionIsWaitedOnHoweverLongAgoItLastWrote(secondsBeforeList: TimeInterval) throws {
        let list = Date(timeIntervalSince1970: 7200)
        let fixture = try Fixture(accessibility: "1", start: list)
        try fixture.staleSession("crashed")
        try fixture.lastWrote("crashed", at: list.addingTimeInterval(-secondsBeforeList))

        let handback = try #require(fixture.perform()["crashed"])

        #expect(handback.state == .restoredWithoutTeardown)
        #expect(handback.qualification != nil)
        #expect(fixture.paused > 10)
        #expect(fixture.device.writes.count == AccessibilityPreference.keys.count)
    }

    /// A runner that died without `exit.json` but kept beating until it died is bounded by its last beat: once that bound plus the teardown's budget has passed, a device found back on is not waited on, written or qualified (SimWalk#91 item 10).
    @Test
    func acrashedSessionWhoseHeartbeatBoundIsLongPastIsNotWaitedOnOrQualified() throws {
        let list = Date(timeIntervalSince1970: 7200)
        let fixture = try Fixture(accessibility: "1", start: list)
        try fixture.staleSession("crashed")
        try fixture.beat("crashed", at: list.addingTimeInterval(-60))

        let handback = try #require(fixture.perform()["crashed"])

        #expect(handback.state == .alreadyOn)
        #expect(handback.qualification == nil)
        #expect(fixture.device.writes.isEmpty)
        #expect(fixture.paused < 1)
    }

    /// A runner that beat a moment ago is waited on from its bound — the beat plus three intervals — rather than from now: a teardown can still be coming, but not for the whole budget.
    @Test
    func acrashedSessionWithARecentHeartbeatIsWaitedOnFromItsBound() throws {
        let list = Date(timeIntervalSince1970: 7200)
        let fixture = try Fixture(accessibility: "1", start: list)
        try fixture.staleSession("crashed")
        // Bound at 4 s before `list`, so the teardown's 10 s budget leaves 6 s of wait, then the 2.5 s confirmation.
        try fixture.beat("crashed", at: list.addingTimeInterval(-10))

        let handback = try #require(fixture.perform()["crashed"])

        #expect(handback.state == .restoredWithoutTeardown)
        // Exactly: a bound of two intervals or four waits 4 s or 8 s before the confirmation, and a lower limit alone (`>= 6`, the confirmation included) let the earlier one through.
        #expect(fixture.paused == 6 + 2.5)
    }

    /// `exit.json` says when the runner stopped, and wins over a beat that bounds it later.
    @Test
    func anexitRecordWinsOverTheHeartbeat() throws {
        let list = Date(timeIntervalSince1970: 7200)
        let fixture = try Fixture(accessibility: "1", start: list)
        try fixture.staleSession("idle", stoppedAt: Date(timeIntervalSince1970: 0))
        try fixture.beat("idle", at: list.addingTimeInterval(-1))

        let handback = try #require(fixture.perform()["idle"])

        #expect(handback.state == .alreadyOn)
        #expect(fixture.paused < 1)
    }

    /// SimWalk#92: two stopped sessions on one device get one restore, dated from the later stop — not from whichever sorts first.
    ///
    /// Dated from the old session's stop, the key reads on before the recent one's teardown lands, and both would be recorded `.alreadyOn` over a device the teardown then switches off.
    @Test
    func onerestoreForTwoStoppedSessionsIsDatedFromTheLaterStop() throws {
        let list = Date(timeIntervalSince1970: 3600)
        let fixture = try Fixture(accessibility: "1", start: list)
        try fixture.staleSession("a-old", stoppedAt: Date(timeIntervalSince1970: 0))
        try fixture.staleSession("b-recent", stoppedAt: list.addingTimeInterval(-2))
        fixture.teardownAfter = 3

        let handbacks = fixture.perform()

        #expect(handbacks["a-old"]?.state == .restored)
        #expect(handbacks["b-recent"]?.state == .restored)
        #expect(fixture.device.writes.count == AccessibilityPreference.keys.count)
        // Each record stores the stop the wait ran from: the later stop, the restore having begun after it.
        for id in ["a-old", "b-recent"] {
            #expect(LiveSessionAccessibilityHandback.Record.read(from: fixture.store.layout(id: id).accessibilityHandback)?.coveredStop == list.addingTimeInterval(-2))
        }
    }
}

extension LiveSessionAccessibilityHandbackTests {
    /// A scratch session store and lease store, a scripted device, and a clock that moves only when the handback pauses.
    final class Fixture {
        static let walkPID: Int32 = 555

        let directory: TemporaryDirectory
        let store: LiveSessionStore
        let leases: LeaseStore
        let processes = FakeSessionProcesses()
        let device: Device
        /// After how long paused the device's XCUITest teardown switches accessibility off, when it is still to come.
        var teardownAfter: TimeInterval?
        private var elapsed: TimeInterval = 0
        private let start: Date

        /// `accessibility` is what the deciding key reads before anything writes it; `start` is the clock when the handback begins.
        init(accessibility: String = "0", start: Date = Date(timeIntervalSince1970: 0)) throws {
            directory = try TemporaryDirectory()
            store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
            leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { $0 == Self.walkPID }
            device = Device(accessibility: accessibility)
            self.start = start
        }

        /// How long the handback has paused, in all.
        var paused: TimeInterval {
            elapsed
        }

        /// A session on `UDID-1` whose runner's pid is gone; `stoppedAt`, when given, is when its runner recorded an idle exit.
        func staleSession(_ id: String, stoppedAt: Date? = nil) throws {
            _ = try store.create(id: id)
            try store.write(LiveSessionRecord(id: id, pid: 11, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light))
            if let stoppedAt {
                try LiveSessionChannel(layout: store.layout(id: id)).markExit(.idle(after: 900, served: 1, stoppedAt: stoppedAt))
            }
        }

        /// Writes session `id`'s runner's last heartbeat, as one that beat at `date` and then died.
        func beat(_ id: String, at date: Date) throws {
            try LiveSessionChannel(layout: store.layout(id: id)).markHeartbeat(LiveSessionHeartbeat(writtenAt: date))
        }

        /// Dates session `id`'s directory and everything directly in it to `date`, as a runner that last wrote then leaves it.
        func lastWrote(_ id: String, at date: Date) throws {
            let directory = store.layout(id: id).directory
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) + [directory] {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
        }

        func perform() -> [String: AccessibilityPreference.Restoration] {
            LiveSessionAccessibilityHandback.perform(
                store: store,
                processes: processes,
                leases: leases,
                run: { [device] in device.run($0, $1) },
                pause: { [self] in
                    elapsed += $0
                    if let teardown = teardownAfter, elapsed >= teardown {
                        device.tearDown()
                        teardownAfter = nil
                    }
                },
                now: { [self] in start.addingTimeInterval(elapsed) }
            )
        }
    }

    /// The deciding key as the device's `defaults` holds it: read back as it stands, switched on by a write.
    final class Device: @unchecked Sendable {
        private(set) var calls: [[String]] = []
        private var accessibility: String

        init(accessibility: String) {
            self.accessibility = accessibility
        }

        /// Every write made to the device.
        var writes: [[String]] {
            calls.filter { $0.contains("write") }
        }

        /// The XCUITest teardown landing: the deciding key switched off.
        func tearDown() {
            accessibility = "0"
        }

        func run(_: String, _ arguments: [String]) -> Shell.Result {
            calls.append(arguments)
            if arguments.contains("write") {
                accessibility = "1"
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }
            return Shell.Result(status: 0, standardOutput: "\(accessibility)\n", standardError: "")
        }
    }
}
