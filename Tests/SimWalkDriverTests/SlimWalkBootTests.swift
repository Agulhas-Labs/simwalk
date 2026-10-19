//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorServices
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What a walk does to a device's launchd services around its boot, and to which devices (a faked `simctl`, a temporary override root).
struct SlimWalkBootTests {
    private static var udid: String {
        "11111111-2222-3333-4444-0000000000A1"
    }

    private static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    }

    private static let start = Date(timeIntervalSince1970: 1_786_867_200)

    private static func service(_ label: String, _ disposition: Disposition) -> ServiceEntry {
        ServiceEntry(label: label, domain: .daemon, start: .keepAlive, ranAtBoot: true, peakFootprintMB: 10, cpuSeconds: 1, disposition: disposition)
    }

    private static let profile = ServiceProfile(
        profileVersion: 3,
        runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A1"),
        deviceType: "iPhone 17",
        generated: "fixture",
        method: ProfileMethod(costWindowSeconds: 1, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
        services: [service("gizmo.a", .disable), service("gizmo.b", .disable), service("gizmo.core", .core)],
        capabilities: [:]
    )

    private static func simulator(booted: Bool, runtime: String? = runtime) -> Simulator {
        Simulator(udid: udid, name: "iPhone 17", osVersion: "27.0", isBooted: booted, runtimeIdentifier: runtime)
    }

    private static var slimText: String {
        "slim: 2 of 3 services off (iOS 27.0, profile v3), kept for the app: nothing"
    }

    /// Case 1: shut down and an app named: the plan is written, replacing what an earlier app left, before the boot the caller makes next.
    @Test
    func aShutDownCreatedDeviceWithAnAppIsWrittenSlimReplacingWhatWasThere() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.left-over"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, appPath: fixture.appPath)

        #expect(provisioned.decision?.text == Self.slimText)
        #expect(provisioned.simulator == Self.simulator(booted: false))
        #expect(try fixture.labels() == ["gizmo.a", "gizmo.b"])
        #expect(fixture.calls.isEmpty)
    }

    /// Case 1, stock outcomes: a runtime with no profile, and `--stock` with an app, remove the override and say why.
    @Test
    func aStockDecisionRemovesTheOverride() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let noProfile = try fixture.provisioning().beforeBoot(Self.simulator(booted: false, runtime: "other"), createdByWalk: true, stockRequested: false, appPath: fixture.appPath)
        #expect(noProfile.decision?.text == "stock: no service profile for iOS 27.0")
        #expect(try fixture.labels().isEmpty)

        try fixture.overrides.write(["gizmo.a"], for: Self.udid)
        let requested = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, appPath: fixture.appPath)
        #expect(requested.decision?.text == "stock: --stock")
        #expect(try fixture.labels().isEmpty)
    }

    /// Case 2: shut down, `--stock`, no app: the override goes and the decision is `--stock`.
    @Test
    func stockWithoutAnAppRemovesTheOverride() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, appPath: nil)

        #expect(provisioned.decision?.text == "stock: --stock")
        #expect(try fixture.labels().isEmpty)
        #expect(fixture.calls.isEmpty)
    }

    /// Case 3: shut down, neither: no decision, and a slim device stays slim.
    @Test
    func neitherFlagLeavesTheOverrideAlone() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, appPath: nil)

        #expect(provisioned.decision == nil)
        #expect(try fixture.labels() == ["gizmo.a"])
        #expect(fixture.provisioning().afterBoot(provisioned) == nil)
    }

    /// Case 4: booted with overrides under `--stock`: shut down first, the override removed, and the device handed back shut down so the boot boots it.
    @Test
    func aBootedCreatedDeviceWithOverridesIsShutDownAndSwitchedBackOnUnderStock() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: true, stockRequested: true, appPath: nil)

        #expect(fixture.calls == [["simctl", "shutdown", Self.udid]])
        #expect(try fixture.labels().isEmpty)
        #expect(provisioned.simulator.isBooted == false)
        #expect(provisioned.decision?.text == "stock: --stock")
    }

    /// Case 5: booted otherwise: no decision, nothing run, nothing changed.
    @Test
    func aBootedCreatedDeviceIsOtherwiseLeftAlone() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        for appPath in [fixture.appPath as String?, nil] {
            let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: true, stockRequested: false, appPath: appPath)
            #expect(provisioned.decision == nil)
            #expect(provisioned.simulator.isBooted)
        }
        #expect(fixture.calls.isEmpty)
        #expect(try fixture.labels() == ["gizmo.a"])

        // `--stock` on a booted device with nothing off changes nothing either.
        let clean = try Fixture()
        let provisioned = try clean.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: true, stockRequested: true, appPath: nil)
        #expect(provisioned.decision == nil)
        #expect(clean.calls.isEmpty)
    }

    /// The override is written before the boot the caller makes and read back after it; a booted device under `--stock` is shut down before its override goes and before the boot.
    @Test
    func theOverrideIsSettledBeforeTheBootAndReadBackAfterIt() throws {
        let fixture = try Fixture()
        var events: [String] = []
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "\"gizmo.a\" => disabled\n\"gizmo.b\" => disabled", standardError: ""))

        let line = try fixture.provisioning().boot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, appPath: fixture.appPath) { device in
            try events.append("boot \(device.isBooted) \(fixture.labels().sorted().joined(separator: ","))")
            events.append("calls \(fixture.calls.count)")
        }

        #expect(events == ["boot false gizmo.a,gizmo.b", "calls 0"])
        #expect(fixture.calls.count == 1)
        #expect(line == "device: \(Self.slimText)")

        let stockFixture = try Fixture()
        try stockFixture.overrides.write(["gizmo.a"], for: Self.udid)
        var atBoot: (calls: [[String]], labels: Set<String>)?
        var bootedAtBoot: Bool?
        _ = try stockFixture.provisioning().boot(Self.simulator(booted: true), createdByWalk: true, stockRequested: true, appPath: nil) { device in
            atBoot = try (stockFixture.calls, stockFixture.labels())
            bootedAtBoot = device.isBooted
        }

        #expect(atBoot?.calls == [["simctl", "shutdown", Self.udid]])
        #expect(atBoot?.labels == [])
        #expect(bootedAtBoot == false)
    }

    /// A device SimWalk did not create never gets an override, whatever the flags and the app.
    @Test
    func aDeviceSimWalkDidNotCreateNeverGetsAnOverride() throws {
        let fixture = try Fixture()

        for booted in [false, true] {
            let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: booted), createdByWalk: false, stockRequested: false, appPath: fixture.appPath)
            #expect(provisioned.decision == nil)
        }
        let stock = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, stockRequested: true, appPath: fixture.appPath)
        #expect(stock.decision == nil)

        #expect(try fixture.labels().isEmpty)
        #expect(try !FileManager.default.fileExists(atPath: fixture.overrides.directory(for: Self.udid).path))
        #expect(fixture.calls.isEmpty)
    }

    /// `--stock` on a device SimWalk did not create that has services off is refused before anything is run or changed.
    @Test
    func stockOnAForeignDeviceWithServicesOffIsRefused() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a", "gizmo.b"], for: Self.udid)

        let refusal = try #require(#expect(throws: SlimWalkError.self) {
            try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, stockRequested: true, appPath: nil)
        })

        #expect(refusal.description == "--stock: \(Self.udid) has 2 launchd services off, and SimWalk did not create it, so it cannot switch them back on — walk a device without them")
        #expect(try fixture.labels() == ["gizmo.a", "gizmo.b"])
        #expect(fixture.calls.isEmpty)
    }

    /// The read-back says slim when every planned label is off on the device.
    @Test
    func aFullReadBackIsSlim() throws {
        let fixture = try Fixture()
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "disabled services = {\n\t\"gizmo.a\" => disabled\n\t\"gizmo.b\" => disabled\n\t\"other\" => enabled\n}", standardError: ""))
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, appPath: fixture.appPath)

        #expect(provisioning.afterBoot(provisioned) == "device: \(Self.slimText)")
        #expect(fixture.calls == [["simctl", "spawn", Self.udid, "launchctl", "print-disabled", "system"]])
    }

    /// A read-back that finds only some of the labels says the runtime did not apply the override.
    @Test
    func aPartialReadBackIsNotSlim() throws {
        let fixture = try Fixture()
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "{\n\t\"gizmo.a\" => disabled\n}", standardError: ""))
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, appPath: fixture.appPath)

        #expect(provisioning.afterBoot(provisioned) == "device: not slim: the runtime did not apply the override (1 of 2 read back)")
    }

    /// A read-back that failed or timed out is unverified and does not throw.
    @Test
    func aFailedOrTimedOutReadBackIsUnverified() throws {
        let fixture = try Fixture()
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, appPath: fixture.appPath)

        fixture.printDisabled = .success(Shell.Result(status: 1, standardOutput: "", standardError: "boom"))
        #expect(provisioning.afterBoot(provisioned) == "device: slim, unverified: the read-back failed: boom")

        fixture.printDisabled = .failure(.timedOut(command: "simctl spawn", seconds: 20))
        #expect(provisioning.afterBoot(provisioned) == "device: slim, unverified: the read-back timed out")
    }

    /// A stock decision is said as it was decided and reads nothing back.
    @Test
    func aStockDecisionIsSaidWithoutAReadBack() throws {
        let fixture = try Fixture()
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, appPath: nil)

        #expect(provisioning.afterBoot(provisioned) == "device: stock: --stock")
        #expect(fixture.calls.isEmpty)
    }

    /// Only a lease that cloned its device makes the device SimWalk's.
    @Test
    func onlyACloneLeaseMakesTheDeviceSimWalks() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let clone = try store.acquire(udid: "CLONE-1", ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SOURCE-1")
        let existing = try store.acquire(udid: "UDID-1", ttl: 60, holderPID: 41, now: Self.start)

        #expect(WalkLease(store: store, udid: "CLONE-1", token: clone.token, taken: false).createdDevice)
        #expect(!WalkLease(store: store, udid: "UDID-1", token: existing.token, taken: false).createdDevice)
        #expect(!WalkLease(store: store, udid: "UDID-1", token: "gone", taken: false).createdDevice)
    }
}

