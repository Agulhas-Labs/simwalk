//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorServices
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// Which devices a parallel walk takes beside shard 0, in which order, and that its one release gives every one back, deleting only the devices it made, whatever ends the walk (a faked `simctl`, a scratch lease store).
struct ShardDevicePoolTests {
    /// Booted devices like shard 0 first, then shut-down ones, then clones of shard 0 when it was shut down; none is created.
    @Test
    func extrasAreTakenBootedAlikeThenShutDownAlikeThenClonesOfAShutDownShard0() throws {
        let fixture = try Fixture()

        let shards = try fixture.pool.acquire(4, beside: Self.primary(booted: false), now: Self.start)

        #expect(shards.map(\.simulator.udid) == ["ALIKE-BOOTED", "ALIKE-SHUT", "CLONE-1", "CLONE-2"])
        #expect(shards.map(\.origin) == [.existing, .existing, .cloned, .cloned])
        #expect(fixture.script.vectors.filter { $0.starts(with: ["simctl", "clone"]) } == [["simctl", "clone", "PRIMARY", "iPhone 17 (SimWalk lease)"], ["simctl", "clone", "PRIMARY", "iPhone 17 (SimWalk lease)"]])
        #expect(!fixture.script.vectors.contains { $0.starts(with: ["simctl", "create"]) })
        #expect(Set(fixture.store.all().filter { $0.lease.holderPID == Self.walk }.map(\.udid)) == ["ALIKE-BOOTED", "ALIKE-SHUT", "CLONE-1", "CLONE-2"])
        #expect(fixture.store.all().filter(\.lease.createdDevice).map(\.udid).sorted() == ["CLONE-1", "CLONE-2"])
    }

    /// An existing extra found booted is not the walk's to reboot, as a serial walk judges a device it found booted; one found shut down, and every device the walk made, is.
    @Test
    func anExistingExtraFoundBootedMayNotBeRebootedAndEveryOtherExtraMay() throws {
        let fixture = try Fixture()

        let shards = try fixture.pool.acquire(4, beside: Self.primary(booted: false), now: Self.start)
        fixture.pool.release()

        #expect(shards.map(\.simulator.udid) == ["ALIKE-BOOTED", "ALIKE-SHUT", "CLONE-1", "CLONE-2"])
        #expect(shards.map(\.mayReboot) == [false, true, true, true])
    }

    /// Asked for owned devices only — a walkbook whose setup changes the device — the pool passes over the booted existing device, leasing and touching nothing of it, and takes the shut-down one and a clone.
    @Test
    func ownedOnlyPassesOverAnExistingDeviceFoundBooted() throws {
        let fixture = try Fixture()

        let shards = try fixture.pool.acquire(2, beside: Self.primary(booted: false), ownedOnly: true, now: Self.start)

        #expect(shards.map(\.simulator.udid) == ["ALIKE-SHUT", "CLONE-1"])
        #expect(!fixture.store.all().contains { $0.udid == "ALIKE-BOOTED" })
        #expect(!fixture.script.vectors.contains { $0.contains("ALIKE-BOOTED") })
        fixture.pool.release()
    }

    /// A shard 0 found booted is never cloned (`simctl clone` refuses it, and it may be somebody's in use) nor shut down: the extras past the existing ones are new devices of its type and runtime.
    @Test
    func abootedShard0IsNeverClonedOrShutDownAndItsExtrasAreCreatedLikeIt() throws {
        let fixture = try Fixture(primaryBooted: true)

        let shards = try fixture.pool.acquire(3, beside: Self.primary(booted: true), now: Self.start)
        fixture.pool.release()

        #expect(shards.map(\.simulator.udid) == ["ALIKE-BOOTED", "ALIKE-SHUT", "CREATED-1"])
        #expect(shards.last?.origin == .created)
        #expect(shards.last?.simulator.runtimeIdentifier == Self.runtime)
        #expect(shards.last?.simulator.deviceTypeIdentifier == Self.deviceType)
        #expect(fixture.script.vectors.contains(["simctl", "create", "iPhone 17 (SimWalk lease)", Self.deviceType, Self.runtime]))
        #expect(!fixture.script.vectors.contains { $0.contains("PRIMARY") })
    }

