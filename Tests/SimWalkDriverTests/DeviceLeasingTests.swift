//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What a lease asks of `simctl`: which device it takes, the clone it makes, and — the one destructive call — the device it deletes on release, which must be the lease's own clone and nothing else.
struct DeviceLeasingTests {
    /// G4: releasing a lease that cloned its device runs exactly `simctl shutdown <udid>` then `simctl delete <udid>`, of that UDID alone.
    @Test
    func releasingACreatedDeviceShutsDownAndDeletesThatUDIDOnly() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SOURCE-1")
        let script = Script()

        try DeviceLeasing(store: store, shell: Shell(script: script.run)).release(token: lease.token)

        #expect(script.vectors == [["simctl", "shutdown", "CLONE-1"], ["simctl", "delete", "CLONE-1"]])
        #expect(store.all().isEmpty)
    }

    /// G4: releasing a lease on a device it did not create runs nothing at all.
    @Test
    func releasingALeaseOnAnExistingDeviceDeletesNothing() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)
        let script = Script()

        try DeviceLeasing(store: store, shell: Shell(script: script.run)).release(token: lease.token)

        #expect(script.vectors.isEmpty)
        #expect(store.all().isEmpty)
    }

    /// A clone that could not be deleted keeps its lease, so the release can be run again rather than the device being forgotten.
    @Test
    func acloneThatCouldNotBeDeletedKeepsItsLease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SOURCE-1")
        let script = Script(failing: "delete")

        #expect(throws: LeaseError.self) {
            try DeviceLeasing(store: store, shell: Shell(script: script.run)).release(token: lease.token)
        }
        #expect(store.entry(token: lease.token) != nil)
    }

    /// A clone is made only of a device that is shut down; a booted source is refused before `simctl clone` runs.
    @Test
    func abootedCloneSourceIsRefusedNamingTheShutdown() throws {
        let directory = try TemporaryDirectory()
        let script = Script()

        #expect(throws: LeaseError.cloneSourceBooted(udid: "BOOTED-1")) {
            try DeviceLeasing(store: LeaseStore(directory: directory.url), shell: Shell(script: script.run)).acquire(device: nil, cloneFrom: "BOOTED-1", ttl: 60, holderPID: 41, now: Self.start)
        }
        #expect(!script.vectors.contains { $0.starts(with: ["simctl", "clone"]) })
    }

    /// A clone of a shut-down source is leased as a device the lease created, so its release deletes it.
    @Test
    func acloneIsLeasedAsCreated() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let script = Script()

        let grant = try DeviceLeasing(store: store, shell: Shell(script: script.run)).acquire(device: nil, cloneFrom: "SHUT-1", ttl: 60, holderPID: 41, now: Self.start)

        #expect(grant.simulator.udid == "CLONE-NEW")
        #expect(grant.lease.createdDevice)
        #expect(grant.lease.clonedFrom == "SHUT-1")
        #expect(script.vectors.last == ["simctl", "clone", "SHUT-1", "iPhone 17 (SimWalk lease)"])
    }

    /// With nothing named, a lease falls only on an unleased shut-down device — never a booted one, which may be somebody's who takes no leases — and is refused, naming the commands that get a device, once none is free.
    @Test
    func anunnamedAcquisitionTakesOnlyAShutDownUnleasedDevice() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let leasing = DeviceLeasing(store: store, shell: Shell(script: Script().run))

        let first = try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        let second = try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)

        #expect(first.simulator.udid == "SHUT-1")
        #expect(second.simulator.udid == "SHUT-2")
        #expect(throws: LeaseError.noShutDownDevice(among: "iOS 26.5")) {
            try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        }
        #expect(store.all().map(\.udid) == ["SHUT-1", "SHUT-2"])
        #expect(LeaseError.noShutDownDevice(among: "iOS 26.5").description.contains("simwalk lease acquire --device <udid>"))
    }

    /// A booted device is leased only when it is named by UDID: named by its name it is refused, with nothing leased, since a lease grants the reboot and the setup; a name that also has a shut-down device falls on that one.
    @Test
    func abootedDeviceIsLeasedWhenNamedByUDIDAndNeverByName() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let leasing = DeviceLeasing(store: store, shell: Shell(script: Script().run))

        #expect(throws: LeaseError.noShutDownDevice(among: "iPhone 17 Pro")) {
            try leasing.acquire(device: "iPhone 17 Pro", cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        }
        #expect(store.all().isEmpty)
        let byName = try leasing.acquire(device: "iPhone 17", cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        let byUDID = try leasing.acquire(device: "BOOTED-1", cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)

        #expect(byName.simulator.udid == "SHUT-1")
        #expect(byUDID.simulator.udid == "BOOTED-1")
    }

    /// A prune releases the expired leases only, deleting only the device an expired lease created.
    @Test
    func releasingExpiredLeasesDeletesOnlyTheirClones() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        _ = try store.acquire(udid: "CLONE-OLD", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SHUT-1")
        _ = try store.acquire(udid: "UDID-OLD", ttl: 60, holderPID: 41, now: Self.start)
        let live = try store.acquire(udid: "CLONE-LIVE", ttl: 3600, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SHUT-1")
        let script = Script()

        let released = DeviceLeasing(store: store, shell: Shell(script: script.run)).releaseExpired(now: Self.start.addingTimeInterval(120), dryRun: false)

        #expect(released.map(\.entry.udid) == ["CLONE-OLD", "UDID-OLD"])
        #expect(script.vectors == [["simctl", "shutdown", "CLONE-OLD"], ["simctl", "delete", "CLONE-OLD"]])
        #expect(store.all().map(\.lease) == [live])
    }

    /// A lease that cloned its device and whose holder has died is never taken over by an acquisition — which would forget the clone was made — and a prune releases it, deleting the clone by its UDID, before it expires.
    @Test
    func adeadHoldersCloneIsNotReacquiredAndPruneDeletesIt() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { $0 != 41 })
        _ = try store.acquire(udid: "SHUT-1", ttl: 3600, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SOURCE-1")
        let script = Script()
        let leasing = DeviceLeasing(store: store, shell: Shell(script: script.run))

        let grant = try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 42, now: Self.start)
        let released = leasing.releaseExpired(now: Self.start, dryRun: false)

        #expect(grant.simulator.udid == "SHUT-2")
        #expect(released.map(\.entry.udid) == ["SHUT-1"])
        #expect(released.map(\.failure) == [nil])
        #expect(script.vectors == [["simctl", "shutdown", "SHUT-1"], ["simctl", "delete", "SHUT-1"]])
        #expect(store.all().map(\.udid) == ["SHUT-2"])
    }

    /// A prune's release takes its lease out of the store before any `simctl` call, so a session that judges the lapsed lease stale mid-release and replaces it — removing it by the token it read, then acquiring — is refused, and the device is never deleted while another lease is on it.
    @Test
    func areleaseNeverDeletesADeviceAnotherLeaseTookMidRelease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lapsed = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SHUT-1")
        let now = Self.start.addingTimeInterval(120)
        var rival: Result<DeviceLease, Error>?
        var leaseAtDelete: DeviceLease?
        let script = Script { arguments in
            if arguments == ["simctl", "shutdown", "CLONE-1"] {
                rival = Result {
                    try store.remove(udid: "CLONE-1", token: lapsed.token)
                    return try store.acquire(udid: "CLONE-1", ttl: 3600, holderPID: 42, now: now)
                }
            }
            if arguments == ["simctl", "delete", "CLONE-1"] {
                leaseAtDelete = try? store.lease(onDevice: "CLONE-1")
            }
        }

        let released = DeviceLeasing(store: store, shell: Shell(script: script.run)).releaseExpired(now: now, dryRun: false)

        #expect(leaseAtDelete == nil)
        #expect(throws: LeaseStoreError.awaitingDeletion(udid: "CLONE-1")) { try rival?.get() }
        #expect(released.map(\.failure) == [nil])
        #expect(store.all().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).filter { !$0.hasPrefix(".") }.isEmpty)
    }

    /// A prune's dry run names the lapsed leases and deletes nothing: no `simctl` call, and every lease still in the store.
    @Test
    func aDryRunReleaseRunsNothingAndKeepsEveryLease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        _ = try store.acquire(udid: "CLONE-OLD", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SHUT-1")
        _ = try store.acquire(udid: "UDID-OLD", ttl: 60, holderPID: 41, now: Self.start)
        let script = Script()

        let released = DeviceLeasing(store: store, shell: Shell(script: script.run)).releaseExpired(now: Self.start.addingTimeInterval(120), dryRun: true)

        #expect(released.map(\.entry.udid) == ["CLONE-OLD", "UDID-OLD"])
        #expect(script.vectors.isEmpty)
        #expect(store.all().map(\.udid) == ["CLONE-OLD", "UDID-OLD"])
    }

    /// Only a temporary file a minute old is swept, and a dry run counts without removing.
    @Test
    func sweepingTemporariesRemovesOnlyOldOnesAndNeverALease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        _ = try store.acquire(udid: "UDID-1", ttl: 3600, holderPID: 41, now: Self.start)
        let old = directory.url.appendingPathComponent(".UDID-1.json.AAAA.tmp")
        let fresh = directory.url.appendingPathComponent(".UDID-1.json.BBBB.tmp")
        for file in [old, fresh] {
            try Data("x".utf8).write(to: file)
        }
        try FileManager.default.setAttributes([.modificationDate: Self.start.addingTimeInterval(-600)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Self.start.addingTimeInterval(-10)], ofItemAtPath: fresh.path)

        let planned = store.sweepTemporaries(now: Self.start, dryRun: true)
        let existedAfterDryRun = FileManager.default.fileExists(atPath: old.path)
        let swept = store.sweepTemporaries(now: Self.start, dryRun: false)

        #expect(planned == 1)
        #expect(existedAfterDryRun)
        #expect(swept == 1)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(store.all().map(\.udid) == ["UDID-1"])
    }

    /// SimWalk#166: a bare acquire prefers an iPhone even where an iPad is listed first.
    @Test
    func aBareAcquireTakesAnIPhoneBeforeAnIPad() throws {
        let directory = try TemporaryDirectory()
        let leasing = DeviceLeasing(store: LeaseStore(directory: directory.url, isAlive: { _ in true }), shell: Shell(script: Script(devices: Script.familyDevices).run))

        let first = try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        let second = try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)

        #expect(first.simulator.udid == "PHONE-1")
        #expect(second.simulator.udid == "PAD-1")
    }

    @Test
    func aFamilyLeasesOnlyThatFamily() throws {
        let directory = try TemporaryDirectory()
        let leasing = DeviceLeasing(store: LeaseStore(directory: directory.url, isAlive: { _ in true }), shell: Shell(script: Script(devices: Script.familyDevices).run))

        let pad = try leasing.acquire(device: nil, cloneFrom: nil, family: .ipad, ttl: 60, holderPID: 41, now: Self.start)

        #expect(pad.simulator.udid == "PAD-1")
        #expect(throws: LeaseError.noShutDownDevice(among: "iOS 27.0 iPad")) {
            try leasing.acquire(device: nil, cloneFrom: nil, family: .ipad, ttl: 60, holderPID: 41, now: Self.start)
        }
    }

    @Test
    func anIPhoneFamilyWithOnlyAnIPadFreeIsRefusedNamingTheFamily() throws {
        let directory = try TemporaryDirectory()
        let leasing = DeviceLeasing(store: LeaseStore(directory: directory.url, isAlive: { _ in true }), shell: Shell(script: Script(devices: Script.onlyIPadDevices).run))

        #expect(throws: LeaseError.noShutDownDevice(among: "iOS 27.0 iPhone")) {
            try leasing.acquire(device: nil, cloneFrom: nil, family: .iphone, ttl: 60, holderPID: 41, now: Self.start)
        }
        #expect(LeaseError.noShutDownDevice(among: "iOS 27.0 iPhone").description.contains("no shut-down iOS 27.0 iPhone simulator is free"))
    }

    @Test
    func aBareAcquireWithOnlyAnIPadFreeStillTakesIt() throws {
        let directory = try TemporaryDirectory()
        let leasing = DeviceLeasing(store: LeaseStore(directory: directory.url, isAlive: { _ in true }), shell: Shell(script: Script(devices: Script.onlyIPadDevices).run))

        let grant = try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)

        #expect(grant.simulator.udid == "PAD-1")
    }

    /// A lease taken on a shut-down device records it, and its release runs exactly `simctl shutdown <udid>`, so a device the lease's walk booted goes back as it was found and the next lease by name finds it free (SimWalk#246).
    @Test
    func aleaseThatFoundItsDeviceShutDownShutsItDownOnRelease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let script = Script()
        let leasing = DeviceLeasing(store: store, shell: Shell(script: script.run))

        let grant = try leasing.acquire(device: "iPhone 17", cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        try leasing.release(token: grant.lease.token)

        #expect(grant.lease.foundShutDown == true)
        #expect(script.vectors == [["simctl", "shutdown", "SHUT-1"]])
        #expect(store.all().isEmpty)
    }

    /// A lease taken on a booted device, which only a UDID can name, records nothing, and its release runs nothing: the device may be somebody's who takes no leases.
    @Test
    func aleaseThatFoundItsDeviceBootedLeavesItAsItIs() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let script = Script()
        let leasing = DeviceLeasing(store: store, shell: Shell(script: script.run))

        let grant = try leasing.acquire(device: "BOOTED-1", cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        try leasing.release(token: grant.lease.token)

        #expect(grant.lease.foundShutDown == nil)
        #expect(script.vectors.isEmpty)
        #expect(store.all().isEmpty)
    }

    /// A device that would not shut down keeps its lease, so the release can be run again, and the refusal names the command.
    @Test
    func adeviceThatWouldNotShutDownKeepsItsLease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let leasing = DeviceLeasing(store: store, shell: Shell(script: Script(failing: "shutdown").run))
        let grant = try leasing.acquire(device: nil, cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)

        #expect(throws: LeaseError.deviceNotShutDown(udid: "SHUT-1", reason: "An error was encountered processing the command (code=164)")) {
            try leasing.release(token: grant.lease.token)
        }
        #expect(store.entry(token: grant.lease.token) != nil)
    }

    /// A prune that releases an expired lease which found its device shut down shuts that device down, and only that one.
    @Test
    func pruningAnExpiredLeaseThatFoundItsDeviceShutDownShutsItDown() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        _ = try store.acquire(udid: "FOUND-OFF", ttl: 60, holderPID: 41, now: Self.start, foundShutDown: true)
        _ = try store.acquire(udid: "FOUND-ON", ttl: 60, holderPID: 41, now: Self.start)
        let script = Script()

        let released = DeviceLeasing(store: store, shell: Shell(script: script.run)).releaseExpired(now: Self.start.addingTimeInterval(120), dryRun: false)

        #expect(released.map(\.failure) == [nil, nil])
        #expect(script.vectors == [["simctl", "shutdown", "FOUND-OFF"]])
        #expect(store.all().isEmpty)
    }

    /// A walk under the lease renews it before it boots the device, and the renewed lease still puts the device back: the case SimWalk#246 was found in.
    @Test
    func arenewedLeaseStillShutsItsDeviceDownOnRelease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let script = Script()
        let leasing = DeviceLeasing(store: store, shell: Shell(script: script.run))
        let grant = try leasing.acquire(device: "iPhone 17", cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)

        _ = try store.renew(token: grant.lease.token, ttl: 1800, now: Self.start.addingTimeInterval(5))
        try leasing.release(token: grant.lease.token)

        #expect(script.vectors == [["simctl", "shutdown", "SHUT-1"]])
    }

    /// A device somebody else is booting is not shut down: only a device `simctl` listed as `Shutdown` is recorded as found shut down.
    @Test
    func adeviceFoundBootingIsLeftAsItIs() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let booting = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"BOOTING-1","name":"iPhone 17","state":"Booting"}]}}"#
        let script = Script(devices: booting)
        let leasing = DeviceLeasing(store: store, shell: Shell(script: script.run))

        let grant = try leasing.acquire(device: "BOOTING-1", cloneFrom: nil, ttl: 60, holderPID: 41, now: Self.start)
        try leasing.release(token: grant.lease.token)

        #expect(grant.lease.foundShutDown == nil)
        #expect(script.vectors.isEmpty)
    }

    /// A release a crash left part done, its found-shut-down lease already a tombstone, is finished by a prune: the device is shut down and the tombstone goes.
    @Test
    func aprunefinishesACrashedReleaseOfAFoundShutDownLease() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "FOUND-OFF", ttl: 3600, holderPID: 41, now: Self.start, foundShutDown: true)
        let file = store.url(for: "FOUND-OFF")
        try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("FOUND-OFF.releasing.\(lease.token)"))
        let script = Script()

        let released = DeviceLeasing(store: store, shell: Shell(script: script.run)).releaseExpired(now: Self.start, dryRun: false)

        #expect(released.map(\.entry.udid) == ["FOUND-OFF"])
        #expect(released.map(\.failure) == [nil])
        #expect(script.vectors == [["simctl", "shutdown", "FOUND-OFF"]])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).filter { $0.contains(".releasing.") }.isEmpty)
    }

    /// A dead holder's lease that found its device shut down is released by a prune before its expiry, as a dead holder's clone is, so its device does not stay booted and refuse every by-name acquisition until then (SimWalk#249).
    @Test
    func aprunereleasesADeadHoldersFoundShutDownLeaseBeforeItExpires() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in false })
        _ = try store.acquire(udid: "FOUND-OFF", ttl: 3600, holderPID: 41, now: Self.start, foundShutDown: true)
        _ = try store.acquire(udid: "FOUND-ON", ttl: 3600, holderPID: 41, now: Self.start)
        let script = Script()

        let released = DeviceLeasing(store: store, shell: Shell(script: script.run)).releaseExpired(now: Self.start.addingTimeInterval(5), dryRun: false)

        #expect(released.map(\.entry.udid) == ["FOUND-OFF"])
        #expect(released.map(\.device) == [.shutDown])
        #expect(script.vectors == [["simctl", "shutdown", "FOUND-OFF"]])
        #expect(store.all().map(\.udid) == ["FOUND-ON"])
    }

    /// A release says what `simctl` answered: a device that was already shut down is not reported as shut down by the release (SimWalk#249).
    @Test
    func areleaseSaysWhenItsDeviceWasAlreadyShutDownOrGone() throws {
        for (answer, expected) in [("Unable to shutdown device in current state: Shutdown", DeviceLeasing.DeviceChange.alreadyShutDown), ("Invalid device: FOUND-OFF", .gone)] {
            let directory = try TemporaryDirectory()
            let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
            let lease = try store.acquire(udid: "FOUND-OFF", ttl: 60, holderPID: 41, now: Self.start, foundShutDown: true)
            let shell = Shell { _, _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "An error was encountered processing the command (code=405):\n\(answer)\n") }

            let released = try DeviceLeasing(store: store, shell: shell).release(token: lease.token)

            #expect(released.device == expected)
            #expect(store.all().isEmpty)
        }
    }

    private static let start = Date(timeIntervalSince1970: 1_000_000)
}

