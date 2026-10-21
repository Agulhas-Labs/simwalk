//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `session end` on a simulator's record hands the device back only when no walk holds it.
struct SessionEndTests {
    /// SimWalk#96: a walk's lease on the session's device keeps `end` from writing the device's accessibility — one line says why, and the answer is qualified.
    @Test
    func aLeaseOnTheDeviceKeepsEndFromHandingItBack() throws {
        let directory = try TemporaryDirectory()
        let store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
        _ = try store.create(id: "s1")
        try store.write(LiveSessionRecord(id: "s1", pid: 4242, udid: "UDID-1", app: "com.example.app", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light))
        let leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in true }
        _ = try leases.acquire(udid: "UDID-1", ttl: 1800, holderPID: 1, now: Date(timeIntervalSince1970: 1000), token: "LEASE-1")
        var vectors: [[String]] = []
        var elapsed: TimeInterval = 0
        let shell = Shell { _, arguments, _ in
            vectors.append(arguments)
            return Shell.Result(status: 0, standardOutput: "1\n", standardError: "")
        }

        let answer = try SessionEndCommand.parse(["s1"]).perform(store: store, processes: FakeSessionProcesses(), leases: leases, shell: shell, pause: { elapsed += $0 }, now: { Date(timeIntervalSince1970: 1000 + elapsed) })

        #expect(vectors.isEmpty)
        #expect(answer.residue.contains { $0.hasPrefix("did not hand UDID-1 back: another holder of its lease holds it") })
        #expect(answer.residue.contains { $0.contains("the handback is deferred until another holder of its lease is done with UDID-1 — `simwalk session end s1`") })
        #expect(store.record(id: "s1") != nil)
        #expect(answer.verdict == .reporting(qualifications: ["the device was not handed back: something else is using it"], detail: "ended session s1"))
    }

    /// The lease a session was started under is its caller's, not another holder's: `end` hands the device back while that lease is still held, and a lease with any other token still keeps it from doing so.
    @Test(arguments: [("LEASE-1", true), ("LEASE-2", false)])
    func theLeaseTheSessionWasStartedUnderDoesNotKeepEndFromHandingItBack(held: String, handedBack: Bool) throws {
        let directory = try TemporaryDirectory()
        let store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
        _ = try store.create(id: "s1")
        try store.write(LiveSessionRecord(id: "s1", pid: 4242, udid: "UDID-1", app: "com.example.app", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light, leaseToken: "LEASE-1"))
        let leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in true }
        _ = try leases.acquire(udid: "UDID-1", ttl: 1800, holderPID: 1, now: Date(timeIntervalSince1970: 1000), token: held)
        var vectors: [[String]] = []
        var elapsed: TimeInterval = 0
        let shell = Shell { _, arguments, _ in
            vectors.append(arguments)
            return Shell.Result(status: 0, standardOutput: "1\n", standardError: "")
        }

        let answer = try SessionEndCommand.parse(["s1"]).perform(store: store, processes: FakeSessionProcesses(), leases: leases, shell: shell, pause: { elapsed += $0 }, now: { Date(timeIntervalSince1970: 1000 + elapsed) })

        #expect(vectors.isEmpty != handedBack)
        #expect(answer.residue.contains { $0.hasPrefix("did not hand UDID-1 back") } != handedBack)
    }

    /// SimWalk#128: a clone whose lease, the session's own, has lapsed awaits deletion, and no holder will ever be done with it — so `end` removes the session with nothing handed back and says why in one line, rather than deferring to an `end` that would run `simctl` against a deleted device.
    @Test
    func aSessionsOwnLapsedCloneLeaseIsRemovedWithoutAHandback() throws {
        let fixture = try Fixture()
        _ = try fixture.leases.acquire(udid: "UDID-1", ttl: 60, holderPID: 1, now: Date(timeIntervalSince1970: 0), createdDevice: true, token: "LEASE-1")

        let answer = try fixture.end()

        #expect(fixture.vectors.isEmpty)
        #expect(fixture.store.record(id: "s1") == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.store.layout(id: "s1").directory.path))
        #expect(answer.residue.contains(Self.ownLeaseLine))
        #expect(answer.verdict == .reporting(qualifications: [], detail: "ended session s1"))
    }

    /// SimWalk#128: the same for a clone whose lease, the session's own, a release is retiring while `end` runs.
    @Test
    func aSessionsOwnLeaseBeingReleasedIsRemovedWithoutAHandback() throws {
        let fixture = try Fixture()
        _ = try fixture.leases.acquire(udid: "UDID-1", ttl: 1800, holderPID: 1, now: Date(timeIntervalSince1970: 1000), createdDevice: true, token: "LEASE-1")
        var answer: Answer?

        let released = try fixture.leases.retire(udid: "UDID-1", token: "LEASE-1") { _ in answer = try fixture.end() }

        #expect(released)
        #expect(fixture.vectors.isEmpty)
        #expect(fixture.store.record(id: "s1") == nil)
        #expect(answer?.residue.contains(Self.ownLeaseLine) == true)
        #expect(answer?.verdict == .reporting(qualifications: [], detail: "ended session s1"))
    }
}

extension SessionEndTests {
    static var ownLeaseLine: String {
        "did not hand UDID-1 back: the session's own lease is no longer held (lapsed, or being released), so the device awaits deletion and nothing was handed back"
    }

    /// A stopped session `s1` on `UDID-1` started under lease `LEASE-1`, a lease store whose holders are alive, and a device that records every command run on it, on a clock starting at 1000 s that moves only when `end` pauses.
    final class Fixture {
        let directory: TemporaryDirectory
        let store: LiveSessionStore
        let leases: LeaseStore
        private(set) var vectors: [[String]] = []
        private var elapsed: TimeInterval = 0

        init() throws {
            directory = try TemporaryDirectory()
            store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
            _ = try store.create(id: "s1")
            try store.write(LiveSessionRecord(id: "s1", pid: 4242, udid: "UDID-1", app: "com.example.app", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light, leaseToken: "LEASE-1"))
            leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in true }
        }

        func end() throws -> Answer {
            let shell = Shell { [self] _, arguments, _ in
                vectors.append(arguments)
                return Shell.Result(status: 0, standardOutput: "1\n", standardError: "")
            }
            return try SessionEndCommand.parse(["s1"]).perform(store: store, processes: FakeSessionProcesses(), leases: leases, shell: shell, pause: { [self] in elapsed += $0 }, now: { [self] in Date(timeIntervalSince1970: 1000 + elapsed) })
        }
    }
}
