//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorServices

/// The `simctl` half of a lease: choosing or cloning the device one is taken on, and deleting the device a lease made when it is released.
///
/// **A release deletes only a device its own lease created**, by that lease's UDID — never by name, never another lease's device, never one the lease was merely taken on.
public struct DeviceLeasing {
    public let store: LeaseStore
    public let shell: Shell
    private let overrides: DisabledServicesOverride

    public init(store: LeaseStore, shell: Shell = Shell(), overrides: DisabledServicesOverride = DisabledServicesOverride()) {
        self.store = store
        self.shell = shell
        self.overrides = overrides
    }

    /// Takes a lease on the device named, on a clone of `source`, or on an unleased shut-down device of the newest iOS runtime.
    ///
    /// **A booted device is leased only when it is named by UDID**: a device already up may be somebody's who takes no leases, and a lease grants the reboot and the setup a walk makes. Nothing named, or a name, falls only on a shut-down device, and is refused naming the commands that get one (`LeaseError.noShutDownDevice`) when none is free.
    public func acquire(device requested: String?, cloneFrom source: String?, ttl: TimeInterval, holderPID: Int32, now: Date) throws -> Grant {
        let devices = try Simulator.available(shell: shell)
        if let source {
            return try clone(source, from: devices, ttl: ttl, holderPID: holderPID, now: now)
        }
        guard let newest = devices.first else {
            throw SimulatorError.noDevices
        }
        let candidates: [Simulator]
        if let requested, let named = devices.first(where: { $0.udid == requested }) {
            candidates = [named]
        } else if let requested {
            let matches = devices.filter { $0.name == requested }
            guard !matches.isEmpty else {
                throw SimulatorError.noSuchDevice(requested: requested, available: devices.map(\.name))
            }
            candidates = matches.filter { !$0.isBooted }
            guard !candidates.isEmpty else {
                throw LeaseError.noShutDownDevice(among: requested)
            }
        } else {
            candidates = devices.filter { $0.osVersion == newest.osVersion && !$0.isBooted }
        }
        var refusal: Error?
        for candidate in candidates {
            do {
                let lease = try LeaseError.mapping { try store.acquire(udid: candidate.udid, ttl: ttl, holderPID: holderPID, now: now) }
                return Grant(simulator: candidate, lease: lease)
            } catch let error as LeaseError {
                refusal = refusal ?? error
            }
        }
        guard requested != nil, let refusal else {
            throw LeaseError.noShutDownDevice(among: "iOS \(newest.osVersion)")
        }
        throw refusal
    }

    /// Leases the paired physical iPhone `udid`, after `devicectl list devices` (a read) confirms it is one; a UDID that is not refused naming the physical UDIDs present (`PhysicalDeviceError.notFound`).
    ///
    /// Releasing the lease deletes nothing: it did not create the device.
    public func acquirePhysical(udid: String, ttl: TimeInterval, holderPID: Int32, now: Date) throws -> (device: PhysicalDevice, lease: DeviceLease) {
        let listing = try PhysicalDevicePrerequisites.devicectl(["list", "devices"], command: PhysicalDevice.command, shell: shell)
        let device = try PhysicalDevice.parse(listDevicesJSON: listing, udid: udid)
        let lease = try LeaseError.mapping { try store.acquire(udid: udid, ttl: ttl, holderPID: holderPID, now: now, physicalDevice: true) }
        return (device, lease)
    }

    /// Removes the lease carrying `token`, first shutting down and deleting its device when the lease created it; the lease is kept when the device could not be deleted, so the release can be run again.
    ///
    /// **A clone's lease leaves the store before any `simctl` call** (`LeaseStore.retire`), and only while it still carries `token`: a lease somebody else took on the device since it was read is not this release's, so nothing is deleted and the release is refused (`LeaseError.noSuchLease`).
    @discardableResult
    public func release(token: String) throws -> LeaseStore.Entry {
        guard let entry = store.entry(token: token) else {
            throw LeaseError.noSuchLease
        }
        let released = if entry.lease.createdDevice {
            try LeaseError.mapping { try store.retire(udid: entry.udid, token: token) { try deleteDevice($0.udid) } }
        } else {
            try LeaseError.mapping { try store.remove(udid: entry.udid, token: token) }
        }
        guard released else {
            throw LeaseError.noSuchLease
        }
        return entry
    }

