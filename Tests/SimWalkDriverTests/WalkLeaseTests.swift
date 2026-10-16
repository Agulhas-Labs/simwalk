//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A walk that names no lease takes one on the device it resolves, and the taking is the choice: two walks starting together can never fall on one device.
struct WalkLeaseTests {
    /// G3: walkers starting at once over one list each win a lease on a different device — a choice made from a snapshot of the store would send them all to the first.
    @Test
    func walkersStartingTogetherEachTakeADifferentDevice() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let devices = (1 ... 6).map { Simulator(udid: "UDID-\($0)", name: "iPhone 17", osVersion: "26.0", isBooted: $0.isMultiple(of: 2)) }
        let taken = Taken()

        DispatchQueue.concurrentPerform(iterations: devices.count) { walker in
            taken.add(Result { try WalkLease.take(nil, among: devices, store: store, holderPID: Int32(1000 + walker), now: Self.start).simulator.udid })
        }

        #expect(taken.failures == 0)
        #expect(Set(taken.udids).count == devices.count)
        #expect(store.all().count == devices.count)
    }

    /// Sixteen walks started together on one phone: the store's exclusive create gives one winner and fifteen refusals naming the holder.
    @Test
    func sixteenPhysicalTakesOfOnePhoneHaveExactlyOneWinner() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let outcomes = PhysicalOutcomes()

        DispatchQueue.concurrentPerform(iterations: 16) { attempt in
            outcomes.add(Result { try WalkLease.takePhysical(udid: "PHONE-1", store: store, holderPID: Int32(1000 + attempt), now: Self.start) })
        }

        #expect(outcomes.won == 1)
        #expect(outcomes.held == 15)
        #expect(store.all().count == 1)
        #expect(store.all().first?.lease.physicalDevice == true)
    }

    /// A lease written before the phone could be leased has no `physicalDevice` key, and is a simulator's.
    @Test
    func aLeaseFileWithoutThePhysicalKeyDecodesAsASimulator() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let old = #"{"token":"T","holderPID":5,"createdAt":"2026-10-01T00:00:00Z","expiresAt":"2126-10-01T00:00:00Z","createdDevice":false}"#
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        try old.write(to: directory.url.appendingPathComponent("SIM-1.json"), atomically: true, encoding: .utf8)

        let lease = try #require(try store.lease(onDevice: "SIM-1"))

        #expect(lease.physicalDevice == nil)
    }

    /// Booted devices are taken before shut-down ones, in list order within each; a leased one is passed over.
    @Test
    func abootedDeviceIsTakenFirstAndALeasedOneIsPassedOver() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let devices = Self.devices
        _ = try store.acquire(udid: "BOOTED-A", ttl: 60, holderPID: 41, now: Self.start)

        let first = try WalkLease.take(nil, among: devices, store: store, holderPID: 42, now: Self.start)
        let second = try WalkLease.take(nil, among: devices, store: store, holderPID: 43, now: Self.start)

        #expect(first.simulator.udid == "BOOTED-B")
        #expect(first.lease.taken)
        #expect(try store.lease(onDevice: "BOOTED-B")?.token == first.lease.token)
        #expect(second.simulator.udid == "SHUTDOWN-A")
    }

    /// A name narrows the candidates, and a named device with none free is refused naming the holder of the first — the booted one.
    @Test
    func anamedDeviceWithNoneFreeIsRefusedNamingItsHolder() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let held = try store.acquire(udid: "BOOTED-A", ttl: 60, holderPID: 41, now: Self.start)
        _ = try store.acquire(udid: "SHUTDOWN-A", ttl: 60, holderPID: 42, now: Self.start)

        #expect(throws: LeaseError.held(udid: "BOOTED-A", holderPID: 41, expiresAt: held.expiresAt)) {
            try WalkLease.take("iPhone A", among: Self.devices, store: store, holderPID: 43, now: Self.start)
        }
        #expect(try WalkLease.take("iPhone B", among: Self.devices, store: store, holderPID: 43, now: Self.start).simulator.udid == "BOOTED-B")
    }

    /// Nothing named and nothing free, no devices at all, and a name nothing answers to are each refused as themselves.
    @Test
    func nothingFreeNoDevicesAndAnUnknownNameAreRefusedAsThemselves() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let one = [Simulator(udid: "UDID-1", name: "iPhone 17", osVersion: "26.0", isBooted: true)]
        _ = try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)

        #expect(throws: LeaseError.noUnleasedDevice(runtime: "iOS")) {
            try WalkLease.take(nil, among: one, store: store, holderPID: 42, now: Self.start)
        }
        #expect(throws: SimulatorError.noDevices) {
            try WalkLease.take(nil, among: [], store: store, holderPID: 42, now: Self.start)
        }
        #expect(throws: SimulatorError.noSuchDevice(requested: "iPhone 99", available: ["iPhone 17"])) {
            try WalkLease.take("iPhone 99", among: one, store: store, holderPID: 42, now: Self.start)
        }
    }

    /// A store that cannot be written is the machine, not a busy device: it is thrown at once rather than passed over for the next candidate.
    @Test
    func astoreThatCannotBeWrittenIsThrownRatherThanReadAsBusy() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let store = LeaseStore(directory: file, isAlive: { _ in true })

        #expect {
            try WalkLease.take(nil, among: Self.devices, store: store, holderPID: 42, now: Self.start)
        } throws: { error in
            guard case .storeFailed = error as? LeaseError else { return false }
            return true
        }
    }

    /// A lease the walk took is released by its token; one handed in with `--lease` is its holder's and stays.
    @Test
    func onlyALeaseTheWalkTookIsReleased() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let handed = try store.acquire(udid: "BOOTED-A", ttl: 60, holderPID: 41, now: Self.start)
        let taken = try WalkLease.take("BOOTED-B", among: Self.devices, store: store, holderPID: 42, now: Self.start).lease

        taken.release()
        WalkLease(store: store, udid: "BOOTED-A", token: handed.token, taken: false).release()

        #expect(store.all().map(\.udid) == ["BOOTED-A"])
    }

    /// Renewal answers `nil` while the lease holds, and why not once it has lapsed.
    @Test
    func renewalSaysWhyALapsedLeaseCannotBeRenewed() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try WalkLease.take(nil, among: Self.devices, store: store, holderPID: 42, now: Self.start).lease

        let renewed = lease.renew(now: Self.start.addingTimeInterval(60))
        let lapsed = lease.renew(now: Self.start.addingTimeInterval(3 * WalkLease.ttl))

        #expect(renewed == nil)
        #expect(try store.lease(onDevice: lease.udid)?.expiresAt == Self.start.addingTimeInterval(60 + WalkLease.ttl))
        #expect(lapsed?.contains("expired") == true)
    }

    private static let start = Date(timeIntervalSince1970: 1_000_000)

    /// Two names, each a booted and a shut-down device, listed shut-down first so the order `take` imposes is its own.
    private static var devices: [Simulator] {
        [
            Simulator(udid: "SHUTDOWN-A", name: "iPhone A", osVersion: "26.0", isBooted: false),
            Simulator(udid: "BOOTED-A", name: "iPhone A", osVersion: "26.0", isBooted: true),
            Simulator(udid: "SHUTDOWN-C", name: "iPhone B", osVersion: "26.0", isBooted: false),
            Simulator(udid: "BOOTED-B", name: "iPhone B", osVersion: "26.0", isBooted: true),
        ]
    }
}

extension WalkLeaseTests {
    /// The devices concurrent walkers took, gathered from every thread.
    final class Taken: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var udids: [String] = []
        private(set) var failures = 0

        func add(_ result: Result<String, Error>) {
            lock.withLock {
                switch result {
                case let .success(udid): udids.append(udid)
                case .failure: failures += 1
                }
            }
        }
    }

    final class PhysicalOutcomes: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var won = 0
        private(set) var held = 0

        func add(_ result: Result<WalkLease, Error>) {
            lock.withLock {
                switch result {
                case .success: won += 1
                case let .failure(error): if case .held = error as? LeaseError {
                        held += 1
                    }
                }
            }
        }
    }
}
