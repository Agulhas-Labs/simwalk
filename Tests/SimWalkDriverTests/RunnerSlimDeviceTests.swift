//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// A walk tells the runner when its device booted slim, read from the device's launchd override file, so a `systemTap` that saw no sheet can name the services that are off.
struct RunnerSlimDeviceTests {
    private static var runtime: String {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
    }

    private static var udid: String {
        "11111111-2222-3333-4444-0000000000C3"
    }

    private static func service(_ label: String) -> ServiceEntry {
        ServiceEntry(label: label, domain: .daemon, start: .keepAlive, ranAtBoot: true, peakFootprintMB: 10, cpuSeconds: 1, disposition: .disable)
    }

    private static let profile = ServiceProfile(
        profileVersion: 1,
        runtime: ProfileRuntime(identifier: runtime, version: "27.0", build: "24A1"),
        deviceType: "iPhone 17",
        generated: "fixture",
        method: ProfileMethod(costWindowSeconds: 1, footprintThresholdMB: 1, cpuThresholdSeconds: 1, checks: []),
        services: [service("gizmo.a"), service("gizmo.health"), service("gizmo.push")],
        capabilities: [.healthKit: ["gizmo.health"], .pushNotifications: ["gizmo.push"], .photos: ["gizmo.photos"]]
    )

    /// Walks on a device whose override file switches off `labels` (none: no file), returning the runner's environment.
    private static func environment(
        off labels: [String]?, runtime: String? = runtime, profile: ServiceProfile? = profile,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> [String: String] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("slim-device-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if let labels {
            try DisabledServicesOverride(root: root).write(labels, for: udid)
        }
        var runnerEnvironments: [[String: String]] = []
        let shell = Shell(script: { executable, _, environment in
            if executable == "/bin/ps" {
                return Shell.Result(status: 1, standardOutput: "", standardError: "")
            }
            runnerEnvironments.append(environment)
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell, overrideRoot: root, profileLookup: { $0 == runtime ? profile : nil })
        let simulator = Simulator(udid: udid, name: "iPhone 17", osVersion: "27.0", isBooted: true, runtimeIdentifier: runtime)

        try runner.walk(walkbookPath: "/book.json", outputPath: "/out.simwalk", buildHash: "a1b2", logFilePath: nil, on: simulator)

        return try #require(runnerEnvironments.first, sourceLocation: sourceLocation)
    }

    @Test
    func aWalkOnASlimDeviceNamesTheServicesOffAndTheCapabilitiesTheyServe() throws {
        let environment = try Self.environment(off: ["gizmo.a", "gizmo.health", "gizmo.push", "gizmo.other"])

        let runnerSide = Dictionary(uniqueKeysWithValues: environment.compactMap { key, value in
            key.hasPrefix("TEST_RUNNER_") ? (String(key.dropFirst("TEST_RUNNER_".count)), value) : nil
        })
        #expect(environment["TEST_RUNNER_SIMWALK_SLIM_DEVICE"] == "4;healthKit,pushNotifications")
        #expect(SlimDevice.read(in: runnerSide) == SlimDevice(servicesOff: 4, capabilities: ["healthKit", "pushNotifications"]))
    }

    @Test
    func aDeviceWithNoOverrideFileSetsNoKey() throws {
        #expect(try Self.environment(off: nil)["TEST_RUNNER_SIMWALK_SLIM_DEVICE"] == nil)
    }

    @Test
    func aRuntimeWithNoProfileGivesTheCountOnly() throws {
        let environment = try Self.environment(off: ["gizmo.a", "gizmo.health"], profile: nil)

        #expect(environment["TEST_RUNNER_SIMWALK_SLIM_DEVICE"] == "2;")
    }
}
