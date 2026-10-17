//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// SimWalk#136: on a machine whose `simctl` would first run `xcodebuild -runFirstLaunch`, `walk`, a dry run, `inspect` and `session start` refuse with the preflight's one line before any `simctl` call — on every path, `--device`'s route check included.
///
/// Every child is scripted: `xcrun --find simctl` names a stub script expecting a newer CoreSimulator than the stub `Info.plist` the check is pointed at, and any other call is recorded and fails.
struct FirstLaunchPreflightWiringTests {
    /// `walk`, with and without a `--device` whose route check lists the simulators.
    @Test(arguments: [[], ["--device", "iPhone 17"]])
    func aWalkIsRefusedBeforeAnySimctlCall(device: [String]) throws {
        let machine = try Machine()
        let command = try WalkCommand.parse([machine.walkbook(), "--output", machine.output] + device)

        let refusal = #expect(throws: XcodeFirstLaunchError.self) {
            try command.walked(shell: machine.shell, runner: { Machine.runner }, builds: machine.builds, leases: machine.leases, firstLaunch: machine.check)
        }

        machine.expectRefusedFirst(refusal)
    }

    /// `walk --dry-run` with no `--device`: its preparation is a walk's, so taken through the dry run itself, where the runner can be named.
    @Test
    func aDryRunIsRefusedBeforeAnySimctlCall() throws {
        let machine = try Machine()
        let command = try WalkCommand.parse([machine.walkbook(), "--output", machine.probeReport, "--dry-run"])

        let refusal = #expect(throws: XcodeFirstLaunchError.self) {
            try WalkDryRun.perform(command, shell: machine.shell, runner: { Machine.runner }, logFileURL: machine.logFile, builds: machine.builds, leases: machine.leases, firstLaunch: machine.check)
        }

        machine.expectRefusedFirst(refusal)
    }

    /// `walk --dry-run --device`, whose route check lists the simulators before anything else.
    @Test
    func aDryRunOnADeviceIsRefusedBeforeTheRouteCheck() throws {
        let machine = try Machine()
        let command = try WalkCommand.parse([machine.walkbook(), "--output", machine.probeReport, "--dry-run", "--device", "iPhone 17"])

        let refusal = #expect(throws: XcodeFirstLaunchError.self) {
            try command.probed(shell: machine.shell, builds: machine.builds, leases: machine.leases, firstLaunch: machine.check)
        }

        machine.expectRefusedFirst(refusal)
    }

    /// `inspect`.
    @Test
    func anInspectIsRefusedBeforeAnySimctlCall() throws {
        let machine = try Machine()
        let command = try InspectCommand.parse(["--app", "com.example.probe"])

        let refusal = #expect(throws: XcodeFirstLaunchError.self) {
            try command.perform(
                shell: machine.shell,
                runner: { Machine.runner },
                logFileURL: machine.logFile,
                builds: machine.builds,
                leases: machine.leases,
                scratch: machine.directory.url,
                firstLaunch: machine.check
            )
        }

        machine.expectRefusedFirst(refusal)
    }

    /// `session start`, under a `--lease` (no route check) and on a `--device` whose route check lists the simulators.
    @Test(arguments: [["--lease", "token-1"], ["--device", "iPhone 17"]])
    func aSessionStartIsRefusedBeforeAnySimctlCall(target: [String]) throws {
        let machine = try Machine()
        let command = try SessionStartCommand.parse(["--app", "com.example.probe"] + target)

        let refusal = #expect(throws: XcodeFirstLaunchError.self) {
            try command.perform(
                shell: machine.shell,
                pause: { _ in },
                runner: { Machine.runner },
                logFileURL: machine.logFile,
                builds: machine.builds,
                leases: machine.leases,
                store: LiveSessionStore(directory: machine.directory.url.appendingPathComponent("sessions", isDirectory: true)),
                processes: FakeSessionProcesses(),
                environment: [:],
                firstLaunch: machine.check
            )
        }

        machine.expectRefusedFirst(refusal)
    }
}

extension FirstLaunchPreflightWiringTests {
    /// A machine where first launch is pending: the scripted shell's record of every call, and the check pointed at the stub CoreSimulator.
    final class Machine {
        static let runner = RunnerSource(projectPath: "/runner/SimWalkRunner.xcodeproj", commit: "c0ffee", origin: .installed)

        let directory: TemporaryDirectory
        let check: XcodeFirstLaunch.Check
        private(set) var calls: [[String]] = []

        init() throws {
            directory = try TemporaryDirectory()
            try Data("#!/bin/sh\nEXPECTED_VERSION=\"1051.9\"\nexec simctl \"$@\"\n".utf8).write(to: directory.url.appendingPathComponent("simctl"))
            let info = directory.url.appendingPathComponent("Info.plist")
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleVersion": "1051.1"], format: .xml, options: 0).write(to: info)
            check = XcodeFirstLaunch.Check(xcrun: "/stub/xcrun", coreSimulatorInfo: info)
        }

        private var simctl: URL {
            directory.url.appendingPathComponent("simctl")
        }

        var shell: Shell {
            Shell(timedScript: { [self] _, arguments, _, _ in
                calls.append(arguments)
                guard arguments == ["--find", "simctl"] else {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "not on this machine\n")
                }
                return Shell.Result(status: 0, standardOutput: "\(simctl.path)\n", standardError: "")
            })
        }

        var builds: RunnerBuilds {
            RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        }

        var leases: LeaseStore {
            LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
        }

        var logFile: URL {
            directory.url.appendingPathComponent("usage.jsonl")
        }

        var output: String {
            directory.url.appendingPathComponent("out.simwalk").path
        }

        var probeReport: String {
            directory.url.appendingPathComponent("probe.json").path
        }

        /// A one-screen walkbook on disk, returning its path.
        func walkbook() throws -> String {
            let url = directory.url.appendingPathComponent("book.json")
            let json = #"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
            try Data(json.utf8).write(to: url)
            return url.path
        }

        /// The refusal is the preflight's one line, and the only call made before it was the preflight's own `xcrun --find simctl`.
        func expectRefusedFirst(_ refusal: XcodeFirstLaunchError?, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(refusal == .pending(installed: "1051.1", expected: "1051.9"), sourceLocation: sourceLocation)
            let text = refusal.map { String(describing: $0) } ?? ""
            #expect(text.hasPrefix("this Xcode's simctl expects CoreSimulator 1051.9 and 1051.1 is installed"), sourceLocation: sourceLocation)
            #expect(!text.contains("\n"), sourceLocation: sourceLocation)
            #expect(calls == [["--find", "simctl"]], sourceLocation: sourceLocation)
        }
    }
}
