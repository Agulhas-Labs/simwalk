//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// What the driver hands the runner for a live read (SimWalk#49): the environment is the only channel into a test bundle, so which keys it sets is the whole contract.
struct RunnerInvocationTests {
    /// A live read tells the runner it is one, names the app, the output and the nonce, and runs the same test a walk runs — with no walkbook, since there is none.
    @Test
    func aliveReadTellsTheRunnerItsModeAppOutputAndNonce() throws {
        var calls: [(arguments: [String], environment: [String: String])] = []
        let shell = Shell(script: { _, arguments, environment in
            calls.append((arguments, environment))
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        try runner.inspect(
            appBundleID: "com.example.app",
            outputPath: "/scratch/live.json",
            logFilePath: "/logs/usage.jsonl",
            runnerCommit: "c0ffee",
            nonce: "NONCE-1",
            resultBundlePath: "/runner/dd/Logs/Test/one.xcresult",
            on: simulator
        )

        let call = try #require(calls.first)

        #expect(calls.count == 1)
        #expect(call.environment == [
            "TEST_RUNNER_SIMWALK_INSPECT": "1",
            "TEST_RUNNER_SIMWALK_APP_BUNDLE_ID": "com.example.app",
            "TEST_RUNNER_SIMWALK_OUTPUT": "/scratch/live.json",
            "TEST_RUNNER_SIMWALK_NONCE": "NONCE-1",
            "TEST_RUNNER_SIMWALK_LOG": "/logs/usage.jsonl",
            "TEST_RUNNER_SIMWALK_RUNNER_COMMIT": "c0ffee",
        ])
        #expect(call.arguments.contains("test-without-building"))
        #expect(call.arguments.contains("-only-testing:SimWalkRunner/WalkRunner/testWalk"))
        #expect(call.arguments.contains("platform=iOS Simulator,id=UDID-1"))
        #expect(call.arguments.suffix(2) == ["-resultBundlePath", "/runner/dd/Logs/Test/one.xcresult"])
    }

