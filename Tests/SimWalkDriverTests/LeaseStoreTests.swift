//
// Copyright © Agulhas Labs
//

import Foundation
import os
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A lease is only worth taking if two callers cannot both hold one device: the store's `O_EXCL` create is the whole guarantee, and a reclaim must never remove a lease somebody else has just taken.
struct LeaseStoreTests {
    /// G3: many acquisitions of one device at once, and exactly one wins; every other is refused as held.
    @Test
    func concurrentAcquisitionsOfOneDeviceHaveExactlyOneWinner() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let outcomes = Outcomes()

        DispatchQueue.concurrentPerform(iterations: 16) { attempt in
            outcomes.add(Result { try store.acquire(udid: "UDID-1", ttl: 60, holderPID: Int32(1000 + attempt), now: Self.start) })
        }

        #expect(outcomes.won == 1)
        #expect(outcomes.refused == 15)
        #expect(store.all().count == 1)
    }

    /// And one after another: the second acquisition finds the first's lease and is refused naming its holder.
    @Test
    func asecondAcquisitionIsRefusedNamingTheHolderAndExpiry() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let first = try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)

        #expect(throws: LeaseError.held(udid: "UDID-1", holderPID: 41, expiresAt: first.expiresAt)) {
            try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 42, now: Self.start)
        }
    }

    /// A renewal extends a lease to `now + ttl` and never shortens it: a walk renewing for 30 minutes under a lease its caller took for two hours keeps the two hours.
    @Test
    func arenewalExtendsALeaseAndNeverShortensIt() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "UDID-1", ttl: 7200, holderPID: 41, now: Self.start)

        let kept = try store.renew(token: lease.token, ttl: 60, now: Self.start.addingTimeInterval(10))
        let extended = try store.renew(token: lease.token, ttl: 7200, now: Self.start.addingTimeInterval(3600))

        #expect(kept.expiresAt == lease.expiresAt)
        #expect(extended.expiresAt == Self.start.addingTimeInterval(3600 + 7200))
        #expect(try store.lease(onDevice: "UDID-1") == extended)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).filter { $0.hasSuffix(".tmp") }.isEmpty)
    }

    /// A lease whose holder has exited is reclaimable by anyone, so it is not renewed — nor one that has expired, nor a token nothing carries.
    @Test
    func arenewalRefusesALeaseThatNoLongerHoldsItsDevice() throws {
        let directory = try TemporaryDirectory()
        let dead = LeaseStore(directory: directory.url, isAlive: { _ in false })
        let lease = try dead.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)

        #expect(throws: LeaseError.holderExited(udid: "UDID-1", holderPID: 41)) {
            try dead.renew(token: lease.token, ttl: 60, now: Self.start)
        }
        #expect(throws: LeaseError.expired(udid: "UDID-1", expiresAt: lease.expiresAt)) {
            try LeaseStore(directory: directory.url, isAlive: { _ in true }).renew(token: lease.token, ttl: 60, now: lease.expiresAt)
        }
        #expect(throws: LeaseError.noSuchLease) {
            try dead.renew(token: "not-a-token", ttl: 60, now: Self.start)
        }
        #expect(try dead.lease(onDevice: "UDID-1") == lease)
    }

    /// An expired lease, or one whose holder is gone, is reclaimed by the next acquisition.
    @Test(arguments: [(Self.start.addingTimeInterval(61), true), (Self.start, false)])
    func anexpiredOrOrphanedLeaseIsReclaimed(now: Date, holderAlive: Bool) throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { $0 != 41 || holderAlive })
        _ = try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)

        let second = try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 42, now: now)

        #expect(store.entry(token: second.token)?.lease.holderPID == 42)
        #expect(store.all().count == 1)
    }

    /// A removal names the lease it read: a token that is no longer the device's removes nothing.
    @Test
    func aremovalByAStaleTokenLeavesTheNewLeaseInPlace() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)

        #expect(try !store.remove(udid: "UDID-1", token: "someone-elses"))
        #expect(store.entry(token: lease.token) != nil)
    }

    /// A lease file that does not decode keeps its device: what cannot be read cannot be judged free.
    @Test
    func anunreadableLeaseIsNeverReclaimed() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        try Data("{".utf8).write(to: store.url(for: "UDID-1"))

        #expect(throws: LeaseError.unreadable(path: store.url(for: "UDID-1").path)) {
            try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 42, now: Self.start)
        }
        #expect(store.held(now: Self.start).keys.contains("UDID-1"))
    }

    /// A write that stops part way leaves nothing at the lease path — not an empty file no read could judge and no acquisition could ever reclaim — and no temporary file either.
    @Test
    func aninterruptedWriteLeavesNoLeaseFile() throws {
        let directory = try TemporaryDirectory()
        var store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        store.writeBytes = { _, _ in false }

        #expect(throws: LeaseError.self) {
            try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)
        }
        #expect(!FileManager.default.fileExists(atPath: store.url(for: "UDID-1").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == [".lock"])
    }

    /// A release whose token the device no longer carries is not that release's: nothing is run and the lease on the device is left as it is.
    @Test
    func aretireByAStaleTokenTouchesNothing() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true)
        var ran = false

        let retired = try store.retire(udid: "CLONE-1", token: "someone-elses") { _ in ran = true }

        #expect(!retired)
        #expect(!ran)
        #expect(store.entry(token: lease.token) != nil)
    }

    /// While a release is deleting its device the device is held, and no acquisition can take it; a prune leaves that release alone.
    @Test
    func adeviceBeingReleasedIsHeldAndLeftToItsRelease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true)
        var heldDuring: [String: DeviceLease?] = [:]
        var finishedDuring: [String] = []

        _ = try store.retire(udid: "CLONE-1", token: lease.token) { _ in
            heldDuring = store.held(now: Self.start)
            finishedDuring = store.finishAbandonedReleases(dryRun: false) { _ in }.map(\.entry.udid)
            #expect(throws: LeaseError.awaitingDeletion(udid: "CLONE-1")) {
                try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 42, now: Self.start)
            }
        }

        #expect(heldDuring.keys.sorted() == ["CLONE-1"])
        #expect(finishedDuring.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == [".lock"])
    }

    /// A release a crash cut short leaves its tombstone, which the next prune finishes by the UDID it names.
    @Test
    func atombstoneACrashLeftIsFinished() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true)
        try FileManager.default.moveItem(at: store.url(for: "CLONE-1"), to: directory.url.appendingPathComponent("CLONE-1.releasing.\(lease.token)"))
        var finished: [String] = []

        let named = store.finishAbandonedReleases(dryRun: true) { _ in Issue.record("a dry run finished a release") }
        let released = store.finishAbandonedReleases(dryRun: false) { finished.append($0.udid) }

        #expect(named.map(\.entry.udid) == ["CLONE-1"])
        #expect(released.map(\.entry) == [LeaseStore.Entry(udid: "CLONE-1", lease: lease)])
        #expect(finished == ["CLONE-1"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == [".lock"])
    }

    /// SimWalk#76: the store's own lock is free once a call returns even while a copy of its descriptor is still open — as a spawning child's is until its exec — and the file is opened close-on-exec.
    @Test
    func theStoresLockIsFreeOnReturnWhileACopyOfItsDescriptorIsStillOpen() throws {
        let directory = try TemporaryDirectory()
        var store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let copies = OSAllocatedUnfairLock(initialState: [Int32]())
        let flags = OSAllocatedUnfairLock<Int32>(initialState: 0)
        store.takeLock = { descriptor, operation in
            copies.withLock { $0.append(dup(descriptor)) }
            flags.withLock { $0 = fcntl(descriptor, F_GETFD) }
            return flock(descriptor, operation)
        }
        defer { copies.withLock { $0.forEach { close($0) } } }

        try store.remove(udid: "U", token: "t")
        let fresh = open(directory.url.appendingPathComponent(".lock").path, O_RDWR | O_CLOEXEC)
        defer { close(fresh) }

        #expect(copies.withLock { $0.count } == 1)
        #expect(flags.withLock { $0 } & FD_CLOEXEC != 0)
        #expect(fresh >= 0)
        #expect(flock(fresh, LOCK_EX | LOCK_NB) == 0)
    }

    /// SimWalk#71: a dry run lets go of the tombstone's lock rather than only closing it, so a copy of its descriptor — which a child another thread is spawning holds until its exec — cannot keep it held, and the real run that follows finishes the release.
    @Test
    func adryRunsLockDoesNotOutliveItInACopyOfItsDescriptor() throws {
        let directory = try TemporaryDirectory()
        var store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let copies = OSAllocatedUnfairLock(initialState: [Int32]())
        store.takeLock = { descriptor, operation in
            let taken = flock(descriptor, operation)
            if taken == 0 {
                copies.withLock { $0.append(dup(descriptor)) }
            }
            return taken
        }
        defer { copies.withLock { $0.forEach { close($0) } } }
        let lease = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true)
        try FileManager.default.moveItem(at: store.url(for: "CLONE-1"), to: directory.url.appendingPathComponent("CLONE-1.releasing.\(lease.token)"))
        var finished: [String] = []

        let named = store.finishAbandonedReleases(dryRun: true) { _ in Issue.record("a dry run finished a release") }
        let released = store.finishAbandonedReleases(dryRun: false) { finished.append($0.udid) }

        #expect(named.map(\.entry.udid) == ["CLONE-1"])
        #expect(released.map(\.entry.udid) == ["CLONE-1"])
        #expect(finished == ["CLONE-1"])
    }

    /// SimWalk#71 / #73 item 11: a tombstone whose lock fails for any reason but being held is reported with its errno, not taken for a release still running and left unsaid.
    @Test
    func atombstoneWhoseLockFailsIsReportedWithItsErrno() throws {
        let directory = try TemporaryDirectory()
        var store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        store.takeLock = { _, _ in
            errno = EBADF
            return -1
        }
        let lease = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true)
        let tombstone = directory.url.appendingPathComponent("CLONE-1.releasing.\(lease.token)")
        try FileManager.default.moveItem(at: store.url(for: "CLONE-1"), to: tombstone)

        let released = store.finishAbandonedReleases(dryRun: false) { _ in Issue.record("a release whose lock failed was run") }

        #expect(released.map(\.entry.udid) == ["CLONE-1"])
        #expect(released.first?.failure?.contains("(errno \(EBADF))") == true)
        #expect(FileManager.default.fileExists(atPath: tombstone.path))
    }

    private static let start = Date(timeIntervalSince1970: 1_000_000)
}

extension LeaseStoreTests {
    /// What the concurrent acquisitions came to, gathered from every thread.
    final class Outcomes: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var won = 0
        private(set) var refused = 0

        func add(_ result: Result<DeviceLease, Error>) {
            lock.withLock {
                switch result {
                case .success: won += 1
                case .failure: refused += 1
                }
            }
        }
    }
}
