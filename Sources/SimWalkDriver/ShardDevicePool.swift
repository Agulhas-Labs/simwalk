//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore

/// The simulators a parallel walk runs its shards on beyond shard 0, the device a serial walk takes, and the one release that gives every one of them back.
///
/// **Extras are taken in this order until there are enough:** unleased existing devices of shard 0's device type and runtime, booted ones first (no boot to wait on), then shut-down ones; then clones of shard 0, but only when shard 0 was shut down when it was taken (`simctl clone` refuses a booted source, and a device found booted may be in use by someone who takes no leases); otherwise new devices of its type and runtime (`simctl create`). Each is leased for the walk's pid for ``WalkLease/ttl`` and claimed as shard 0 is; a clone or a created device is leased as created, so its release, or `simwalk prune` after a walk killed outright, deletes it. Clones are made from a shut-down shard 0, so ``acquire(_:beside:now:)`` runs before shard 0 boots.
///
/// **One release, whatever ends the walk.** ``release()`` runs its commands once: from the walk's end, from a throw part-way through ``acquire(_:beside:now:)`` (which releases before it rethrows), or from a cancel handler (``release(on:)``). It stops nothing it did not start, deletes only devices it created (`simctl shutdown`, then `simctl delete`, by UDID; a device already gone counts as deleted), releases every lease and claim it took, and answers with what it could not give back. A cancel that lands while a device is being cloned or created waits for that command to return, so the new device is deleted too rather than left unleased; `SimctlBound` bounds the wait.
public final class ShardDevicePool: @unchecked Sendable {
    private let leasing: DeviceLeasing
    private let holderPID: Int32
    /// Held across each acquisition step and the whole release, so a release from another thread never runs between a device being made and its being recorded here.
    private let lock = NSLock()
    private var taken: [Taken] = []
    /// What the release could not give back; `nil` until the pool has been released.
    private var unreleased: [Unreleased]?

    public init(leasing: DeviceLeasing, holderPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.leasing = leasing
        self.holderPID = holderPID
    }

    /// The extra devices acquired so far, in the order they were taken.
    public var shards: [Shard] {
        lock.withLock { taken.map(\.shard) }
    }

    /// Acquires `count` devices beside `primary` (shard 0, as it was listed when the walk took it), in the order the type describes.
    ///
    /// `ownedOnly` takes no extra the walk would not own (``Shard/mayReboot``): an existing device found booted is passed over, for a walkbook whose setup changes the device. A serial walk refuses such a setup on a device it does not own (`DeviceSetupError.notOwned`); the extras are the walk's own choice, so it chooses only devices it may change instead.
    ///
    /// A throw part-way releases everything acquired so far, then rethrows; ``release()`` afterwards runs nothing and answers what that release could not give back.
    public func acquire(_ count: Int, beside primary: Simulator, ownedOnly: Bool = false, now: Date) throws -> [Shard] {
        guard count > 0 else { return [] }
        do {
            return try acquiring(count, beside: primary, ownedOnly: ownedOnly, now: now)
        } catch {
            release()
            throw error
        }
    }

    /// Releases every claim and lease the pool took and deletes every device it created; the second and later calls run nothing and answer what the first could not give back.
    @discardableResult
    public func release() -> [Unreleased] {
        lock.withLock {
            if let unreleased {
                return unreleased
            }
            var left: [Unreleased] = []
            for held in taken {
                held.claim?.release()
                do {
                    try leasing.release(token: held.token)
                } catch let LeaseError.deviceNotDeleted(udid, command, reason) {
                    left.append(Unreleased(udid: udid, command: command, reason: reason))
                } catch {
                    left.append(Unreleased(udid: held.shard.simulator.udid, command: "release its lease", reason: String(describing: error)))
                }
            }
            unreleased = left
            return left
        }
    }

    /// Releases the pool when `cancellation` is cancelled, at once when it already has been.
    ///
    /// The release completes inside the handler: `TerminationSignals` runs the handlers and then ends the process, so a SIGINT or SIGTERM ends it with the created devices deleted and the leases released.
    public func release(on cancellation: Cancellation) {
        cancellation.onCancel { [self] in
            _ = release()
        }
    }

    /// The lease on an extra the pool holds, for a walk of that device to renew; `nil` for a device the pool does not hold.
    ///
    /// Its release stays the pool's, so the lease is not marked taken.
    public func lease(for shard: Shard) -> WalkLease? {
        lock.withLock { taken }.first { $0.shard == shard }.map { WalkLease(store: leasing.store, udid: $0.shard.simulator.udid, token: $0.token, taken: false) }
    }

    private func acquiring(_ count: Int, beside primary: Simulator, ownedOnly: Bool, now: Date) throws -> [Shard] {
        let devices = try Simulator.available(shell: leasing.shell)
        let listed = devices.first { $0.udid == primary.udid } ?? primary
        var shards: [Shard] = []
        let alike = devices.filter { $0.udid != listed.udid && Self.isAlike($0, listed) && (!ownedOnly || Shard(simulator: $0, origin: .existing).mayReboot) }
        for candidate in alike.filter(\.isBooted) + alike.filter({ !$0.isBooted }) where shards.count < count {
            if let shard = try step({ try leaseExisting(candidate, now: now) }) {
                shards.append(shard)
            }
        }
        let wasShutDown = !primary.isBooted && !listed.isBooted
        for _ in shards.count ..< count {
            if let shard = try step({ try make(like: listed, cloning: wasShutDown, now: now) }) {
                shards.append(shard)
            }
        }
        return shards
    }