extension SlimWalkBootTests {
    /// An `.app` declaring nothing the profile maps, so every disableable service goes.
    private final class Fixture {
        let directory: TemporaryDirectory
        let overrides: DisabledServicesOverride
        let appPath: String
        private(set) var calls: [[String]] = []
        var printDisabled: Result<Shell.Result, ShellError> = .success(Shell.Result(status: 0, standardOutput: "", standardError: ""))
        init() throws {
            directory = try TemporaryDirectory()
            overrides = DisabledServicesOverride(root: directory.url)
            let app = directory.url.appendingPathComponent("Gizmo.app")
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Gizmo"], format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
            // A 64-bit arm64 image with no load commands, so no entitlements.
            let header: [UInt32] = [0xFEED_FACF, 0x0100_000C, 0, 2, 0, 0, 0, 0]
            try Data(header.flatMap { value in (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) } }).write(to: app.appendingPathComponent("Gizmo"))
            appPath = app.path
        }

        func provisioning() -> SlimWalkProvisioning {
            let shell = Shell(script: { _, arguments, _ in
                self.calls.append(arguments)
                if arguments.first == "simctl", arguments.dropFirst().first == "spawn" {
                    switch self.printDisabled {
                    case let .success(result): return result
                    case let .failure(error): throw error
                    }
                }
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            })
            return SlimWalkProvisioning(shell: shell, overrides: overrides, profileLookup: { $0 == SlimWalkBootTests.runtime ? SlimWalkBootTests.profile : nil })
        }

        func labels() throws -> Set<String> {
            try overrides.labels(for: SlimWalkBootTests.udid)
        }
    }
}
