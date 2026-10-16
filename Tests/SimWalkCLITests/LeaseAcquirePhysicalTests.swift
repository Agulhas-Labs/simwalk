//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `lease acquire --physical` (SimWalk#116): confirms the UDID is a physical device with a read, then leases it, against a scratch store.
struct LeaseAcquirePhysicalTests {
    private static var list: String {
        """
        {"result":{"devices":[{"properties":{
          "hardware":{"reality":"physical","udid":"PHONE-1","marketingName":"iPhone 17","productType":"iPhone18,1"},
          "connection":{"transportType":"wired","pairingState":"paired","state":"connected"},
          "state":{"name":"Test Phone"},
          "software":{"osVersionNumber":{"stringValue":"27.0"}}}}]}}
        """
    }

    private static func shell() -> Shell {
        Shell { _, _, _ in Shell.Result(status: 0, standardOutput: list, standardError: "") }
    }

    @Test
    func aPhysicalUDIDIsLeasedAndMarkedPhysical() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let command = try LeaseAcquireCommand.parse(["--physical", "PHONE-1"])

        let answer = try command.answer(leasing: DeviceLeasing(store: store, shell: Self.shell()), holderPID: 500, now: Date())

        #expect(answer.text.contains("udid: PHONE-1"))
        #expect(store.all().first?.lease.physicalDevice == true)
        let listed = LeaseListCommand.answer(store: store, now: Date())
        #expect(listed.text.contains("physical device"))
    }

    @Test
    func anAbsentUDIDIsRefusedNamingThePhysicalUDIDsPresent() throws {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let command = try LeaseAcquireCommand.parse(["--physical", "SIM-9"])

        let thrown = try #require(#expect(throws: PhysicalDeviceError.self) {
            try command.answer(leasing: DeviceLeasing(store: store, shell: Self.shell()), holderPID: 500, now: Date())
        })

        #expect(thrown.description.contains("PHONE-1"))
        #expect(store.all().isEmpty)
    }

    @Test
    func physicalBesideDeviceOrCloneFromIsAValidationError() {
        #expect(throws: (any Error).self) { try LeaseAcquireCommand.parse(["--physical", "PHONE-1", "--device", "X"]) }
        #expect(throws: (any Error).self) { try LeaseAcquireCommand.parse(["--physical", "PHONE-1", "--clone-from", "X"]) }
    }
}
