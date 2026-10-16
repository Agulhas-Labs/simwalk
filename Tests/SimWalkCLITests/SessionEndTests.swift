//
// Copyright © Agulhas Labs
//

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
        #expect(answer.residue.contains { $0.hasPrefix("did not hand UDID-1 back") })
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
}