    /// Releases every lease that has expired by `now`, and every lease that cloned its device whose holder is gone — the devices they created deleted, no other — or, with `dryRun`, names them; for `simwalk prune`.
    ///
    /// A lapsed lease that cloned its device is never reclaimed by an acquisition (`LeaseError.awaitingDeletion`), so this is the only way its clone is deleted: a dead holder's is released here even before its expiry.
    ///
    /// A release a crash left part done — its clone's lease already out of the store — is finished first, deleting the device by the UDID its tombstone names.
    public func releaseExpired(now: Date, dryRun: Bool) -> [Release] {
        let abandoned = store.finishAbandonedReleases(dryRun: dryRun) { entry in
            if entry.lease.createdDevice {
                try deleteDevice(entry.udid)
            }
        }
        let lapsed = store.all().filter { $0.lease.expiresAt <= now || ($0.lease.createdDevice && !store.isHeld($0.lease, now: now)) }.map { entry in
            guard !dryRun else { return Release(entry: entry, failure: nil) }
            do {
                try release(token: entry.lease.token)
                return Release(entry: entry, failure: nil)
            } catch {
                return Release(entry: entry, failure: String(describing: error))
            }
        }
        return abandoned.map { Release(entry: $0.entry, failure: $0.failure) } + lapsed
    }

    private func clone(_ source: String, from devices: [Simulator], ttl: TimeInterval, holderPID: Int32, now: Date) throws -> Grant {
        guard let original = devices.first(where: { $0.udid == source }) else {
            throw SimulatorError.noSuchDevice(requested: source, available: devices.map(\.name))
        }
        guard !original.isBooted else {
            throw LeaseError.cloneSourceBooted(udid: source)
        }
        let name = "\(original.name) (SimWalk lease)"
        let cloned = try shell.run("/usr/bin/xcrun", ["simctl", "clone", source, name])
        let udid = cloned.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cloned.succeeded, !udid.isEmpty else {
            throw SimulatorError.simctlFailed(command: "clone \(source)", reason: cloned.failureLine)
        }
        let made = Simulator(udid: udid, name: name, osVersion: original.osVersion, isBooted: false, runtimeIdentifier: original.runtimeIdentifier, deviceTypeIdentifier: original.deviceTypeIdentifier)
        return try leaseCreated(made, clonedFrom: source, ttl: ttl, holderPID: holderPID, now: now)
    }

    /// Creates a new device of `deviceType` on `runtime`, named `"<name> (SimWalk lease)"`, and leases it as a device the lease created, so its release deletes it.
    ///
    /// The device is deleted again, by the UDID `simctl create` answered with, when its lease cannot be written.
    public func create(named name: String, deviceType: String, runtime: String, ttl: TimeInterval, holderPID: Int32, now: Date) throws -> Grant {
        let named = "\(name) (SimWalk lease)"
        let created = try shell.run("/usr/bin/xcrun", ["simctl", "create", named, deviceType, runtime])
        let udid = created.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard created.succeeded, !udid.isEmpty else {
            throw SimulatorError.simctlFailed(command: "create \(deviceType) \(runtime)", reason: created.failureLine)
        }
        let made = Simulator(udid: udid, name: named, osVersion: Simulator.version(fromRuntime: runtime), isBooted: false, runtimeIdentifier: runtime, deviceTypeIdentifier: deviceType)
        return try leaseCreated(made, clonedFrom: nil, ttl: ttl, holderPID: holderPID, now: now)
    }

    /// Leases a device just made, as one the lease created; a lease that cannot be written deletes the device rather than leave it nobody's.
    private func leaseCreated(_ made: Simulator, clonedFrom source: String?, ttl: TimeInterval, holderPID: Int32, now: Date) throws -> Grant {
        do {
            let lease = try LeaseError.mapping { try store.acquire(udid: made.udid, ttl: ttl, holderPID: holderPID, now: now, createdDevice: true, clonedFrom: source) }
            return Grant(simulator: made, lease: lease)
        } catch {
            try? deleteDevice(made.udid)
            throw error
        }
    }

    /// `simctl shutdown` then `simctl delete`, of `udid` alone.
    ///
    /// A device already shut down, or already gone, is what each step wanted.
    private func deleteDevice(_ udid: String) throws {
        for step in ["shutdown", "delete"] {
            let result = try shell.run("/usr/bin/xcrun", ["simctl", step, udid])
            let alreadyDone = result.failureLine.contains("current state: Shutdown") || result.failureLine.contains("Invalid device")
            guard result.succeeded || alreadyDone else {
                throw LeaseError.deviceNotDeleted(udid: udid, command: "simctl \(step) \(udid)", reason: result.failureLine)
            }
        }
        // `simctl delete` leaves the launchd override directory behind.
        try? overrides.remove(for: udid)
    }
}

public extension DeviceLeasing {
    /// A lease taken, and the device it is on.
    struct Grant: Equatable, Sendable {
        public let simulator: Simulator
        public let lease: DeviceLease
    }

    /// A lapsed lease a prune released or would release, and any reason its clone was not deleted.
    struct Release: Equatable, Sendable {
        public let entry: LeaseStore.Entry
        public let failure: String?
    }
}