extension DeviceLeasingTests {
    /// `simctl` as a lease sees it: a booted device and two shut-down ones on one runtime, a clone that answers with its new UDID, optionally one subcommand that fails, and optionally what another session does while a call runs.
    final class Script {
        private(set) var vectors: [[String]] = []
        private let failing: String?
        private let meanwhile: ([String]) -> Void
        private let deviceList: String

        init(failing: String? = nil, devices: String = Script.devices, meanwhile: @escaping ([String]) -> Void = { _ in }) {
            self.failing = failing
            deviceList = devices
            self.meanwhile = meanwhile
        }

        var run: (String, [String], [String: String]) throws -> Shell.Result {
            { [self] _, arguments, _ in
                vectors.append(arguments)
                meanwhile(arguments)
                if arguments.count > 1, arguments[1] == failing {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "An error was encountered processing the command (code=164)\n")
                }
                switch arguments {
                case _ where arguments.starts(with: ["simctl", "list"]):
                    vectors.removeLast()
                    return Shell.Result(status: 0, standardOutput: deviceList, standardError: "")
                case _ where arguments.starts(with: ["simctl", "clone"]):
                    return Shell.Result(status: 0, standardOutput: "CLONE-NEW\n", standardError: "")
                default:
                    return Shell.Result(status: 0, standardOutput: "", standardError: "")
                }
            }
        }

        static var devices: String {
            #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"BOOTED-1","name":"iPhone 17 Pro","state":"Booted"},{"udid":"SHUT-1","name":"iPhone 17","state":"Shutdown"},{"udid":"SHUT-2","name":"iPhone 17","state":"Shutdown"}]}}"#
        }

        /// An iPad listed before an iPhone, both shut down, with their device types (SimWalk#166).
        static var familyDevices: String {
            #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"PAD-1","name":"iPad Pro","state":"Shutdown","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5"},{"udid":"PHONE-1","name":"iPhone 17","state":"Shutdown","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]}}"#
        }

        /// Only an iPad is shut down.
        static var onlyIPadDevices: String {
            #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"PAD-1","name":"iPad Pro","state":"Shutdown","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5"},{"udid":"PHONE-1","name":"iPhone 17","state":"Booted","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17"}]}}"#
        }
    }
}