    /// A device of another type, of another runtime, or leased by somebody else is never taken, shut down, cloned or deleted, and the other holder's lease stays.
    @Test
    func aDeviceOfAnotherTypeOrRuntimeOrLeasedIsNeverTakenShutDownClonedOrDeleted() throws {
        let fixture = try Fixture()

        let shards = try fixture.pool.acquire(3, beside: Self.primary(booted: false), now: Self.start)
        fixture.pool.release()

        let untouchable = ["OTHER-TYPE", "OTHER-RUNTIME", "LEASED-SHUT"]

        #expect(!shards.contains { untouchable.contains($0.simulator.udid) })
        #expect(!fixture.script.vectors.contains { vector in untouchable.contains { vector.contains($0) } })
        #expect(fixture.store.all().map(\.udid) == ["LEASED-SHUT"])
    }

    /// G4: a throw part-way through acquiring gives back everything acquired so far: the clone made is shut down and deleted, every lease and claim the pool took is gone, and the error is the one thrown.
    @Test
    func athrowPartWayThroughAcquiringReleasesAndDeletesEverythingAcquiredSoFar() throws {
        let fixture = try Fixture(failingSecond: "clone")

        #expect(throws: SimulatorError.self) {
            try fixture.pool.acquire(4, beside: Self.primary(booted: false), now: Self.start)
        }
        #expect(fixture.store.all().map(\.udid) == ["LEASED-SHUT"])
        #expect(fixture.script.vectors.suffix(2) == [["simctl", "shutdown", "CLONE-1"], ["simctl", "delete", "CLONE-1"]])
        #expect(WalkClaim.walkedDevices(in: fixture.store, isAlive: { _ in true }).isEmpty)
        #expect(fixture.pool.release().isEmpty)
    }

    /// The walk's cancel runs the same release: the created device deleted, every lease released.
    @Test
    func acancelRunsTheSameRelease() throws {
        let fixture = try Fixture(primaryBooted: true)
        let cancellation = Cancellation()
        _ = try fixture.pool.acquire(3, beside: Self.primary(booted: true), now: Self.start)
        fixture.pool.release(on: cancellation)

        cancellation.cancel()

        #expect(fixture.store.all().map(\.udid) == ["LEASED-SHUT"])
        #expect(fixture.script.vectors.suffix(2) == [["simctl", "shutdown", "CREATED-1"], ["simctl", "delete", "CREATED-1"]])
        #expect(throws: ShardDevicePoolError.released) {
            try fixture.pool.acquire(1, beside: Self.primary(booted: true), now: Self.start)
        }
    }

    /// A cancel that lands from another thread while a device is being created waits for `simctl create` to return, so the new device is deleted too rather than left behind unleased.
    @Test
    func acancelWhileADeviceIsBeingCreatedWaitsAndDeletesItToo() throws {
        let cancellation = Cancellation()
        let done = DispatchSemaphore(value: 0)
        let fixture = try Fixture(primaryBooted: true) { arguments in
            guard arguments.starts(with: ["simctl", "create"]) else { return }
            Thread.detachNewThread {
                cancellation.cancel()
                done.signal()
            }
        }
        fixture.pool.release(on: cancellation)

        _ = try fixture.pool.acquire(3, beside: Self.primary(booted: true), now: Self.start)
        done.wait()

        #expect(fixture.store.all().map(\.udid) == ["LEASED-SHUT"])
        #expect(fixture.script.vectors.contains(["simctl", "delete", "CREATED-1"]))
    }

    /// A second release runs no command and answers what the first could not give back.
    @Test
    func releasingTwiceRunsNothingTheSecondTime() throws {
        let fixture = try Fixture(primaryBooted: true, failing: "delete")
        _ = try fixture.pool.acquire(3, beside: Self.primary(booted: true), now: Self.start)
        let first = fixture.pool.release()
        let ran = fixture.script.vectors

        let second = fixture.pool.release()

        #expect(fixture.script.vectors == ran)
        #expect(second == first)
        #expect(first.count == 1)
    }

    /// A device that could not be deleted is answered with its UDID, the command that failed and why; its lease is kept, so `simwalk prune` deletes it once the walk is gone.
    @Test
    func aFailedDeleteIsAnsweredWithItsUDIDCommandAndReason() throws {
        let fixture = try Fixture(primaryBooted: true, failing: "delete")
        _ = try fixture.pool.acquire(3, beside: Self.primary(booted: true), now: Self.start)

        let left = fixture.pool.release()

        #expect(left == [ShardDevicePool.Unreleased(udid: "CREATED-1", command: "simctl delete CREATED-1", reason: "An error was encountered processing the command (code=164)")])
        #expect(fixture.store.all().map(\.udid).sorted() == ["CREATED-1", "LEASED-SHUT"])
    }

    /// A device somebody else already deleted is what the release wanted: nothing is answered and its lease is gone.
    @Test
    func aDeviceAlreadyGoneCountsAsDeleted() throws {
        let fixture = try Fixture(primaryBooted: true, gone: "CREATED-1")
        _ = try fixture.pool.acquire(3, beside: Self.primary(booted: true), now: Self.start)

        let left = fixture.pool.release()

        #expect(left.isEmpty)
        #expect(fixture.store.all().map(\.udid) == ["LEASED-SHUT"])
    }

    /// A device the walk made boots as one SimWalk created (its override settled: here `--stock` removes it and says so), and an existing device boots as a serial walk boots one it did not make, with nothing decided.
    @Test
    func aDeviceTheWalkMadeBootsAsCreatedAndAnExistingOneAsASerialWalkBootsIt() throws {
        let fixture = try Fixture()
        let provisioning = SlimWalkProvisioning(shell: Shell(script: fixture.script.run), overrides: fixture.overrides)
        let made = "11111111-2222-3333-4444-0000000000A1"
        let existing = "11111111-2222-3333-4444-0000000000A2"
        let shards = [
            ShardDevicePool.Shard(simulator: Simulator(udid: made, name: "iPhone 17", osVersion: "26.5", isBooted: false), origin: .created),
            ShardDevicePool.Shard(simulator: Simulator(udid: existing, name: "iPhone 17", osVersion: "26.5", isBooted: false), origin: .existing),
        ]
        var booted: [String] = []

        let lines = try shards.map { shard in
            try shard.boot(with: provisioning, stockRequested: true, appPath: nil) { booted.append($0.udid) }
        }

        #expect(booted == [made, existing])
        #expect(lines.map { $0 != nil } == [true, false])
    }

    /// An extra the pool holds has a lease on its token that the pool alone releases; a device it does not hold has none.
    @Test
    func aHeldExtraHasALeaseOnItsTokenAndAnotherDeviceHasNone() throws {
        let fixture = try Fixture()
        let shards = try fixture.pool.acquire(1, beside: Self.primary(booted: false), now: Self.start)
        let shard = try #require(shards.first)

        let lease = try #require(fixture.pool.lease(for: shard))

        #expect(lease.udid == shard.simulator.udid)
        #expect(lease.token == fixture.store.all().first { $0.udid == shard.simulator.udid }?.lease.token)
        #expect(!lease.taken)
        #expect(fixture.pool.lease(for: ShardDevicePool.Shard(simulator: Self.primary(booted: false), origin: .existing)) == nil)
    }

    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let walk: Int32 = 41

    private static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-26-5"
    }

    private static var deviceType: String {
        "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
    }

    private static func primary(booted: Bool) -> Simulator {
        Simulator(udid: "PRIMARY", name: "iPhone 17", osVersion: "26.5", isBooted: booted, runtimeIdentifier: runtime, deviceTypeIdentifier: deviceType)
    }
}

