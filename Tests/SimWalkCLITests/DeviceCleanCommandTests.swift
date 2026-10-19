//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

struct DeviceCleanCommandTests {
    static var udid: String {
        "00008160-00000000000000AA"
    }

    private func store() throws -> (LeaseStore, TemporaryDirectory) {
        let directory = try TemporaryDirectory()
        return (LeaseStore(directory: directory.url.appendingPathComponent("leases"), isAlive: { _ in true }), directory)
    }

    @Test
    func theRunnerIsUninstalledUnderTheCommandsLeaseAndTheAnswerNamesIt() throws {
        let (leases, keep) = try store()
        _ = keep
        let recorder = Recorder(installed: true)
        let command = try DeviceCleanCommand.parse(["--udid", Self.udid, "--runner-bundle-id", "com.team.runner"])

        let answer = try command.answer(shell: recorder.shell, leases: leases, holderPID: 4242, now: Date())

        #expect(recorder.calls.last == ["devicectl", "device", "uninstall", "app", "--device", Self.udid, "com.team.runner.xctrunner"])
        #expect(answer.verdict == .unqualified("removed com.team.runner.xctrunner"))
        #expect(leases.all().isEmpty)
    }

    @Test
    func aRunnerThatIsNotInstalledIsAnAnswerAndNothingIsUninstalled() throws {
        let (leases, keep) = try store()
        _ = keep
        let recorder = Recorder(installed: false)

        let answer = try DeviceCleanCommand.parse(["--udid", Self.udid]).answer(shell: recorder.shell, leases: leases, holderPID: 4242, now: Date())

        #expect(answer.verdict == .unqualified("com.agulhaslabs.simwalk.runner.xctrunner is not installed"))
        #expect(!recorder.calls.contains { $0.starts(with: ["devicectl", "device", "uninstall"]) })
    }

    @Test
    func aPhoneAnotherLivePidHoldsIsRefusedWithNothingRun() throws {
        let (leases, keep) = try store()
        _ = keep
        _ = try leases.acquire(udid: Self.udid, ttl: 600, holderPID: 777, now: Date(), physicalDevice: true)
        let recorder = Recorder(installed: true)

        #expect(throws: LeaseError.self) {
            try DeviceCleanCommand.parse(["--udid", Self.udid]).answer(shell: recorder.shell, leases: leases, holderPID: 4242, now: Date())
        }

        #expect(recorder.calls.isEmpty)
    }

    @Test
    func aFailedUninstallIsRefusedNamingDevicectlsError() throws {
        let (leases, keep) = try store()
        _ = keep
        let recorder = Recorder(installed: true, uninstallStatus: 1)

        let thrown = try #require(#expect(throws: RunnerAppUninstall.Failure.self) {
            try DeviceCleanCommand.parse(["--udid", Self.udid]).answer(shell: recorder.shell, leases: leases, holderPID: 4242, now: Date())
        })

        #expect(thrown.description.contains("not allowed"))
    }

    @Test
    func udidWithLeaseAndNeitherAreValidationErrors() {
        #expect(throws: (any Error).self) { try DeviceCleanCommand.parse(["--udid", Self.udid, "--lease", "t"]) }
        #expect(throws: (any Error).self) { try DeviceCleanCommand.parse([]) }
    }
}

extension DeviceCleanCommandTests {
    final class Recorder: @unchecked Sendable {
        var calls: [[String]] = []
        let installed: Bool
        let uninstallStatus: Int32

        init(installed: Bool, uninstallStatus: Int32 = 0) {
            self.installed = installed
            self.uninstallStatus = uninstallStatus
        }

        var shell: Shell {
            Shell(script: { _, arguments, _ in
                self.calls.append(arguments)
                if arguments.starts(with: ["devicectl", "device", "info", "apps"]) {
                    let apps = self.installed ? #"{"bundleIdentifier":"x"}"# : ""
                    return Shell.Result(status: 0, standardOutput: #"{"result":{"apps":[\#(apps)]}}"#, standardError: "")
                }
                if arguments.starts(with: ["devicectl", "device", "uninstall", "app"]), self.uninstallStatus != 0 {
                    return Shell.Result(status: self.uninstallStatus, standardOutput: "", standardError: "not allowed")
                }
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            })
        }
    }
}
