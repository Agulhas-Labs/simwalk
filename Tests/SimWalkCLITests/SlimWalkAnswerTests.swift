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

    /// A walk refused over `--slim` or `--stock` records the refusal as its slim verdict, with no memory, since it touched no device.
    @Test(arguments: ["--stock", "--slim"])
    func aSlimOrStockRefusalIsRecordedAsRefused(_ flag: String) throws {
        let fixture = try WalkDeviceRoutingTests.Fixture()
        let keep = try TemporaryDirectory()
        let machine = WalkDeviceRoutingTests.Machine(phone: DeviceWalkCommandTests().phone(appearances: [DeviceWalkCommandTests.appearance("light")], keep: keep))
        let walk = try WalkCommand.parse([fixture.walkbookPath, "--output", fixture.output, "--device", WalkDeviceRoutingTests.udid, "--team", "TEAM", "--app-path", "App.app", flag])
        let log = UsageLog(directory: keep.url, now: { Date(timeIntervalSince1970: 0) })
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try walk.runServing(log: log, emit: recorder.emit, emitError: recorder.emitError) {
                try walk.walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)
            }
        }

        let entry = try #require(try UsageReport.entries(at: log.fileURL).entries.first)
        #expect(entry.slim == SlimUsage(verdict: .refused))
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

        #expect(refusal.description.hasPrefix("--stock switches a simulator's launchd services back on where a slim walk switched them off"))
        #expect(refusal.usageFailureKind == .inputRefused)
        #expect(machine.phone.calls.allSatisfy { $0.arguments == ["--find", "simctl"] || $0.arguments.starts(with: ["devicectl", "list"]) })
    }
}