extension ShardDevicePoolTests {
    /// A pool over a scratch lease store and override root, a scripted `simctl`, and a lease somebody else holds on one device like shard 0.
    struct Fixture {
        let directory: TemporaryDirectory
        let store: LeaseStore
        let overrides: DisabledServicesOverride
        let script: Script
        let pool: ShardDevicePool

        init(primaryBooted: Bool = false, failing: String? = nil, failingSecond: String? = nil, gone: String? = nil, meanwhile: @escaping ([String]) -> Void = { _ in }) throws {
            directory = try TemporaryDirectory()
            store = LeaseStore(directory: directory.url.appendingPathComponent("leases"), isAlive: { _ in true })
            overrides = DisabledServicesOverride(root: directory.url.appendingPathComponent("overrides"))
            script = Script(primaryBooted: primaryBooted, failing: failing, failingSecond: failingSecond, gone: gone, meanwhile: meanwhile)
            _ = try store.acquire(udid: "LEASED-SHUT", ttl: 3600, holderPID: 99, now: ShardDevicePoolTests.start)
            pool = ShardDevicePool(leasing: DeviceLeasing(store: store, shell: Shell(script: script.run), overrides: overrides), holderPID: ShardDevicePoolTests.walk)
        }
    }

    /// `simctl` as the pool sees it: shard 0, a booted and a shut-down device like it, one leased, one of another type and one of another runtime; clones and creations answer with numbered UDIDs; optionally one subcommand fails every time, or the second time, and one device is already gone.
    final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [[String]] = []
        private var counts: [String: Int] = [:]
        private let primaryBooted: Bool
        private let failing: String?
        private let failingSecond: String?
        private let gone: String?
        private let meanwhile: ([String]) -> Void

