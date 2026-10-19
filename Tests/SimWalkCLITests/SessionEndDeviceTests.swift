//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `session end` on a physical device's record runs the device's stop: devicectl, not `simctl`, and the session's lease released.
struct SessionEndDeviceTests {
    /// A device session whose runner has exited is ended through devicectl alone — exit record, appearance, the runner's container — its lease released and its directory removed.
    @Test
    func aDeviceRecordIsEndedByTheDeviceStop() throws {
        let directory = try TemporaryDirectory()
        let store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
        let layout = try store.create(id: "s1")
        let leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in true }
        _ = try leases.acquire(udid: "PHONE", ttl: 1800, holderPID: 1, now: Date(), physicalDevice: true, token: "LEASE-1")
        let appearance = try PhysicalDeviceAppearance.parse(appearanceJSON: Data(Self.light.utf8))
        let device = LiveSessionRecord.DeviceEndpoint(address: "fd00::1", port: 50000, team: "TEAM", runnerBundleID: nil, leaseToken: "LEASE-1", leaseTaken: true, appearance: appearance)
        try store.write(LiveSessionRecord(id: "s1", pid: 4242, udid: "PHONE", app: "com.example.app", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light, device: device))
        var executables: [String] = []
        let shell = Shell { executable, arguments, _ in
            executables.append(([executable] + arguments.prefix(1)).joined(separator: " "))
            let output = arguments.contains("appearance") ? Self.light : ""
            return Shell.Result(status: 0, standardOutput: output, standardError: "")
        }

        let answer = try SessionEndCommand.parse(["s1"]).perform(store: store, processes: FakeSessionProcesses(), leases: leases, shell: shell, pause: { _ in }, now: { Date() })

        #expect(Set(executables) == ["/usr/bin/xcrun devicectl"])
        #expect(answer.residue.contains("runner container emptied"))
        #expect(answer.residue.contains("released the session's lease on PHONE"))
        #expect(answer.residue.contains("removed \(layout.directory.path)"))
        #expect(try leases.lease(onDevice: "PHONE") == nil)
    }

    private static var light: String {
        #"{"result":{"userInterfaceStyle":"light","textSize":"Large","increaseContrast":false}}"#
    }
}
