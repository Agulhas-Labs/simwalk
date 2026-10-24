//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorServices
import SimWalkCore

/// The `simctl` half of a lease: choosing or cloning the device one is taken on, and, when it is released, deleting the device a lease made or shutting down one the lease found shut down.
///
/// **A release deletes only a device its own lease created, and shuts down only one its own lease found listed as `Shutdown`**, by that lease's UDID — never by name, never another lease's device, never one found booted or booting.
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
    ///
    /// **Nothing named prefers an iPhone** (SimWalk#166): an iPhone-only app is refused on an iPad, so the shut-down devices of the newest runtime are tried iPhones first, then other families, each in `simctl` order. `family` narrows that to one family and refuses, naming it, when none of it is free; it applies only where nothing is named.
    public func acquire(device requested: String?, cloneFrom source: String?, family: DeviceFamily? = nil, ttl: TimeInterval, holderPID: Int32, now: Date) throws -> Grant {
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
            let shutDown = devices.filter { $0.osVersion == newest.osVersion && !$0.isBooted }
            if let family {
                candidates = shutDown.filter { DeviceFamily(deviceTypeIdentifier: $0.deviceTypeIdentifier) == family }
            } else {
                let isPhone = { (device: Simulator) in DeviceFamily(deviceTypeIdentifier: device.deviceTypeIdentifier) == .iphone }
                candidates = shutDown.filter(isPhone) + shutDown.filter { !isPhone($0) }
            }
        }
        var refusal: Error?
        for candidate in candidates {
            do {
                let lease = try LeaseError.mapping { try store.acquire(udid: candidate.udid, ttl: ttl, holderPID: holderPID, now: now, foundShutDown: candidate.isShutDown) }
                return Grant(simulator: candidate, lease: lease)
            } catch let error as LeaseError {
                refusal = refusal ?? error
            }
        }
        guard requested != nil, let refusal else {
            let kind = family.map { $0 == .iphone ? " iPhone" : " iPad" } ?? ""
            throw LeaseError.noShutDownDevice(among: "iOS \(newest.osVersion)\(kind)")
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

    /// Removes the lease carrying `token`, first shutting down and deleting its device when the lease created it, or shutting it down when the lease found it shut down (SimWalk#246: the lease's walk booted it, so it goes back as it was found); the lease is kept when the device could not be deleted or shut down, so the release can be run again.
    ///
    /// **A lease that changes its device leaves the store before any `simctl` call** (`LeaseStore.retire`), and only while it still carries `token`: a lease somebody else took on the device since it was read is not this release's, so nothing is shut down or deleted and the release is refused (`LeaseError.noSuchLease`). A lease that found its device booted, or was written before that was recorded, leaves the device as it is.
    @discardableResult
    public func release(token: String) throws -> Released {
        guard let entry = store.entry(token: token) else {
            throw LeaseError.noSuchLease
        }
        var change = DeviceChange.leftAsItIs
        let released = if entry.lease.createdDevice {
            try LeaseError.mapping { try store.retire(udid: entry.udid, token: token) { change = try deleteDevice($0.udid) } }
        } else if entry.lease.foundShutDown == true {
            try LeaseError.mapping { try store.retire(udid: entry.udid, token: token) { change = try shutDownDevice($0.udid) } }
        } else {
            try LeaseError.mapping { try store.remove(udid: entry.udid, token: token) }
        }
        guard released else {
            throw LeaseError.noSuchLease
        }
        return Released(entry: entry, device: change)
    }

    /// Releases every lease that has expired by `now`, and every lease that cloned its device or found it shut down whose holder is gone — the devices they created deleted and the ones they found shut down shut down again, no other — or, with `dryRun`, names them; for `simwalk prune`.
    ///
    /// A lapsed lease that cloned its device is never reclaimed by an acquisition (`LeaseError.awaitingDeletion`), so this is the only way its clone is deleted: a dead holder's is released here even before its expiry. A dead holder's found-shut-down device goes the same way (SimWalk#249): its walk left it booted, and a booted device is never leased by name, so waiting for the expiry would keep it from every by-name acquisition until then.
    ///
    /// A release a crash left part done — its clone's lease already out of the store — is finished first, deleting the device by the UDID its tombstone names.
    public func releaseExpired(now: Date, dryRun: Bool) -> [Release] {
        var changes: [String: DeviceChange] = [:]
        let abandoned = store.finishAbandonedReleases(dryRun: dryRun) { entry in
            if entry.lease.createdDevice {
                changes[entry.udid] = try deleteDevice(entry.udid)
            } else if entry.lease.foundShutDown == true {
                changes[entry.udid] = try shutDownDevice(entry.udid)
            }
        }
        let lapsed = store.all().filter { $0.lease.expiresAt <= now || (($0.lease.createdDevice || $0.lease.foundShutDown == true) && !store.isHeld($0.lease, now: now)) }.map { entry in
            guard !dryRun else { return Release(entry: entry, failure: nil, device: DeviceChange(planFor: entry.lease)) }
            do {
                return try Release(entry: entry, failure: nil, device: release(token: entry.lease.token).device)
            } catch {
                return Release(entry: entry, failure: String(describing: error), device: nil)
            }
        }
        return abandoned.map { abandoned in
            let device = abandoned.failure != nil ? nil : dryRun ? DeviceChange(planFor: abandoned.entry.lease) : changes[abandoned.entry.udid] ?? .leftAsItIs
            return Release(entry: abandoned.entry, failure: abandoned.failure, device: device)
        } + lapsed
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
            _ = try? deleteDevice(made.udid)
            throw error
        }
    }

    /// `simctl shutdown` then `simctl delete`, of `udid` alone; always `.deleted`, so a release reads its change from either helper alike.
    ///
    /// A device already shut down, or already gone, is what each step wanted.
    @discardableResult
    private func deleteDevice(_ udid: String) throws -> DeviceChange {
        for step in ["shutdown", "delete"] {
            let result = try shell.run("/usr/bin/xcrun", ["simctl", step, udid])
            let alreadyDone = result.failureLine.contains("current state: Shutdown") || result.failureLine.contains("Invalid device")
            guard result.succeeded || alreadyDone else {
                throw LeaseError.deviceNotDeleted(udid: udid, command: "simctl \(step) \(udid)", reason: result.failureLine)
            }
        }
        // `simctl delete` leaves the launchd override directory behind.
        try? overrides.remove(for: udid)
        return .deleted
    }

    /// `simctl shutdown` of `udid` alone, for a lease that found the device shut down, and which of the three ends it met; a device already shut down, or gone, is what it wanted.
    private func shutDownDevice(_ udid: String) throws -> DeviceChange {
        let result = try shell.run("/usr/bin/xcrun", ["simctl", "shutdown", udid])
        if result.succeeded {
            return .shutDown
        }
        if result.failureLine.contains("current state: Shutdown") {
            return .alreadyShutDown
        }
        if result.failureLine.contains("Invalid device") {
            return .gone
        }
        throw LeaseError.deviceNotShutDown(udid: udid, reason: result.failureLine)
    }
}

