//
// Copyright © Agulhas Labs
//

import SimWalkCore
@testable import SimWalkDriver
import Testing

/// Which of this module's own errors the usage log counts as an `input-refused` bad argument versus a `runner-failed` machinery problem.
struct UsageFailureKindTests {
    /// A caller-named value that does not match reality — a bad argument, the same as any other.
    @Test
    func simulatorErrorNamingASpecificBadValueIsInputRefused() {
        let noSuchDevice = SimulatorError.noSuchDevice(requested: "iPhone 99", available: ["iPhone 17 Pro"])
        let appNotInstalled = SimulatorError.appNotInstalled(bundleID: "com.example.app", udid: "UDID-1")

        #expect(UsageFailureKind.of(noSuchDevice) == .inputRefused)
        #expect(UsageFailureKind.of(appNotInstalled) == .inputRefused)
        let refusal = DeviceFamilyCheck.Refusal(bundleID: "com.example.app", families: [1], deviceName: "iPad", udid: "UDID-1")
        #expect(UsageFailureKind.of(SimulatorError.iPhoneOnlyAppOnIPad(refusal)) == .inputRefused)
    }

    /// `simctl`, or the machine it runs on, not answering the way the walk needs — nothing any argument could have prevented.
    @Test
    func simulatorErrorAboutSimctlItselfIsRunnerFailed() {
        let noDevices = SimulatorError.noDevices
        let unreadableList = SimulatorError.unreadableDeviceList
        let simctlFailed = SimulatorError.simctlFailed(command: "boot", reason: "timed out")

        #expect(UsageFailureKind.of(noDevices) == .runnerFailed)
        #expect(UsageFailureKind.of(unreadableList) == .runnerFailed)
        #expect(UsageFailureKind.of(simctlFailed) == .runnerFailed)
    }

    @Test
    func runnerErrorIsAlwaysRunnerFailed() {
        let buildFailed = RunnerError.buildFailed(reason: "compile error")
        let walkFailed = RunnerError.walkFailed(reason: "crashed")

        #expect(UsageFailureKind.of(buildFailed) == .runnerFailed)
        #expect(UsageFailureKind.of(walkFailed) == .runnerFailed)
    }

    @Test
    func runnerProjectErrorIsAlwaysRunnerFailed() {
        let cases: [RunnerProjectError] = [
            .overrideMissing(variable: "SIMWALK_RUNNER_PROJECT", path: "/nope"),
            .notInstalled(binaryHash: "abcd", latest: nil, variable: "SIMWALK_RUNNER_PROJECT"),
            .snapshotMissing(path: "/nope", commit: "abcd"),
            .binaryUnreadable(variable: "SIMWALK_RUNNER_PROJECT"),
        ]

        for error in cases {
            #expect(UsageFailureKind.of(error) == .runnerFailed)
        }
    }

    /// Every caller of `Shell.run` in this package is launching something a walk needs to run at all.
    @Test
    func shellErrorIsRunnerFailed() {
        let error = ShellError.couldNotRun(executable: "/usr/bin/xcrun", reason: "not found")

        #expect(UsageFailureKind.of(error) == .runnerFailed)
    }
}
