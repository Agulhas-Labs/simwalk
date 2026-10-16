//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// What a live session's resident runner is spawned with.
struct RunnerSessionCommandTests {
    /// The session test alone, the session's directory and result bundle, and the host's idle override passed on under the runner's prefix.
    @Test
    func asessionRunsTheSessionTestWithItsDirectoryAndIdleOverride() {
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd")
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        let command = runner.session(layout: Self.layout, logFilePath: "/logs/usage.jsonl", runnerCommit: "c0ffee", idleOverride: "20", deviceAppearance: nil, on: simulator)

        #expect(command.executable == "/usr/bin/xcodebuild")
        #expect(command.arguments.contains("-only-testing:SimWalkRunner/WalkRunner/testSession"))
        #expect(command.arguments.contains("platform=iOS Simulator,id=UDID-1"))
        #expect(command.arguments.suffix(2) == ["-resultBundlePath", Self.layout.resultBundle.path])
        #expect(command.environment == [
            "TEST_RUNNER_SIMWALK_SESSION": "/s/abc",
            "TEST_RUNNER_SIMWALK_LOG": "/logs/usage.jsonl",
            "TEST_RUNNER_SIMWALK_RUNNER_COMMIT": "c0ffee",
            "TEST_RUNNER_SIMWALK_SESSION_IDLE_SECONDS": "20",
        ])
    }

    /// The device's appearance as `start` found it goes to the runner, which puts it back on every exit — an idle one included, which no host command sees.
    @Test
    func aSessionCarriesTheFoundDeviceAppearance() {
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd")
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        let command = runner.session(layout: Self.layout, logFilePath: nil, runnerCommit: nil, idleOverride: nil, deviceAppearance: .light, on: simulator)

        #expect(command.environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] == "light")
    }

    /// A session tells the runner when its device booted as a walk does, so its `systemTap` steps can name a fresh boot (SimWalk#88).
    @Test
    func aSessionTellsTheRunnerWhenTheDeviceBooted() throws {
        let shell = Shell(script: { _, _, _ in
            let line = "84326 01:10 launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/UDID-1/data/var/run/launchd_bootstrap.plist\n"
            return Shell.Result(status: 0, standardOutput: line, standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)
        let before = Date()

        let command = runner.session(layout: Self.layout, logFilePath: nil, runnerCommit: nil, idleOverride: nil, deviceAppearance: nil, on: simulator)

        let read = try #require(command.environment["TEST_RUNNER_SIMWALK_DEVICE_BOOTED_AT"].flatMap(TimeInterval.init))

        #expect(read >= before.timeIntervalSince1970 - 70 && read <= Date().timeIntervalSince1970 - 70)
    }

    /// A walk and a session share one command line apart from the test they name.
    @Test
    func aSessionAndAWalkShareTheirCommandLineButTheTest() throws {
        var walked: [[String]] = []
        let shell = Shell(script: { _, arguments, _ in
            walked.append(arguments)
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        try runner.inspect(appBundleID: "a", outputPath: "/o", logFilePath: nil, runnerCommit: nil, nonce: "n", resultBundlePath: Self.layout.resultBundle.path, on: simulator)
        let session = runner.session(layout: Self.layout, logFilePath: nil, runnerCommit: nil, idleOverride: nil, deviceAppearance: nil, on: simulator)

        let walk = try #require(walked.first)

        #expect(walk.map { $0.replacingOccurrences(of: "testWalk", with: "testSession") } == session.arguments)
    }
}

extension RunnerSessionCommandTests {
    static let layout = LiveSessionLayout(directory: URL(fileURLWithPath: "/s/abc", isDirectory: true))
}
