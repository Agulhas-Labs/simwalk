//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// A device read from `simctl` keeps the runtime it is listed under.
struct SimulatorRuntimeIdentifierTests {
    /// The runtime key is stored on the device rather than reduced to a version and dropped.
    @Test
    func parseDevicesKeepsTheRuntimeIdentifier() throws {
        let json = """
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{"udid": "GIZMO-1", "name": "Gizmo Phone", "state": "Shutdown"}]}}
        """

        let devices = try Simulator.parseDevices(Data(json.utf8))

        #expect(devices.map(\.runtimeIdentifier) == ["com.apple.CoreSimulator.SimRuntime.iOS-27-0"])
        #expect(devices.map(\.osVersion) == ["27.0"])
    }
}
