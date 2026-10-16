//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// The refusals of `simwalk device check` (SimWalk#116): each prerequisite refuses by name, in order, and no later `devicectl` command runs once one has.
///
/// The fixtures are real `devicectl` output, scrubbed; the unmet variants are made by mutating the decoded JSON.
struct PhysicalDevicePrerequisitesTests {
    static var udid: String {
        "00008160-00000000000000AA"
    }

    static func fixture(_ name: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil), sourceLocation: sourceLocation)
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// The list-devices fixture with `change` applied to the physical device's `properties`.
    static func list(_ change: (inout [String: Any]) -> Void = { _ in }, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: fixture("devicectl-list-devices.json")) as? [String: Any], sourceLocation: sourceLocation)
        var result = try #require(root["result"] as? [String: Any], sourceLocation: sourceLocation)
        var devices = try #require(result["devices"] as? [[String: Any]], sourceLocation: sourceLocation)
        var properties = try #require(devices[0]["properties"] as? [String: Any], sourceLocation: sourceLocation)
        change(&properties)
        devices[0]["properties"] = properties
        result["devices"] = devices
        root["result"] = result
        return try JSONSerialization.data(withJSONObject: root)
    }

    static func setting(_ section: String, _ key: String, to value: Any?) -> (inout [String: Any]) -> Void {
        { properties in
            var inner = properties[section] as? [String: Any] ?? [:]
            inner[key] = value
            properties[section] = inner
        }
    }

    static func script(list: Data? = nil, locked: Bool = false) throws -> Script {
        try Script(
            list: list ?? self.list(),
            lock: fixture(locked ? "devicectl-lockstate-locked.json" : "devicectl-lockstate-unlocked.json")
        )
    }

    @Test
    func noTeamRefusesBeforeRunningAnything() throws {
        let script = try Self.script()

        #expect(throws: PhysicalDeviceError.noTeam) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: nil, shell: script.shell)
        }
        #expect(throws: PhysicalDeviceError.noTeam) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "  ", shell: script.shell)
        }
        #expect(script.calls.isEmpty)
    }

    @Test
    func aSimulatorUDIDIsNotFoundAndThePresentPhysicalOnesAreListed() throws {
        let script = try Self.script()
        let simulator = "11111111-2222-3333-4444-000000000008"

        #expect(throws: PhysicalDeviceError.notFound(udid: simulator, present: [Self.udid])) {
            try PhysicalDevicePrerequisites.check(udid: simulator, team: "TEAM", shell: script.shell)
        }
        #expect(script.calls.count == 1)
        #expect(!script.calls.contains { $0.contains("lockState") })
    }

    @Test
    func anUnpairedDeviceRefusesBeforeLockStateIsRead() throws {
        let script = try Self.script(list: Self.list(Self.setting("connection", "pairingState", to: "unpaired")))

        #expect(throws: PhysicalDeviceError.notPaired(udid: Self.udid, state: "unpaired")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
        #expect(script.calls.count == 1)
    }

    @Test
    func aDeviceStillDisconnectedAfterOneCallToItRefusesNotConnected() throws {
        let script = try Self.script(list: Self.list(Self.setting("connection", "state", to: "disconnected")))

        #expect(throws: PhysicalDeviceError.notConnected(udid: Self.udid, state: "disconnected")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
        #expect(script.calls.map { $0.contains("lockState") ? "lockState" : "list" } == ["list", "lockState", "list"])
    }

    /// Over Wi-Fi a paired device lists as `disconnected` until a call opens its tunnel; measured on an iPad, one `lockState` call turned it `connected`.
    @Test
    func aNetworkDeviceListedDisconnectedIsConnectedByOneCallAndPasses() throws {
        let script = try Self.script(list: Self.list(Self.setting("connection", "state", to: "disconnected")))
        script.listAfterConnect = try Self.list()

        let device = try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)

        #expect(device.connectionState == "connected")
        #expect(script.calls.map { $0.contains("lockState") ? "lockState" : "list" } == ["list", "lockState", "list", "lockState"])
    }

    @Test
    func anOfflineDeviceMissingItsTransportAndStateNameStillRefusesNotConnected() throws {
        let list = try Self.list { properties in
            Self.setting("connection", "transportType", to: nil)(&properties)
            Self.setting("connection", "state", to: "disconnected")(&properties)
            Self.setting("state", "name", to: nil)(&properties)
        }
        let script = try Self.script(list: list)

        #expect(throws: PhysicalDeviceError.notConnected(udid: Self.udid, state: "disconnected")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
    }

    @Test
    func anUnpairedDeviceMissingItsNameAndOSVersionStillRefusesNotPaired() throws {
        let list = try Self.list { properties in
            Self.setting("connection", "pairingState", to: "unpaired")(&properties)
            Self.setting("state", "name", to: nil)(&properties)
            Self.setting("hardware", "marketingName", to: nil)(&properties)
            properties["software"] = [String: Any]()
        }
        let script = try Self.script(list: list)

        #expect(throws: PhysicalDeviceError.notPaired(udid: Self.udid, state: "unpaired")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
    }

    @Test
    func developerModeOffNamesWhatDevicectlReportedAndNeverReadsLockState() throws {
        let script = try Self.script(list: Self.list(Self.setting("state", "developerModeStatus", to: ["disabled": [String: Int]()])))

        #expect(throws: PhysicalDeviceError.developerModeOff(udid: Self.udid, reported: "{\"disabled\":{}}")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
        #expect(script.calls.count == 1)
    }

    @Test
    func aStringDeveloperModeStatusIsNotEnabled() throws {
        let script = try Self.script(list: Self.list(Self.setting("state", "developerModeStatus", to: "enabled")))

        #expect(throws: PhysicalDeviceError.developerModeOff(udid: Self.udid, reported: "\"enabled\"")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
    }

    @Test
    func aMissingDeveloperModeStatusIsUnreadableNotAssumedEnabled() throws {
        let script = try Self.script(list: Self.list(Self.setting("state", "developerModeStatus", to: nil)))

        #expect(throws: PhysicalDeviceError.unreadable(command: "devicectl list devices", reason: "properties.state.developerModeStatus is missing for \(Self.udid)")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
        #expect(script.calls.count == 1)
    }

    @Test
    func aMissingPairingStateIsUnreadableAndNamesTheCommand() throws {
        let script = try Self.script(list: Self.list(Self.setting("connection", "pairingState", to: nil)))

        #expect(throws: PhysicalDeviceError.unreadable(command: "devicectl list devices", reason: "properties.connection.pairingState is missing for \(Self.udid)")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
    }

    @Test
    func aLockedDeviceRefusesAndTheRefusalNamesUnlocking() throws {
        let script = try Self.script(locked: true)

        #expect(throws: PhysicalDeviceError.locked(udid: Self.udid)) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
        #expect(PhysicalDeviceError.locked(udid: Self.udid).description.contains("unlock it"))
        #expect(script.calls.count == 2)
    }

    @Test
    func anUnreadableLockStateRefusesByCommandName() throws {
        let script = try Script(list: Self.list(), lock: Data("{}".utf8))

        #expect(throws: PhysicalDeviceError.unreadable(command: "devicectl device info lockState", reason: "result.passcodeRequired is missing")) {
            try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)
        }
    }

    @Test
    func aPassingDeviceIsReturnedParsed() throws {
        let script = try Self.script()

        let device = try PhysicalDevicePrerequisites.check(udid: Self.udid, team: "TEAM", shell: script.shell)

        #expect(device == PhysicalDevice(
            udid: Self.udid,
            name: "iPhone",
            marketingName: "iPhone 18 Pro Max",
            productType: "iPhone19,7",
            osVersion: "27.0.1",
            transportType: "localNetwork",
            pairingState: "paired",
            connectionState: "connected",
            developerModeEnabled: true,
            developerModeReport: "{\"enabled\":{\"mode\":1}}"
        ))
        #expect(script.calls.map { Array($0.prefix(3)) } == [["devicectl", "list", "devices"], ["devicectl", "device", "info"]])
    }

    @Test
    func appearanceParsesStyleTextSizeAndContrast() throws {
        let appearance = try PhysicalDeviceAppearance.parse(appearanceJSON: Self.fixture("devicectl-appearance-light.json"))

        #expect(appearance == PhysicalDeviceAppearance(userInterfaceStyle: "light", textSize: "Large", increaseContrast: false))
    }
}

extension PhysicalDevicePrerequisitesTests {
    /// Answers `devicectl` from a list-devices document and a lock-state document, recording the arguments of each call.
    ///
    /// `listAfterConnect`, when set, is the listing once a `lockState` call has been made — a network device that call connected.
    final class Script {
        var calls: [[String]] = []
        let list: Data
        let lock: Data
        var listAfterConnect: Data?

        init(list: Data, lock: Data) {
            self.list = list
            self.lock = lock
        }

        var shell: Shell {
            Shell(script: { _, arguments, _ in
                let connected = self.calls.contains { $0.contains("lockState") }
                self.calls.append(arguments)
                let json = arguments.contains("lockState") ? self.lock : (connected ? self.listAfterConnect ?? self.list : self.list)
                return Shell.Result(status: 0, standardOutput: String(decoding: json, as: UTF8.self), standardError: "")
            })
        }
    }
}
