//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// The `simctl launch` that says whether the device or the app is at fault after two launch timeouts (SimWalk#266).
struct SimctlLaunchCheckTests {
    private let simulator = Simulator(udid: "UDID-1", name: "iPhone 17", osVersion: "27.0", isBooted: true)

    private func check(_ launch: @escaping () throws -> Shell.Result, calls: Calls) -> SimctlLaunchCheck {
        let shell = Shell(timedScript: { _, arguments, environment, timeout in
            calls.all.append(Calls.Call(arguments: arguments, environment: environment, timeout: timeout))
            if arguments.contains("launch") {
                return try launch()
            }
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        return SimctlLaunchCheck.perform(on: simulator, bundleID: "com.x", arguments: ["-a", "b"], environment: ["K": "V"], shell: shell)
    }

    @Test
    func aLaunchGivesItsPidWithPrefixedEnvironmentAndIsTerminatedAfter() {
        let calls = Calls()
        let result = check({ Shell.Result(status: 0, standardOutput: "com.x: 4312\n", standardError: "") }, calls: calls)

        #expect(result == .launched(pid: 4312))
        #expect(calls.all.count == 2)
        #expect(calls.all[0].arguments == ["simctl", "launch", "UDID-1", "com.x", "-a", "b"])
        #expect(calls.all[0].environment == ["SIMCTL_CHILD_K": "V"])
        #expect(calls.all[1].arguments == ["simctl", "terminate", "UDID-1", "com.x"])
        #expect(calls.all[1].timeout == DeviceSettle.handbackBound)
    }

    @Test
    func aRefusalIsSimctlsDeepestCauseNotItsHeader() {
        let calls = Calls()
        // `simctl launch` of a bundle that is not installed, as Xcode 27's simctl printed it.
        let stderr = """
        An error was encountered processing the command (domain=FBSOpenApplicationServiceErrorDomain, code=4):
        Simulator device failed to launch com.example.not-installed.
        Underlying error (domain=FBSOpenApplicationServiceErrorDomain, code=4):
        \tThe request to open "com.example.not-installed" failed.

        """
        let result = check({ Shell.Result(status: 4, standardOutput: "", standardError: stderr) }, calls: calls)

        #expect(result == .refused(reason: "The request to open \"com.example.not-installed\" failed."))
        #expect(calls.all.last?.arguments.contains("terminate") == true)
    }

    @Test
    func aRefusalInCoreSimulatorsOwnDomainIsTheDevices() {
        // `simctl launch` on a device that is shut down, as Xcode 27's simctl printed it.
        let stderr = """
        An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):
        Unable to lookup in current state: Shutdown

        """
        let result = check({ Shell.Result(status: 149, standardOutput: "", standardError: stderr) }, calls: Calls())

        #expect(result == .deviceRefused(reason: "Unable to lookup in current state: Shutdown"))
    }

    @Test
    func aRefusalWithNoTextNamesTheStatusAndUnparseableOutputIsARefusal() {
        #expect(check({ Shell.Result(status: 3, standardOutput: "", standardError: "") }, calls: Calls()) == .refused(reason: "simctl exited 3"))
        #expect(check({ Shell.Result(status: 0, standardOutput: "garbage\n", standardError: "") }, calls: Calls()) == .refused(reason: "garbage"))
    }

    @Test
    func aTimeoutIsUnanswered() {
        let calls = Calls()
        let result = check({ throw ShellError.timedOut(command: "simctl launch", seconds: 60) }, calls: calls)

        #expect(result == .unanswered(seconds: 60))
        #expect(calls.all.last?.arguments.contains("terminate") == true)
    }

    @Test
    func anyOtherThrowIsARefusal() {
        let result = check({ throw ShellError.stopped }, calls: Calls())

        #expect(result == .refused(reason: "\(ShellError.stopped)"))
    }

    @Test
    func theLinesAreExact() {
        let context = " (booted 41 s ago; host load average 990)"
        let slow = "the device was slow to answer XCUITest, not the app — walk again once it settles"

        #expect(SimctlLaunchCheck.launched(pid: 4312).line(attempts: 2, bootedAgo: 41, loadAverage: 990)
            == "the app launches with simctl (pid 4312), but XCUITest timed out launching it twice: \(slow)\(context)")
        #expect(SimctlLaunchCheck.launched(pid: 4312).line(attempts: 1, bootedAgo: 41, loadAverage: 990)
            == "the app launches with simctl (pid 4312), but XCUITest timed out launching it, and the walk did not try again because the runner had already written to its output: \(slow)\(context)")
        #expect(SimctlLaunchCheck.refused(reason: "boom").line(attempts: 2, bootedAgo: 41, loadAverage: 990)
            == "the app did not launch with simctl either (boom): the app or its install, not XCUITest")
        #expect(SimctlLaunchCheck.deviceRefused(reason: "Unable to lookup in current state: Shutdown").line(attempts: 2, bootedAgo: 41, loadAverage: 990)
            == "simctl could not launch the app on the device either (Unable to lookup in current state: Shutdown): the device, not the app — walk again once it settles, or reboot it\(context)")
        #expect(SimctlLaunchCheck.unanswered(seconds: 60).line(attempts: 2, bootedAgo: 41, loadAverage: 990)
            == "simctl did not launch the app within 60 s either: the device itself is not answering — walk again once it settles, or reboot it\(context)")
    }

    @Test
    func theContextListsWhicheverFiguresAreKnownAndFormatsThem() {
        let launched = SimctlLaunchCheck.launched(pid: 1)
        let tail = "walk again once it settles"

        #expect(launched.line(attempts: 2, bootedAgo: nil, loadAverage: nil).hasSuffix(tail))
        #expect(launched.line(attempts: 2, bootedAgo: 41, loadAverage: nil).hasSuffix("\(tail) (booted 41 s ago)"))
        #expect(launched.line(attempts: 2, bootedAgo: nil, loadAverage: 7.14).hasSuffix("\(tail) (host load average 7.1)"))
        #expect(launched.line(attempts: 2, bootedAgo: 720, loadAverage: 12.6).hasSuffix("(booted 12 min ago; host load average 13)"))
        #expect(launched.line(attempts: 2, bootedAgo: 3 * 3600 + 5, loadAverage: nil).hasSuffix("(booted 3 h ago)"))
        #expect(launched.line(attempts: 2, bootedAgo: 119, loadAverage: nil).hasSuffix("(booted 119 s ago)"))
    }

    @Test
    func theHostLoadAverageIsKnownOnThisMachine() {
        #expect(SimctlLaunchCheck.hostLoadAverage != nil)
    }
}

extension SimctlLaunchCheckTests {
    final class Calls {
        var all: [Call] = []
    }
}

extension SimctlLaunchCheckTests.Calls {
    struct Call {
        let arguments: [String]
        let environment: [String: String]
        let timeout: TimeInterval?
    }
}