    /// One acquisition, under the lock: refused once the pool has been released, and recorded, with its claim, as soon as its lease exists.
    private func step(_ body: () throws -> (DeviceLeasing.Grant, Origin)?) throws -> Shard? {
        try lock.withLock {
            guard unreleased == nil else {
                throw ShardDevicePoolError.released
            }
            guard let made = try body() else { return nil }
            let (grant, origin) = made
            let shard = Shard(simulator: grant.simulator, origin: origin)
            taken.append(Taken(shard: shard, token: grant.lease.token, claim: nil))
            taken[taken.count - 1].claim = try LeaseError.takingClaim(udid: grant.simulator.udid, in: leasing.store)
            return shard
        }
    }

    /// A lease on an existing device, or `nil` when somebody else holds it; a store that cannot be written is thrown rather than read as a busy device.
    private func leaseExisting(_ candidate: Simulator, now: Date) throws -> (DeviceLeasing.Grant, Origin)? {
        do {
            let lease = try LeaseError.mapping { try leasing.store.acquire(udid: candidate.udid, ttl: WalkLease.ttl, holderPID: holderPID, now: now) }
            return (DeviceLeasing.Grant(simulator: candidate, lease: lease), .existing)
        } catch let error as LeaseError {
            if case .storeFailed = error {
                throw error
            }
            return nil
        }
    }

    /// A clone of `primary` when it was shut down, else a new device of its type and runtime.
    private func make(like primary: Simulator, cloning: Bool, now: Date) throws -> (DeviceLeasing.Grant, Origin) {
        if cloning {
            return try (leasing.acquire(device: nil, cloneFrom: primary.udid, ttl: WalkLease.ttl, holderPID: holderPID, now: now), .cloned)
        }
        guard let deviceType = primary.deviceTypeIdentifier, let runtime = primary.runtimeIdentifier else {
            throw ShardDevicePoolError.deviceTypeUnknown(udid: primary.udid)
        }
        return try (leasing.create(named: primary.name, deviceType: deviceType, runtime: runtime, ttl: WalkLease.ttl, holderPID: holderPID, now: now), .created)
    }

    /// Whether `device` is of `primary`'s device type and runtime, both known.
    private static func isAlike(_ device: Simulator, _ primary: Simulator) -> Bool {
        guard let deviceType = primary.deviceTypeIdentifier, let runtime = primary.runtimeIdentifier else { return false }
        return device.deviceTypeIdentifier == deviceType && device.runtimeIdentifier == runtime
    }
}

public extension ShardDevicePool {
    /// An extra device a shard runs on, and how the pool came by it.
    struct Shard: Equatable, Sendable {
        public let simulator: Simulator
        public let origin: Origin

        /// Whether the walk made this device (cloned or created it), so its launchd services are the walk's to switch off and its release deletes it.
        public var createdByWalk: Bool {
            origin != .existing
        }

        /// Whether the walk may reboot this device and change its device-wide state, as a serial walk judges a device it resolved (``DeviceSettle/mayReboot(_:requested:leased:)``): one it made, or an existing one that was shut down when the pool listed it. An existing device found booted may be in use by someone who takes no leases, and the pool's lease grants no reboot, as a serial walk's own lease grants none.
        public var mayReboot: Bool {
            createdByWalk || DeviceSettle.mayReboot(simulator, requested: nil, leased: false)
        }

        /// Boots the device as `provisioning` boots shard 0, and returns the line the answer carries: slim when the walk made the device, otherwise as a serial walk boots a device it did not make.
        public func boot(with provisioning: SlimWalkProvisioning, stockRequested: Bool, appPath: String?, boot: (Simulator) throws -> Void) throws -> String? {
            try provisioning.boot(simulator, createdByWalk: createdByWalk, stockRequested: stockRequested, appPath: appPath, boot: boot)
        }
    }

    /// How the pool came by a device.
    enum Origin: Equatable, Sendable {
        /// An existing device, leased; its release deletes nothing.
        case existing
        /// A clone of shut-down shard 0 (`simctl clone`).
        case cloned
        /// A new device of shard 0's type and runtime (`simctl create`).
        case created
    }

    /// A device the release could not give back: its UDID, the command that failed, and why, for the walk's answer.
    struct Unreleased: Equatable, Sendable, CustomStringConvertible {
        public let udid: String
        public let command: String
        public let reason: String

        public var description: String {
            "\(udid): \(command) failed: \(reason)"
        }
    }
}

private extension ShardDevicePool {
    /// A device the pool holds: the shard, its lease's token and its claim.
    struct Taken {
        let shard: Shard
        let token: String
        var claim: WalkClaim?
    }
}
