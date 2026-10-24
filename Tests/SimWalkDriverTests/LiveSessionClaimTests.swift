//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A start's claim on a device: of any number of starts reclaiming one dead claim at the same instant, exactly one gets it.
struct LiveSessionClaimTests {
    private static let deadHolder: Int32 = 900_000
    private static let starts = 8
    private static let rounds = 150
    /// Seconds a wait that succeeds at once allows before it is called failed: far above any scheduling delay, since under a machine load of ~120 a global-queue block missed a 10-second budget (SimWalk#204), and only a hang ever spends it.
    private static let ceiling = 120.0

    /// The reclaim's read, judge, remove and create is one step: a start that finds the claim's lock held waits for it rather than reclaiming beside its holder, and takes the claim once it is released.
    ///
    /// This pins the property itself. The race it closes — a start removing the *fresh* claim another has just re-created — sits between two adjacent statements, so no stress run can be relied on to hit it.
    @Test
    func aStartWaitsOutAnotherReclaimInProgress() throws {
        let directory = try TemporaryDirectory()
        let store = LiveSessionStore(directory: directory.url)
        let claim = store.claim(udid: "UDID-1")
        try FileManager.default.createDirectory(at: claim.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\(Self.deadHolder) dead\n".utf8).write(to: claim)
        let lock = open(claim.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
        #expect(lock >= 0)
        #expect(flock(lock, LOCK_EX) == 0)
        defer { close(lock) }

        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let results = Results()
        DispatchQueue.global().async {
            started.signal()
            results.add(Result { try LiveSessionClaim.take(udid: "UDID-1", in: store, holder: 801_001, isAlive: { $0 == 801_001 }) })
            finished.signal()
        }

        // The start is running before the window opens, so the window measures the start rather than when the queue got to it.
        #expect(started.wait(timeout: .now() + Self.ceiling) == .success)
        #expect(finished.wait(timeout: .now() + 0.4) == .timedOut, "the start took the claim while another reclaim held its lock")
        #expect(flock(lock, LOCK_UN) == 0)
        #expect(finished.wait(timeout: .now() + Self.ceiling) == .success)
        #expect(results.winners == 1)
    }

    /// Every round leaves a dead claimant's claim and sets several starts on it at once; the winners of a round are counted, and there must be one.
    @Test
    func startsReclaimingTheSameDeadClaimNeverBothGetIt() throws {
        let directory = try TemporaryDirectory()
        let store = LiveSessionStore(directory: directory.url)
        let holders = (1 ... Self.starts).map { Int32(800_000 + $0) }
        let isAlive: @Sendable (Int32) -> Bool = { holders.contains($0) }
        for round in 0 ..< Self.rounds {
            let udid = "UDID-\(round)"
            try FileManager.default.createDirectory(at: store.claim(udid: udid).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("\(Self.deadHolder) dead\n".utf8).write(to: store.claim(udid: udid))
            let results = Results()
            let startGun = DispatchSemaphore(value: 0)
            let done = DispatchGroup()
            for holder in holders {
                DispatchQueue.global().async(group: done) {
                    startGun.wait()
                    results.add(Result { try LiveSessionClaim.take(udid: udid, in: store, holder: holder, isAlive: isAlive) })
                }
            }
            for _ in holders {
                startGun.signal()
            }
            done.wait()
            #expect(results.winners == 1, "round \(round): \(results.winners) starts hold the claim")
            if results.winners != 1 {
                return
            }
        }
    }
}

private extension LiveSessionClaimTests {
    final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [Result<LiveSessionClaim, any Error>] = []

        func add(_ result: Result<LiveSessionClaim, any Error>) {
            lock.lock()
            defer { lock.unlock() }
            all.append(result)
        }

        var winners: Int {
            lock.lock()
            defer { lock.unlock() }
            return all.filter {
                if case .success = $0 {
                    true
                } else {
                    false
                }
            }.count
        }
    }
}
