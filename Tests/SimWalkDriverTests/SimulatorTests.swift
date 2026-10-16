//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `simctl list devices --json` is someone else's format, so what it is read as belongs in a test rather than in a hope.
struct SimulatorTests {
    @Test
    func devicesAreReadNewestRuntimeFirstWithTheirBootState() throws {
        let devices = try Simulator.parseDevices(Data(Self.deviceListJSON.utf8))

        #expect(devices.map(\.name) == ["iPhone 17 Pro", "Agent-Sim-2", "iPhone 15"])
        #expect(devices[0].osVersion == "26.5")
        #expect(devices[0].isBooted)
        #expect(!devices[1].isBooted)
        #expect(devices[2].osVersion == "17.4")
    }

    /// A runtime identifier is not a version, and the manifest records the version.
    @Test
    func aRuntimeIdentifierIsReducedToItsVersion() {
        #expect(Simulator.version(fromRuntime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5") == "26.5")
        #expect(Simulator.version(fromRuntime: "com.apple.CoreSimulator.SimRuntime.iOS-17-4") == "17.4")
    }

    /// `simctl` reports every platform installed, and `watchOS` sorts *above* `iOS` as a string, so "the newest available device" over the raw list resolved to an Apple Watch — which then reported every screen of an iPhone app unreachable and looked like a walkbook problem.
    @Test
    func onlyIOSRuntimesAreOfferedAsDevicesToWalk() throws {
        let devices = try Simulator.parseDevices(Data(Self.mixedPlatformJSON.utf8))

        #expect(devices.map(\.name) == ["iPhone 17 Pro"])
        #expect(!devices.contains { $0.name.contains("Watch") })
        #expect(!devices.contains { $0.name.contains("TV") })
    }