    /// A runner that fails is never followed by a sysdiagnose: `xcodebuild` would otherwise spend up to ten minutes on `simctl diagnose` before the walk hears of a failure that has already happened (SimWalk#54).
    @Test
    func therunnerNeverCollectsTestDiagnostics() throws {
        var calls: [[String]] = []
        let shell = Shell(script: { _, arguments, _ in
            calls.append(arguments)
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        try runner.inspect(appBundleID: "com.example.app", outputPath: "/scratch/live.json", logFilePath: nil, runnerCommit: nil, nonce: "NONCE-1", on: simulator)

        let arguments = try #require(calls.first)
        let flag = try #require(arguments.firstIndex(of: "-collect-test-diagnostics"))

        #expect(arguments.dropFirst(flag + 1).first == "never")
    }

    /// A runner that exits non-zero is a runner failure carrying its own diagnostic, as a walk's is.
    @Test
    func aliveReadWhoseRunnerFailsThrowsTheRunnersDiagnostic() {
        let shell = Shell(script: { _, _, _ in
            Shell.Result(status: 65, standardOutput: "WalkRunner.swift:40: error: SIMWALK_NONCE not set\n** TEST FAILED **\n", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        #expect(throws: RunnerError.walkFailed(reason: "WalkRunner.swift:40: error: SIMWALK_NONCE not set")) {
            try runner.inspect(appBundleID: "com.example.app", outputPath: "/scratch/live.json", logFilePath: nil, runnerCommit: nil, nonce: "NONCE-1", on: simulator)
        }
    }

    /// A walk tells the runner when its device booted, read from the device's `launchd_sim` before the runner starts, so a `systemTap` that saw no sheet can name a fresh boot (SimWalk#88); a `ps` that cannot say leaves it out.
    @Test(arguments: [true, false])
    func aWalkTellsTheRunnerWhenTheDeviceBootedWhereItCanBeRead(readable: Bool) throws {
        var runnerEnvironments: [[String: String]] = []
        let shell = Shell(script: { executable, _, environment in
            guard executable == "/bin/ps" else {
                runnerEnvironments.append(environment)
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }
            let line = "84326 01:10 launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/UDID-1/data/var/run/launchd_bootstrap.plist\n"
            return Shell.Result(status: readable ? 0 : 1, standardOutput: readable ? line : "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)
        let before = Date()

        try runner.walk(walkbookPath: "/book.json", outputPath: "/out.simwalk", buildHash: "a1b2", logFilePath: nil, on: simulator)

        let environment = try #require(runnerEnvironments.first)
        let bootedAt = environment["TEST_RUNNER_SIMWALK_DEVICE_BOOTED_AT"].flatMap(TimeInterval.init)

        #expect(runnerEnvironments.count == 1)
        guard readable else {
            #expect(bootedAt == nil)
            return
        }
        let read = try #require(bootedAt)
        #expect(read >= before.timeIntervalSince1970 - 70 && read <= Date().timeIntervalSince1970 - 70)

        // The key the host writes is the key the runner's parse reads back (SimWalk#90 item 3): strip the prefix `xcodebuild` strips.
        let runnerSide = Dictionary(uniqueKeysWithValues: environment.compactMap { key, value in
            key.hasPrefix("TEST_RUNNER_") ? (String(key.dropFirst("TEST_RUNNER_".count)), value) : nil
        })
        let age = try #require(DeviceBootTime.age(in: runnerSide, now: Date()))
        #expect(age >= 70 && age <= 70 + Date().timeIntervalSince(before) + 1)
    }

    /// The animations-off library reaches the runner under the key its own read takes back (SimWalk#154), and a walk handed none sets nothing.
    @Test(arguments: ["/libs/animations-1.dylib", nil])
    func aWalkHandsTheRunnerTheAnimationsOffLibraryOnlyWhenGivenOne(library: String?) throws {
        var runnerEnvironments: [[String: String]] = []
        let shell = Shell(script: { executable, _, environment in
            if executable.hasSuffix("xcodebuild") {
                runnerEnvironments.append(environment)
            }
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        try runner.walk(walkbookPath: "/book.json", outputPath: "/out.simwalk", buildHash: "a1b2", logFilePath: nil, animationsOffLibrary: library, on: simulator)

        let environment = try #require(runnerEnvironments.first)

        #expect(environment["TEST_RUNNER_SIMWALK_ANIMATIONS_OFF_LIBRARY"] == library)
        #expect(environment[AnimationsOptIn.hostEnvironmentKey] == library)
    }

    /// A session tells the runner where the animations-off library is only when it is passed one (SimWalk#154).
    @Test(arguments: [nil, "/libs/animations-1.dylib"])
    func aSessionTellsTheRunnerTheAnimationsLibraryOnlyWhenPassedOne(library: String?) {
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: "", standardError: "") }))
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)
        let layout = LiveSessionStore(directory: URL(fileURLWithPath: "/sessions")).layout(id: "s1")

        let command = runner.session(layout: layout, logFilePath: nil, runnerCommit: nil, idleOverride: nil, deviceAppearance: nil, animationsOffLibrary: library, on: simulator)

        #expect(command.environment[AnimationsOptIn.hostEnvironmentKey] == library)
    }

    /// `--motion` reaches the runner as the key its own read takes back (SimWalk#67): every screen records, a screen asking alone without it, and a walk without the flag sets nothing.
    @Test(arguments: [true, false])
    func aWalkTellsTheRunnerToRecordMotionOnlyWhenAsked(motion: Bool) throws {
        var runnerEnvironments: [[String: String]] = []
        let shell = Shell(script: { executable, _, environment in
            if executable.hasSuffix("xcodebuild") {
                runnerEnvironments.append(environment)
            }
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        try runner.walk(walkbookPath: "/book.json", outputPath: "/out.simwalk", buildHash: "a1b2", logFilePath: nil, motion: motion, on: simulator)

        let environment = try #require(runnerEnvironments.first)
        let runnerSide = Dictionary(uniqueKeysWithValues: environment.compactMap { key, value in
            key.hasPrefix("TEST_RUNNER_") ? (String(key.dropFirst("TEST_RUNNER_".count)), value) : nil
        })
        let asking = Walkbook.Screen(id: "a", route: [], states: [Walkbook.CaptureState(theme: .light)], motion: true)
        let silent = Walkbook.Screen(id: "b", route: [], states: [Walkbook.CaptureState(theme: .light)])

        #expect((environment[MotionOptIn.hostEnvironmentKey] != nil) == motion)
        #expect([asking, silent].map { MotionOptIn.records($0, in: runnerSide) } == [true, motion])
    }
}