        init(primaryBooted: Bool, failing: String?, failingSecond: String?, gone: String?, meanwhile: @escaping ([String]) -> Void) {
            self.primaryBooted = primaryBooted
            self.failing = failing
            self.failingSecond = failingSecond
            self.gone = gone
            self.meanwhile = meanwhile
        }

        /// Every call but `simctl list`, in order.
        var vectors: [[String]] {
            lock.withLock { recorded }
        }

        var run: (String, [String], [String: String]) throws -> Shell.Result {
            { [self] _, arguments, _ in
                guard !arguments.starts(with: ["simctl", "list"]) else {
                    return Shell.Result(status: 0, standardOutput: devices, standardError: "")
                }
                let verb = arguments.count > 1 ? arguments[1] : ""
                let count = lock.withLock {
                    recorded.append(arguments)
                    counts[verb, default: 0] += 1
                    return counts[verb] ?? 0
                }
                meanwhile(arguments)
                if verb == failing || (verb == failingSecond && count == 2) {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "An error was encountered processing the command (code=164)\n")
                }
                if let gone, arguments.last == gone, ["shutdown", "delete"].contains(verb) {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "Invalid device: \(gone)\n")
                }
                return switch verb {
                case "clone": Shell.Result(status: 0, standardOutput: "CLONE-\(count)\n", standardError: "")
                case "create": Shell.Result(status: 0, standardOutput: "CREATED-\(count)\n", standardError: "")
                default: Shell.Result(status: 0, standardOutput: "", standardError: "")
                }
            }
        }

        private var devices: String {
            let type = ShardDevicePoolTests.deviceType
            let other = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
            func device(_ udid: String, _ state: String, _ deviceType: String) -> String {
                #"{"udid":"\#(udid)","name":"iPhone 17","state":"\#(state)","deviceTypeIdentifier":"\#(deviceType)"}"#
            }
            let newest = [
                device("OTHER-TYPE", "Shutdown", other),
                device("PRIMARY", primaryBooted ? "Booted" : "Shutdown", type),
                device("LEASED-SHUT", "Shutdown", type),
                device("ALIKE-SHUT", "Shutdown", type),
                device("ALIKE-BOOTED", "Booted", type),
            ]
            let older = [device("OTHER-RUNTIME", "Shutdown", type)]
            return #"{"devices":{"\#(ShardDevicePoolTests.runtime)":[\#(newest.joined(separator: ","))],"com.apple.CoreSimulator.SimRuntime.iOS-26-4":[\#(older.joined(separator: ","))]}}"#
        }
    }
}