public extension DeviceLeasing {
    /// A lease taken, and the device it is on.
    struct Grant: Equatable, Sendable {
        public let simulator: Simulator
        public let lease: DeviceLease
    }

    /// A lease released, and what its release did to the device.
    struct Released: Equatable, Sendable {
        public let entry: LeaseStore.Entry
        public let device: DeviceChange
    }

    /// What a release did to its lease's device, from the answer `simctl` gave.
    enum DeviceChange: Equatable, Sendable {
        /// The lease created the device, so it was shut down and deleted.
        case deleted
        /// The lease found the device shut down, and the release shut it down again.
        case shutDown
        /// The lease found the device shut down, and `simctl` answered that it still was.
        case alreadyShutDown
        /// The lease found the device shut down, and `simctl` answered that it no longer exists.
        case gone
        /// The device was not the lease's to change: found booted, a phone, or a lease older than the record.
        case leftAsItIs

        /// What releasing `lease` would do, for a dry run.
        public init(planFor lease: DeviceLease) {
            self = lease.createdDevice ? .deleted : lease.foundShutDown == true ? .shutDown : .leftAsItIs
        }
    }

    /// A lapsed lease a prune released or would release, with what it did or would do to the device, or the reason it was not released.
    struct Release: Equatable, Sendable {
        public let entry: LeaseStore.Entry
        public let failure: String?
        /// `nil` when the release failed.
        public let device: DeviceChange?
    }
}
