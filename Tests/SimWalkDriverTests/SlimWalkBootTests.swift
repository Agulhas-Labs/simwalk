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
        "slim: 2 of 3 services off (iOS 27.0, profile v3, bundled), kept for the app: nothing"
    }

    /// Case 1: shut down and an app named: the plan is written, replacing what an earlier app left, before the boot the caller makes next.
    @Test
    func aShutDownCreatedDeviceWithAnAppIsWrittenSlimReplacingWhatWasThere() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.left-over"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)

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

        let noProfile = try fixture.provisioning().beforeBoot(Self.simulator(booted: false, runtime: "other"), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)
        #expect(noProfile.decision?.text == "stock: no service profile for iOS 27.0")
        #expect(try fixture.labels().isEmpty)

        try fixture.overrides.write(["gizmo.a"], for: Self.udid)
        let requested = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: fixture.appPath)
        #expect(requested.decision?.text == "stock: --stock")
        #expect(try fixture.labels().isEmpty)
    }

    /// Case 2: shut down, `--stock`, no app: the override goes and the decision is `--stock`.
    @Test
    func stockWithoutAnAppRemovesTheOverride() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: nil)

        #expect(provisioned.decision?.text == "stock: --stock")
        #expect(try fixture.labels().isEmpty)
        #expect(fixture.calls.isEmpty)
    }

    /// Case 3: shut down, neither: no decision, and a slim device stays slim.
    @Test
    func neitherFlagLeavesTheOverrideAlone() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: nil)

        #expect(provisioned.decision == nil)
        #expect(try fixture.labels() == ["gizmo.a"])
        #expect(fixture.provisioning().afterBoot(provisioned) == nil)
    }

    /// Case 4: booted with overrides under `--stock`: shut down first, the override removed, and the device handed back shut down so the boot boots it.
    @Test
    func aBootedCreatedDeviceWithOverridesIsShutDownAndSwitchedBackOnUnderStock() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: nil)

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
            let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: appPath)
            #expect(provisioned.decision == nil)
            #expect(provisioned.simulator.isBooted)
        }
        #expect(fixture.calls.isEmpty)
        #expect(try fixture.labels() == ["gizmo.a"])

        // `--stock` on a booted device with nothing off changes nothing either, and says so.
        let clean = try Fixture()
        let provisioned = try clean.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: nil)
        #expect(provisioned.decision?.text == "stock: nothing to put back")
        #expect(provisioned.simulator.isBooted)
        #expect(clean.calls.isEmpty)
    }

    /// The override is written before the boot the caller makes and read back after it; a booted device under `--stock` is shut down before its override goes and before the boot.
    @Test
    func theOverrideIsSettledBeforeTheBootAndReadBackAfterIt() throws {
        let fixture = try Fixture()
        var events: [String] = []
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "\"gizmo.a\" => disabled\n\"gizmo.b\" => disabled", standardError: ""))

        let line = try fixture.provisioning().boot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath) { device in
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
        _ = try stockFixture.provisioning().boot(Self.simulator(booted: true), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: nil) { device in
            atBoot = try (stockFixture.calls, stockFixture.labels())
            bootedAtBoot = device.isBooted
        }

        #expect(atBoot?.calls == [["simctl", "shutdown", Self.udid]])
        #expect(atBoot?.labels == [])
        #expect(bootedAtBoot == false)
    }

    /// A device SimWalk did not create never gets an override without `--slim`, whatever the other flag and the app.
    @Test
    func aDeviceSimWalkDidNotCreateNeverGetsAnOverride() throws {
        let fixture = try Fixture()

        for booted in [false, true] {
            let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: booted), createdByWalk: false, stockRequested: false, mayReboot: true, appPath: fixture.appPath)
            #expect(provisioned.decision == nil)
        }
        let stock = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, stockRequested: true, mayReboot: true, appPath: fixture.appPath)
        #expect(stock.decision?.text == "stock: nothing to put back")

        #expect(try fixture.labels().isEmpty)
        #expect(try !FileManager.default.fileExists(atPath: fixture.overrides.directory(for: Self.udid).path))
        #expect(fixture.calls.isEmpty)
    }

    /// `--slim` slims a device SimWalk did not create: the decision, the override written, the same line.
    @Test
    func slimRequestedSlimsADeviceSimWalkDidNotCreate() throws {
        let fixture = try Fixture()

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, slimRequested: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)

        #expect(provisioned.decision?.text == Self.slimText)
        #expect(try fixture.labels() == ["gizmo.a", "gizmo.b"])
        #expect(fixture.calls.isEmpty)
    }

    /// Without `--slim`, the same device with the same app is not slimmed.
    @Test
    func withoutSlimRequestedADeviceSimWalkDidNotCreateIsNotSlimmed() throws {
        let fixture = try Fixture()

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, slimRequested: false, stockRequested: false, mayReboot: true, appPath: fixture.appPath)

        #expect(provisioned.decision == nil)
        #expect(try fixture.labels().isEmpty)
    }

    /// `--stock` puts a slimmed device back exactly: the entries the walk wrote are gone, an entry that was there before stays.
    @Test
    func stockRestoresASlimmedDeviceKeepingForeignEntries() throws {
        let fixture = try Fixture()
        // An entry somebody else put there: written as a property list, not through the library, so it is not the library's to take back.
        let directory = try fixture.overrides.directory(for: Self.udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["gizmo.foreign": true], format: .xml, options: 0).write(to: directory.appendingPathComponent("disabled.plist"))
        _ = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, slimRequested: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)
        #expect(try fixture.labels() == ["gizmo.foreign", "gizmo.a", "gizmo.b"])

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, stockRequested: true, mayReboot: true, appPath: fixture.appPath)

        #expect(provisioned.decision?.text == "stock: --stock")
        #expect(try fixture.labels() == ["gizmo.foreign"])
    }

    /// `--stock` on a device that was never slimmed changes nothing and says there was nothing to put back.
    @Test
    func stockOnANeverSlimmedDeviceIsUntouched() throws {
        let fixture = try Fixture()

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: false, stockRequested: true, mayReboot: true, appPath: nil)

        #expect(provisioned.decision?.text == "stock: nothing to put back")
        #expect(try !FileManager.default.fileExists(atPath: fixture.overrides.directory(for: Self.udid).path))
    }

    /// `--slim` on a booted device the walk may reboot: shut down, slimmed as a shut-down device is, handed back shut down so the boot that follows boots it, and read back after it.
    @Test
    func slimOnABootedDeviceTheWalkMayRebootShutsItDownAndSlimsIt() throws {
        let fixture = try Fixture()
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "\"gizmo.a\" => disabled\n\"gizmo.b\" => disabled", standardError: ""))
        var atBoot: (calls: [[String]], labels: Set<String>)?
        var bootedAtBoot: Bool?

        let line = try fixture.provisioning().boot(Self.simulator(booted: true), createdByWalk: false, slimRequested: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath) { device in
            atBoot = try (fixture.calls, fixture.labels())
            bootedAtBoot = device.isBooted
        }

        #expect(atBoot?.calls == [["simctl", "shutdown", Self.udid]])
        #expect(atBoot?.labels == ["gizmo.a", "gizmo.b"])
        #expect(bootedAtBoot == false)
        #expect(line == "device: \(Self.slimText)")
    }

    /// `--slim` on a booted device the walk may not reboot is refused with the command to run, and nothing is shut down or written.
    @Test
    func slimOnABootedDeviceTheWalkMayNotRebootIsRefused() throws {
        let fixture = try Fixture()

        let refusal = try #require(#expect(throws: SlimWalkError.self) {
            try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: false, slimRequested: true, stockRequested: false, mayReboot: false, appPath: fixture.appPath)
        })

        #expect(refusal.description == "\(Self.udid) is booted and may be in use; launchd reads the switch-off at boot. Shut it down (xcrun simctl shutdown \(Self.udid)) or name it with --device")
        #expect(refusal.usageFailureKind == .inputRefused)
        #expect(fixture.calls.isEmpty)
        #expect(try !FileManager.default.fileExists(atPath: fixture.overrides.directory(for: Self.udid).path))
    }

    /// `--slim` on a booted device that would boot stock anyway (no profile for its runtime) says why and leaves it booted and unchanged.
    @Test
    func slimOnABootedDeviceThatWouldBootStockLeavesItBooted() throws {
        let fixture = try Fixture()

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: true, runtime: "other"), createdByWalk: false, slimRequested: true, stockRequested: false, mayReboot: false, appPath: fixture.appPath)

        #expect(provisioned.decision?.text == "stock: no service profile for iOS 27.0")
        #expect(provisioned.simulator.isBooted)
        #expect(fixture.calls.isEmpty)
        #expect(try fixture.labels().isEmpty)
    }

    /// `--slim` on a booted device an earlier walk slimmed, whose decision now comes out stock (no profile for its runtime): the earlier switch-off is put back, the device shut down first and handed back shut down so the boot that follows boots it stock, or the walk is refused with nothing run or changed when it may not reboot it.
    @Test(arguments: [false, true])
    func slimOnABootedSlimmedDeviceThatNowBootsStockPutsItBack(createdByWalk: Bool) throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)
        let file = try fixture.overrides.directory(for: Self.udid).appendingPathComponent("disabled.plist")
        let before = try Data(contentsOf: file)
        let booted = Self.simulator(booted: true, runtime: "other")

        let refusal = try #require(#expect(throws: SlimWalkError.self) {
            try fixture.provisioning().beforeBoot(booted, createdByWalk: createdByWalk, slimRequested: true, stockRequested: false, mayReboot: false, appPath: fixture.appPath)
        })
        #expect(refusal == .bootedInUse(udid: Self.udid, switchingOff: false))
        #expect(fixture.calls.isEmpty)
        #expect(try Data(contentsOf: file) == before)

        let provisioned = try fixture.provisioning().beforeBoot(booted, createdByWalk: createdByWalk, slimRequested: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)
        #expect(fixture.calls == [["simctl", "shutdown", Self.udid]])
        #expect(provisioned.simulator.isBooted == false)
        #expect(provisioned.decision?.text == "stock: no service profile for iOS 27.0")
        #expect(try fixture.labels().isEmpty)
    }

    /// `--stock` on a booted device the walk slimmed: put back after a shutdown when the walk may reboot it, refused with the command to run when it may not.
    @Test
    func stockOnABootedSlimmedDeviceShutsDownOnlyWhenTheWalkMayRebootIt() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)

        let refusal = try #require(#expect(throws: SlimWalkError.self) {
            try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: false, stockRequested: true, mayReboot: false, appPath: nil)
        })
        #expect(refusal.description == "\(Self.udid) is booted and may be in use; launchd reads the switch-on at boot. Shut it down (xcrun simctl shutdown \(Self.udid)) or name it with --device")
        #expect(fixture.calls.isEmpty)
        #expect(try fixture.labels() == ["gizmo.a"])

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: false, stockRequested: true, mayReboot: true, appPath: nil)
        #expect(fixture.calls == [["simctl", "shutdown", Self.udid]])
        #expect(provisioned.simulator.isBooted == false)
        #expect(provisioned.decision?.text == "stock: --stock")
        #expect(try fixture.labels().isEmpty)
    }

    /// `--stock` counts only what a slim walk switched off: a booted device whose override holds somebody else's entries alone is neither shut down nor refused, and the entries stay.
    @Test
    func stockIgnoresEntriesSimWalkDidNotWrite() throws {
        let fixture = try Fixture()
        let directory = try fixture.overrides.directory(for: Self.udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["gizmo.foreign": true], format: .xml, options: 0).write(to: directory.appendingPathComponent("disabled.plist"))

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: true), createdByWalk: false, stockRequested: true, mayReboot: false, appPath: nil)

        #expect(provisioned.decision?.text == "stock: nothing to put back")
        #expect(provisioned.simulator.isBooted)
        #expect(fixture.calls.isEmpty)
        #expect(try fixture.labels() == ["gizmo.foreign"])
    }

    /// A device SimWalk created has its whole override removed, including one an earlier SimWalk wrote with no record of what it switched off.
    @Test
    func aCreatedDevicesOverrideIsRemovedWholeEvenWithoutARecord() throws {
        let fixture = try Fixture()
        let directory = try fixture.overrides.directory(for: Self.udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["gizmo.a": true], format: .xml, options: 0).write(to: directory.appendingPathComponent("disabled.plist"))

        let provisioned = try fixture.provisioning().beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: nil)

        #expect(provisioned.decision?.text == "stock: --stock")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// A local profile's source is in the line; a refused local profile is a stock line with the reason.
    @Test
    func theLineNamesALocalProfileAndARefusedOne() throws {
        let fixture = try Fixture()
        let file = URL(fileURLWithPath: "/profiles/\(Self.runtime).json")
        let local = fixture.provisioning(resolve: { _ in .found(Self.profile, .local(file)) })
        let provisioned = try local.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)
        #expect(provisioned.decision?.text == "slim: 2 of 3 services off (iOS 27.0, profile v3, local /profiles/\(Self.runtime).json), kept for the app: nothing")

        let refused = fixture.provisioning(resolve: { _ in .unreadable(file, "not valid JSON") })
        let stock = try refused.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)
        #expect(refused.afterBoot(stock) == "device: stock: the local profile /profiles/\(Self.runtime).json was refused: not valid JSON")
        #expect(try fixture.labels().isEmpty)
    }

    /// A device's override file that is there and cannot be parsed is a named refusal that says which file and how to clear it, not the property-list error.
    ///
    /// On a device SimWalk did not create, the walk's own record says it switched something off there, so `--stock` has to read the file.
    @Test(arguments: [(createdByWalk: false, booted: false), (createdByWalk: true, booted: true)])
    func aCorruptOverrideFileUnderStockIsANamedRefusal(createdByWalk: Bool, booted: Bool) throws {
        let fixture = try Fixture()
        let directory = try fixture.overrides.directory(for: Self.udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !createdByWalk {
            try fixture.overrides.write(["gizmo.a"], for: Self.udid)
        }
        let file = directory.appendingPathComponent("disabled.plist")
        try Data("not a property list".utf8).write(to: file)

        let refusal = try #require(#expect(throws: SlimWalkError.self) {
            try fixture.provisioning().beforeBoot(Self.simulator(booted: booted), createdByWalk: createdByWalk, stockRequested: true, mayReboot: true, appPath: nil)
        })

        guard case let .overrideUnreadable(path, _, created) = refusal else {
            Issue.record("expected overrideUnreadable, got \(refusal)")
            return
        }

        #expect(path == file.path)
        #expect(refusal.description.contains(file.path))
        #expect(created == createdByWalk)
        #expect(refusal.description.contains("remove the file"))
        // Shutting down and walking again clears a created device's override, which is removed whole; another's is put back label by label, which reads the file again.
        #expect(refusal.description.contains("shut the device down and walk again") == createdByWalk)
        #expect(refusal.description.contains("--device") == false)
        #expect(refusal.usageFailureKind == .inputRefused)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(fixture.calls.isEmpty)
    }

    /// Every refusal comes before every side effect: a booted device the walk may reboot, whose override file cannot be read while the walk's record says it switched something off there, is refused before it is shut down, under `--slim` with a slim or a stock decision and under `--stock`.
    @Test(arguments: [(stockRequested: false, runtime: runtime), (stockRequested: false, runtime: "other"), (stockRequested: true, runtime: runtime)])
    func aCorruptOverrideFileOnABootedDeviceIsRefusedBeforeTheShutdown(stockRequested: Bool, runtime: String) throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)
        let file = try fixture.overrides.directory(for: Self.udid).appendingPathComponent("disabled.plist")
        let corrupt = Data("not a property list".utf8)
        try corrupt.write(to: file)

        let refusal = try #require(#expect(throws: SlimWalkError.self) {
            try fixture.provisioning().beforeBoot(Self.simulator(booted: true, runtime: runtime), createdByWalk: false, slimRequested: !stockRequested, stockRequested: stockRequested, mayReboot: true, appPath: fixture.appPath)
        })

        guard case let .overrideUnreadable(path, _, createdByWalk) = refusal else {
            Issue.record("expected overrideUnreadable, got \(refusal)")
            return
        }

        #expect(path == file.path)
        #expect(!createdByWalk)
        #expect(fixture.calls.isEmpty)
        #expect(try Data(contentsOf: file) == corrupt)
    }

    /// The read-back says slim when every planned label is off on the device.
    @Test
    func aFullReadBackIsSlim() throws {
        let fixture = try Fixture()
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "disabled services = {\n\t\"gizmo.a\" => disabled\n\t\"gizmo.b\" => disabled\n\t\"other\" => enabled\n}", standardError: ""))
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)

        #expect(provisioning.afterBoot(provisioned) == "device: \(Self.slimText)")
        #expect(fixture.calls == [["simctl", "spawn", Self.udid, "launchctl", "print-disabled", "system"]])
    }

    /// A read-back that finds only some of the labels says the runtime did not apply the override.
    @Test
    func aPartialReadBackIsNotSlim() throws {
        let fixture = try Fixture()
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "{\n\t\"gizmo.a\" => disabled\n}", standardError: ""))
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)

        #expect(provisioning.afterBoot(provisioned) == "device: not slim: the runtime did not apply the override (1 of 2 read back)")
    }

    /// A read-back that failed or timed out is unverified and does not throw.
    @Test
    func aFailedOrTimedOutReadBackIsUnverified() throws {
        let fixture = try Fixture()
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)

        fixture.printDisabled = .success(Shell.Result(status: 1, standardOutput: "", standardError: "boom"))
        #expect(provisioning.afterBoot(provisioned) == "device: slim, unverified: the read-back failed: boom")

        fixture.printDisabled = .failure(.timedOut(command: "simctl spawn", seconds: 20))
        #expect(provisioning.afterBoot(provisioned) == "device: slim, unverified: the read-back timed out")
    }

    /// A stock decision is said as it was decided and reads nothing back.
    @Test
    func aStockDecisionIsSaidWithoutAReadBack() throws {
        let fixture = try Fixture()
        try fixture.overrides.write(["gizmo.a"], for: Self.udid)
        let provisioning = fixture.provisioning()
        let provisioned = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: nil)

        #expect(provisioning.afterBoot(provisioned) == "device: stock: --stock")
        #expect(fixture.calls.isEmpty)
    }

    /// Each branch of the line carries the verdict that line states, and the line itself is the one `afterBoot` prints.
    @Test
    func eachAfterBootBranchStatesItsVerdictBesideItsLine() throws {
        let fixture = try Fixture()
        let provisioning = fixture.provisioning()
        let slimmed = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: false, mayReboot: true, appPath: fixture.appPath)

        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "{\n\t\"gizmo.a\" => disabled\n\t\"gizmo.b\" => disabled\n}", standardError: ""))
        #expect(provisioning.deviceNote(after: slimmed) == SlimWalkProvisioning.DeviceNote(line: "device: \(Self.slimText)", verdict: .slim))
        fixture.printDisabled = .success(Shell.Result(status: 0, standardOutput: "{\n\t\"gizmo.a\" => disabled\n}", standardError: ""))
        #expect(provisioning.deviceNote(after: slimmed)?.verdict == .notSlim)
        fixture.printDisabled = .success(Shell.Result(status: 1, standardOutput: "", standardError: "boom"))
        #expect(provisioning.deviceNote(after: slimmed) == SlimWalkProvisioning.DeviceNote(line: "device: slim, unverified: the read-back failed: boom", verdict: .slimUnverified))
        fixture.printDisabled = .failure(.timedOut(command: "simctl spawn", seconds: 20))
        #expect(provisioning.deviceNote(after: slimmed) == SlimWalkProvisioning.DeviceNote(line: "device: slim, unverified: the read-back timed out", verdict: .slimUnverified))

        try fixture.overrides.write(["gizmo.a"], for: Self.udid)
        let stocked = try provisioning.beforeBoot(Self.simulator(booted: false), createdByWalk: true, stockRequested: true, mayReboot: true, appPath: nil)
        #expect(provisioning.deviceNote(after: stocked) == SlimWalkProvisioning.DeviceNote(line: "device: stock: --stock", verdict: .stock))

        let undecided = SlimWalkProvisioning.Provisioned(simulator: Self.simulator(booted: false), decision: nil)
        #expect(provisioning.deviceNote(after: undecided) == nil)
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

        func provisioning(resolve: ((String) -> ProfileResolution)? = nil) -> SlimWalkProvisioning {
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
            return SlimWalkProvisioning(shell: shell, overrides: overrides, resolve: resolve ?? { $0 == SlimWalkBootTests.runtime ? .found(SlimWalkBootTests.profile, .bundled) : .none })
        }

        func labels() throws -> Set<String> {
            try overrides.labels(for: SlimWalkBootTests.udid)
        }
    }
}
