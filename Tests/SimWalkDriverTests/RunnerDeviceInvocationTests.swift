//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What the driver hands the runner for a walk on a physical device (SimWalk#116).
struct RunnerDeviceInvocationTests {
    @Test
    func aDeviceWalkNamesTheDeviceDestinationTheTestAndOnlyTheDeviceKeys() throws {
        let calls = CallLog()

        try calls.runner().walkOnDevice(
            walkbookJSON: "{}",
            outputName: "walk.simwalk",
            buildHash: "abc",
            udid: "DEVICE-1",
            nonce: "N1",
            deviceAppearance: .dark,
            runnerCommit: "c0ffee"
        )

        let call = try #require(calls.value.first)

        #expect(call.arguments.contains("platform=iOS,id=DEVICE-1"))
        #expect(call.arguments.contains("-only-testing:SimWalkRunner/WalkRunner/testWalk"))
        #expect(call.environment == [
            "TEST_RUNNER_SIMWALK_WALKBOOK_JSON": "{}",
            "TEST_RUNNER_SIMWALK_OUTPUT": "walk.simwalk",
            "TEST_RUNNER_SIMWALK_OUTPUT_ROOT": "container",
            "TEST_RUNNER_SIMWALK_BUILD_HASH": "abc",
            "TEST_RUNNER_SIMWALK_DEVICE_UDID": "DEVICE-1",
            "TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE": "dark",
            "TEST_RUNNER_SIMWALK_RUNNER_COMMIT": "c0ffee",
            "TEST_RUNNER_SIMWALK_NONCE": "N1",
        ])
    }

    @Test
    func aDeviceWalkOmitsUnknownAppearanceAndCommitAndNeverSetsHostPathKeys() throws {
        let calls = CallLog()

        try calls.runner().walkOnDevice(
            walkbookJSON: "{}", outputName: "w.simwalk", buildHash: "abc", udid: "D", nonce: "N", resultBundlePath: "/r.xcresult"
        )

        let call = try #require(calls.value.first)

        #expect(call.environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] == nil)
        #expect(call.environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] == nil)
        #expect(call.environment["TEST_RUNNER_SIMWALK_LOG"] == nil)
        #expect(call.environment["TEST_RUNNER_SIMWALK_PROGRESS"] == nil)
        #expect(call.environment[DeviceBootTime.hostEnvironmentKey] == nil)
        #expect(call.arguments.suffix(2) == ["-resultBundlePath", "/r.xcresult"])
    }

    @Test
    func aMeasureRunPassesTheSettleAndTheDeviceAppearanceBesideItsRun() throws {
        let calls = CallLog()

        try calls.runner().measureOnDevice(
            MeasureRun(screenID: "general", stateSlug: "light", iterations: 3),
            walkbookJSON: "{}", udid: "D", settleMilliseconds: 750, deviceAppearance: .dark, resultBundlePath: "/r.xcresult"
        )

        let call = try #require(calls.value.first)

        #expect(call.environment["TEST_RUNNER_SIMWALK_SETTLE_MS"] == "750")
        #expect(call.environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] == "dark")
        #expect(call.environment["TEST_RUNNER_SIMWALK_MEASURE_SCREEN"] == "general")
    }

    @Test
    func aDeviceBuildCarriesTheTeamSigningAndAnOverrideOnlyWhenGiven() throws {
        let calls = CallLog()
        // A real directory: a build locks the directory it builds into (SimWalk#242).
        let scratch = try TemporaryDirectory()
        let invocation = calls.runner(derivedDataPath: scratch.url.path)

        try invocation.buildForDevice(udid: "D", team: "TEAM123")
        try invocation.buildForDevice(udid: "D", team: "TEAM123", runnerBundleID: "com.work.runner")
        let plain = try #require(calls.value.first).arguments
        let overridden = try #require(calls.value.last).arguments

        for arguments in [plain, overridden] {
            #expect(arguments.first == "build-for-testing")
            #expect(arguments.contains("platform=iOS,id=D"))
            #expect(arguments.contains("-allowProvisioningUpdates"))
            #expect(arguments.contains("DEVELOPMENT_TEAM=TEAM123"))
            #expect(arguments.contains("CODE_SIGN_STYLE=Automatic"))
        }

        #expect(!plain.contains { $0.hasPrefix("PRODUCT_BUNDLE_IDENTIFIER=") })
        #expect(overridden.contains("PRODUCT_BUNDLE_IDENTIFIER=com.work.runner"))
    }

    @Test
    func theContainerAndSourceNamesFollowTheRunner() {
        #expect(RunnerInvocation.deviceContainerBundleID(runnerBundleID: nil) == "com.agulhaslabs.simwalk.runner.xctrunner")
        #expect(RunnerInvocation.deviceContainerBundleID(runnerBundleID: "com.work.runner") == "com.work.runner.xctrunner")
        #expect(RunnerInvocation.deviceOutputSource(outputName: "w.simwalk") == "Documents/SimWalkOut/w.simwalk")
    }

    /// The project has one `PRODUCT_BUNDLE_IDENTIFIER`, the SimWalkRunner UI-test target's, and `<it>.xctrunner` is the container the driver reads (SimWalk#117).
    @Test
    func theDefaultRunnerBundleIDIsTheOneRunnerProjectDeclares() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appendingPathComponent("Runner/project.yml"), encoding: .utf8)
        let declared = project.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("PRODUCT_BUNDLE_IDENTIFIER:") else { return nil }
            return trimmed.dropFirst("PRODUCT_BUNDLE_IDENTIFIER:".count).trimmingCharacters(in: .whitespaces)
        }
        // xcodebuild builds the committed project, not project.yml, so a hand edit there or a missed regeneration is caught too.
        let pbxproj = try String(contentsOf: root.appendingPathComponent("Runner/SimWalkRunner.xcodeproj/project.pbxproj"), encoding: .utf8)
        let built = Set(pbxproj.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("PRODUCT_BUNDLE_IDENTIFIER = "), trimmed.hasSuffix(";") else { return nil }
            return String(trimmed.dropFirst("PRODUCT_BUNDLE_IDENTIFIER = ".count).dropLast())
        })

        #expect(declared == [RunnerInvocation.defaultRunnerBundleID])
        #expect(built == [RunnerInvocation.defaultRunnerBundleID])
    }

    /// A device session's runner is told its id, launch, device, appearance, commit and idle override — and never its token, which reaches it only through `bind.json` (SimWalk#116, Brief ruling 2).
    @Test
    func aDeviceSessionNamesTheDeviceAndTheSessionTestAndCarriesNoToken() throws {
        let token = try DeviceSessionToken.random()
        let launch = try String(decoding: JSONEncoder().encode(LiveSessionLaunch(appBundleID: "x.y", state: nil)), as: UTF8.self)

        let command = CallLog().runner().deviceSession(
            layout: LiveSessionLayout(directory: URL(fileURLWithPath: "/sessions/s1", isDirectory: true)),
            launchJSON: launch,
            udid: "DEVICE-1",
            runnerCommit: "c0ffee",
            idleOverride: "60",
            deviceAppearance: .light
        )

        #expect(command.arguments == [
            "test-without-building", "-project", "/runner/SimWalkRunner.xcodeproj", "-scheme", "SimWalkRunner",
            "-destination", "platform=iOS,id=DEVICE-1", "-derivedDataPath", "/runner/dd",
            "-only-testing:SimWalkRunner/WalkRunner/testSession", "-collect-test-diagnostics", "never",
            "-resultBundlePath", LiveSessionLayout(directory: URL(fileURLWithPath: "/sessions/s1", isDirectory: true)).resultBundle.path,
        ])
        #expect(command.environment == [
            "TEST_RUNNER_SIMWALK_SESSION_DEVICE": "s1",
            "TEST_RUNNER_SIMWALK_SESSION_LAUNCH_JSON": launch,
            "TEST_RUNNER_SIMWALK_DEVICE_UDID": "DEVICE-1",
            "TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE": "light",
            "TEST_RUNNER_SIMWALK_RUNNER_COMMIT": "c0ffee",
            "TEST_RUNNER_" + LiveSessionIdle.overrideVariable: "60",
        ])
        #expect(!(command.arguments + command.environment.keys + command.environment.values).contains { $0.contains(token.hex) })
    }

    /// The tunnel address is read from the `properties` dictionary, and no address is a tunnel that is not up.
    @Test
    func theTunnelIsTheConnectionsAddressAndNoneWhenItIsDown() throws {
        let listing = try PhysicalDevicePrerequisitesTests.fixture("devicectl-list-devices.json")
        let down = #"{"result":{"devices":[{"connectionProperties":{"tunnelState":"disconnected","tunnelIPAddress":"fd00::1"},"properties":{"hardware":{"udid":"U"},"connection":{}}}]}}"#
        let deprecatedOnly = #"{"result":{"devices":[{"connectionProperties":{"tunnelState":"connected","tunnelIPAddress":"fd05:e6a2:c9c8::1"},"properties":{"hardware":{"udid":"U"}}}]}}"#

        #expect(PhysicalDeviceTunnel.parse(listDevicesJSON: listing, udid: "00008160-00000000000000AA") == PhysicalDeviceTunnel(address: "fd00::1", state: "connected"))
        #expect(PhysicalDeviceTunnel.parse(listDevicesJSON: Data(down.utf8), udid: "U").address == nil)
        #expect(PhysicalDeviceTunnel.parse(listDevicesJSON: Data(deprecatedOnly.utf8), udid: "U").address == "fd05:e6a2:c9c8::1")
        #expect(PhysicalDeviceTunnel.parse(listDevicesJSON: listing, udid: "ELSEWHERE").address == nil)
    }

    /// A simulator session's record is written without a `device` key, and a record from before device sessions still reads.
    @Test
    func aRecordWithoutADeviceEndpointReadsAndWritesAsBefore() throws {
        let old = #"{"id":"s1","pid":42,"udid":"U","app":"x.y","startedAt":0,"foundAppearance":"light"}"#
        let device = LiveSessionRecord.DeviceEndpoint(address: "fd00::1", port: 50000, team: "TEAM", runnerBundleID: nil, leaseToken: "L", leaseTaken: true, appearance: nil)
        let withDevice = LiveSessionRecord(id: "s1", pid: 42, udid: "U", app: "x.y", startedAt: Date(timeIntervalSinceReferenceDate: 0), foundAppearance: .light, device: device)

        let read = try JSONDecoder().decode(LiveSessionRecord.self, from: Data(old.utf8))

        #expect(read.device == nil)
        #expect(try !String(decoding: JSONEncoder().encode(read), as: UTF8.self).contains("device"))
        #expect(try JSONDecoder().decode(LiveSessionRecord.self, from: JSONEncoder().encode(withDevice)) == withDevice)
    }
}

extension RunnerDeviceInvocationTests {
    /// Records each `xcodebuild` call the invocation makes.
    final class CallLog {
        var value: [(arguments: [String], environment: [String: String])] = []

        func runner(derivedDataPath: String = "/runner/dd") -> RunnerInvocation {
            let shell = Shell(script: { _, arguments, environment in
                self.value.append((arguments, environment))
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            })
            return RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: derivedDataPath, shell: shell)
        }
    }
}