    @Test
    func aDeviceListOfAnUnexpectedShapeIsRefusedRatherThanReadAsEmpty() {
        #expect(throws: SimulatorError.unreadableDeviceList) {
            try Simulator.parseDevices(Data(#"{"somethingElse": []}"#.utf8))
        }
    }

    /// A booted device is preferred over a shutdown one of the same name, because booting costs tens of seconds and a walk that silently boots a second device while one sits ready is the kind of surprise that makes a tool feel unpredictable.
    @Test
    func resolvingPrefersABootedDeviceAmongEqualNames() throws {
        let devices = try Simulator.parseDevices(Data(Self.duplicateNameJSON.utf8))
        let booted = devices.filter { $0.name == "iPhone 17 Pro" }

        #expect(booted.count == 2)
        #expect(booted.first(where: \.isBooted)?.udid == "BOOTED-ONE")
    }

    /// With nothing named, a device another caller has leased is passed over even though it is booted and listed first: the walk takes the next booted device, never the leased one (Brief §2.4).
    @Test
    func resolvingWithNothingNamedPassesOverALeasedBootedDevice() throws {
        let directory = try TemporaryDirectory()
        let leases = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let now = Date(timeIntervalSince1970: 0)
        _ = try leases.acquire(udid: "BOOTED-A", ttl: 3600, holderPID: 41, now: now)
        let list = Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: Self.twoBootedJSON, standardError: "") })

        let resolved = try Simulator.resolve(nil, leases: leases, now: now, shell: list)

        #expect(resolved.udid == "BOOTED-B")
    }

    /// A clone whose lease has lapsed is held all the same — it awaits deletion by `simwalk prune` — so a walk resolving with nothing named passes over it rather than walking a device about to be deleted.
    @Test
    func resolvingWithNothingNamedPassesOverALapsedClone() throws {
        let directory = try TemporaryDirectory()
        let leases = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let now = Date(timeIntervalSince1970: 0)
        _ = try leases.acquire(udid: "BOOTED-A", ttl: 60, holderPID: 41, now: now, createdDevice: true, clonedFrom: "SOURCE")
        let list = Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: Self.twoBootedJSON, standardError: "") })

        let resolved = try Simulator.resolve(nil, leases: leases, now: now.addingTimeInterval(120), shell: list)

        #expect(resolved.udid == "BOOTED-B")
    }

    @Test
    func anUnknownDeviceNameIsRefusedListingWhatIsActuallyThere() {
        let error = SimulatorError.noSuchDevice(requested: "iPhone 99", available: ["iPhone 17 Pro", "iPhone 15"])

        #expect(error.description.contains("iPhone 99"))
        #expect(error.description.contains("iPhone 17 Pro"))
    }

    /// With no `--device` given and nothing booted, `Simulator.resolve` picks a device nobody chose (`devices[0]`) — the refusal must not name it as though it had, so this case is worded on its own (SimWalk#51.2).
    @Test
    func noSimulatorBootedIsWordedWithoutNamingADeviceNobodyChose() {
        let error = SimulatorError.noSimulatorBooted

        #expect(error.description.contains("no simulator is booted"))
        #expect(error.description.contains("xcrun simctl boot"))
    }

    /// The refusal a walk gives when the app is simply not there — the one that would otherwise arrive as a bundle of unreachable screens blaming the walkbook for the environment.
    @Test
    func aMissingAppRefusesBeforeTheWalkAndSaysWhy() {
        let error = SimulatorError.appNotInstalled(bundleID: "dev.simwalk.route-fixture", udid: "UDID-1")

        #expect(error.description.contains("dev.simwalk.route-fixture"))
        #expect(error.description.contains("--app-path"))
    }

    /// The one shape of `get_app_container` failure that legitimately means "not installed" — simctl's own wording for an absent app.
    @Test
    func installedAppPathIsNilOnlyWhenSimctlSaysTheAppIsAbsent() throws {
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)
        let absent = Shell(script: { _, _, _ in
            Shell.Result(
                status: 1,
                standardOutput: "",
                standardError: "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=2):\nNo such file or directory\n"
            )
        })

        let path = try simulator.installedAppPath(bundleID: "com.example.app", shell: absent)

        #expect(path == nil)
    }

    /// Any other non-zero exit — a CoreSimulator error, or another agent shutting the device down between boot and this call, a real risk on a machine several walks share — is the machine failing to answer, not a caller naming a bundle ID that is not there.
    ///
    /// Reading it as "not installed" would classify the failure as `input-refused` and drop it out of `simwalk usage`'s headline.
    @Test
    func installedAppPathThrowsOnAnyOtherSimctlFailure() throws {
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)
        let wedged = Shell(script: { _, _, _ in
            Shell.Result(
                status: 1,
                standardOutput: "",
                standardError: "An error was encountered processing the command (domain=com.apple.CoreSimulator, code=405):\nThe operation could not be completed.\n"
            )
        })

        #expect(throws: SimulatorError.simctlFailed(command: "get_app_container", reason: "The operation could not be completed.")) {
            try simulator.installedAppPath(bundleID: "com.example.app", shell: wedged)
        }
    }

    private static var deviceListJSON: String {
        """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              { "udid": "A-1", "name": "iPhone 17 Pro", "state": "Booted" },
              { "udid": "A-2", "name": "Agent-Sim-2", "state": "Shutdown" }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-17-4": [
              { "udid": "B-1", "name": "iPhone 15", "state": "Shutdown" }
            ]
          }
        }
        """
    }

    private static var mixedPlatformJSON: String {
        """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.watchOS-26-2": [
              { "udid": "W-1", "name": "Apple Watch Series 11 (46mm)", "state": "Shutdown" }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              { "udid": "A-1", "name": "iPhone 17 Pro", "state": "Shutdown" }
            ],
            "com.apple.CoreSimulator.SimRuntime.tvOS-26-0": [
              { "udid": "T-1", "name": "Apple TV 4K", "state": "Shutdown" }
            ]
          }
        }
        """
    }

    private static var twoBootedJSON: String {
        """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              { "udid": "BOOTED-A", "name": "iPhone 17 Pro", "state": "Booted" },
              { "udid": "BOOTED-B", "name": "iPhone 17", "state": "Booted" }
            ]
          }
        }
        """
    }

    private static var duplicateNameJSON: String {
        """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              { "udid": "SHUTDOWN-ONE", "name": "iPhone 17 Pro", "state": "Shutdown" },
              { "udid": "BOOTED-ONE", "name": "iPhone 17 Pro", "state": "Booted" }
            ]
          }
        }
        """
    }
}
