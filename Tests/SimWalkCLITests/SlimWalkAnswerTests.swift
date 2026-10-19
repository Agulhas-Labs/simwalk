//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What a walk says about how it booted its device, and that a physical device refuses `--stock`.
struct SlimWalkAnswerTests {
    @Test
    func theAnswerCarriesTheDeviceLine() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(
            in: directory,
            captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen(), settled: true, hasContent: true)],
            unreachable: [],
            buildHash: "a1b2c3d4",
            nonce: nil
        )
        var outcome = WalkCommand.Outcome(bundle: bundle)
        outcome.deviceNote = "device: stock: --stock"

        #expect(outcome.answer().text.contains("device: stock: --stock"))
    }

    @Test
    func stockOnAPhysicalDeviceIsRefusedBeforeAnythingRuns() throws {
        let fixture = try WalkDeviceRoutingTests.Fixture()
        let keep = try TemporaryDirectory()
        let machine = WalkDeviceRoutingTests.Machine(phone: DeviceWalkCommandTests().phone(appearances: [DeviceWalkCommandTests.appearance("light")], keep: keep))
        let walk = try WalkCommand.parse([fixture.walkbookPath, "--output", fixture.output, "--device", WalkDeviceRoutingTests.udid, "--team", "TEAM", "--stock"])

        let refusal = try #require(#expect(throws: DeviceWalkRefusal.self) {
            try walk.walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)
        })

        #expect(refusal.description.hasPrefix("--stock boots a simulator SimWalk created with every service on"))
        #expect(refusal.usageFailureKind == .inputRefused)
        #expect(machine.phone.calls.allSatisfy { $0.arguments == ["--find", "simctl"] || $0.arguments.starts(with: ["devicectl", "list"]) })
    }
}
