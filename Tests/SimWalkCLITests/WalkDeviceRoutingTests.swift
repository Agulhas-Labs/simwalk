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

/// `walk --device <physical udid>` (SimWalk#116 next step 4): which target a walk takes, what it refuses before touching either, and that the device path is `device walk`'s.
struct WalkDeviceRoutingTests {
    typealias Fixture = DeviceWalkCommandTests.Fixture

    static var udid: String {
        DeviceWalkCommandTests.udid
    }

    static var twoScreens: String {
        #"{"name":"w","appBundleID":"x.y","screens":[{"id":"today","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]},{"id":"other","route":[{"tab":{"label":"Other"}}],"states":[{"theme":"light"}]}]}"#
    }

    private func machine(keep: TemporaryDirectory) -> Machine {
        Machine(phone: DeviceWalkCommandTests().phone(appearances: [DeviceWalkCommandTests.appearance("light")], keep: keep))
    }

    private func command(_ fixture: Fixture, _ arguments: [String]) throws -> WalkCommand {
        try WalkCommand.parse([fixture.walkbookPath, "--output", fixture.output] + arguments)
    }

    @Test
    func aPhysicalUDIDTakesTheDevicePathInTheDeviceWalksOrderWithNoSimulatorBootOrInstall() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        let answer = try command(fixture, ["--device", Self.udid, "--team", "TEAM"]).walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)

        // The preflight asks where `simctl` is first (SimWalk#136); the routing read is the first `list`; the rest is `device walk`'s own order, unchanged.
        #expect(machine.phone.summary == ["find simctl", "list", "list", "lockState", "appearance", "xcodebuild build-for-testing", "xcodebuild test-without-building", "copy", "wipe", "appearance"])
        #expect(machine.simctl == [["simctl", "list", "devices", "available", "--json"]])
        #expect(answer.verdict == .unqualified("1 of 1 screens captured · 1 capture"))
    }

    @Test
    func aSimulatorUDIDStaysOnTheSimulatorPathAndReadsNoPhone() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        let target = try command(fixture, ["--device", "SIM-1"]).target(shell: machine.shell, leases: fixture.leases)

        guard case .simulator = target else {
            Issue.record("expected the simulator path, got \(target)")
            return
        }

        // The preflight's `--find simctl` (SimWalk#136) is the one call that is not `simctl list`, and no phone is read.
        #expect(machine.phone.calls.allSatisfy { $0.arguments == ["--find", "simctl"] })
    }

    @Test
    func aLeaseOnAPhysicalDeviceRoutesToTheDevicePathWithoutReadingAnything() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)
        let lease = try fixture.leases.acquire(udid: Self.udid, ttl: 600, holderPID: 1, now: Date(), physicalDevice: true)

        let target = try command(fixture, ["--lease", lease.token, "--team", "TEAM"]).target(shell: machine.shell, leases: fixture.leases)

        guard case let .device(walk) = target else {
            Issue.record("expected the device path, got \(target)")
            return
        }

        #expect(walk.lease == lease.token)
        #expect(machine.phone.calls.isEmpty && machine.simctl.isEmpty)
    }

    @Test(arguments: [["--team", "TEAM"], ["--runner-bundle-id", "com.team.runner"]])
    func aDeviceOnlyFlagOnASimulatorWalkIsRefusedBeforeAnythingRuns(_ flag: [String]) throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) {
            try command(fixture, ["--device", "SIM-1"] + flag).walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)
        })

        #expect(thrown.description.hasPrefix(flag[0]))
        #expect(machine.simctl.allSatisfy { $0.starts(with: ["simctl", "list"]) })
        #expect(machine.phone.calls.allSatisfy { $0.arguments == ["--find", "simctl"] })
    }

    @Test
    func aDryRunOnADeviceIsRefused() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) {
            try command(fixture, ["--device", Self.udid, "--team", "TEAM", "--dry-run"]).target(shell: machine.shell, leases: fixture.leases)
        })

        #expect(thrown.description.contains("--dry-run"))
        #expect(machine.phone.calls.allSatisfy { $0.arguments == ["--find", "simctl"] || $0.arguments.starts(with: ["devicectl", "list"]) })
    }

    /// The real entries: the CLI's `runDryRun` around `probed` (what `run()` composes) and the MCP face's `answer()`.
    @Test
    func aDryRunOnADeviceIsRefusedAtTheCLIAndMCPEntries() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)
        let recorder = StreamRecorder()
        let arguments = ["--device", Self.udid, "--team", "TEAM", "--dry-run"]

        let exit = try #require(#expect(throws: ExitCode.self) {
            try command(fixture, arguments).runDryRun(log: Self.log(in: fixture), emit: recorder.emit, emitError: recorder.emitError) {
                try command(fixture, arguments).probed(shell: machine.shell, builds: fixture.builds, leases: fixture.leases)
            }
        })
        let mcp = try #require(#expect(throws: DeviceWalkRefusal.self) {
            try command(fixture, arguments).answer(environment: Self.environment(fixture), shell: machine.shell, builds: fixture.builds, leases: fixture.leases)
        })

        #expect(exit == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.contains(DeviceWalkRefusal.dryRunOnDevice.description) == true)
        #expect(mcp.description == DeviceWalkRefusal.dryRunOnDevice.description)
        #expect(mcp.usageFailureKind == .inputRefused)
        #expect(machine.phone.calls.allSatisfy { $0.arguments == ["--find", "simctl"] || $0.arguments.starts(with: ["devicectl", "list"]) })
    }

    /// The same entries for `--verbose`: `runServing` around `walked` (what `run()` composes) and `answer()`.
    @Test
    func aVerboseWalkOnADeviceIsRefusedAtTheCLIAndMCPEntries() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)
        let recorder = StreamRecorder()
        let arguments = ["--device", Self.udid, "--team", "TEAM", "--verbose"]

        let exit = try #require(#expect(throws: ExitCode.self) {
            try command(fixture, arguments).runServing(log: Self.log(in: fixture), emit: recorder.emit, emitError: recorder.emitError) {
                try command(fixture, arguments).walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)
            }
        })
        let mcp = try #require(#expect(throws: DeviceWalkRefusal.self) {
            try command(fixture, arguments).answer(environment: Self.environment(fixture), shell: machine.shell, builds: fixture.builds, leases: fixture.leases)
        })

        #expect(exit == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.contains(DeviceWalkRefusal.verboseOnDevice.description) == true)
        #expect(mcp.description == DeviceWalkRefusal.verboseOnDevice.description)
        #expect(mcp.usageFailureKind == .inputRefused)
        #expect(machine.phone.calls.allSatisfy { $0.arguments == ["--find", "simctl"] || $0.arguments.starts(with: ["devicectl", "list"]) })
    }

    @Test
    func theAliasEndsARefusalWithTheAliasLineAndWalkDeviceDoesNot() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)
        let aliasStreams = StreamRecorder()
        let walk = StreamRecorder()

        _ = try #require(#expect(throws: ExitCode.self) {
            let alias = try fixture.command(["--udid", "NO-SUCH"])
            try alias.run(log: Self.log(in: fixture), emit: aliasStreams.emit, emitError: aliasStreams.emitError) {
                try alias.aliasAnswer(shell: machine.shell, builds: fixture.builds, resolveRunner: fixture.source(), leases: fixture.leases, holderPID: fixture.holderPID, now: Date())
            }
        })
        _ = try #require(#expect(throws: ExitCode.self) {
            try command(fixture, ["--device", "NO-SUCH", "--team", "TEAM"]).runServing(log: Self.log(in: fixture), emit: walk.emit, emitError: walk.emitError) {
                try command(fixture, ["--device", "NO-SUCH", "--team", "TEAM"]).walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)
            }
        })

        #expect(aliasStreams.err.first?.hasSuffix("\n" + DeviceWalkCommand.aliasLine) == true)
        #expect(walk.err.first?.contains("no simulator or physical device 'NO-SUCH'") == true)
        #expect(walk.err.allSatisfy { !$0.contains(DeviceWalkCommand.aliasLine) })
    }

    /// The same refusal reached by both verbs (a locked phone) differs only by the closing line: the alias is `walk --device`'s refusal plus ``DeviceWalkCommand/aliasLine``, not a second wording (SimWalk#127).
    @Test
    func theAliasRefusalMinusItsClosingLineIsTheWalkDeviceRefusal() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)
        machine.phone.locked = true
        let aliasStreams = StreamRecorder()
        let walk = StreamRecorder()

        _ = try #require(#expect(throws: ExitCode.self) {
            let alias = try fixture.command(["--udid", Self.udid])
            try alias.run(log: Self.log(in: fixture), emit: aliasStreams.emit, emitError: aliasStreams.emitError) {
                try alias.aliasAnswer(shell: machine.shell, builds: fixture.builds, resolveRunner: fixture.source(), leases: fixture.leases, holderPID: fixture.holderPID, now: Date())
            }
        })
        _ = try #require(#expect(throws: ExitCode.self) {
            try command(fixture, ["--device", Self.udid, "--team", "TEAM"]).runServing(log: Self.log(in: fixture), emit: walk.emit, emitError: walk.emitError) {
                try command(fixture, ["--device", Self.udid, "--team", "TEAM"]).walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)
            }
        })

        let aliasRefusal = try #require(aliasStreams.err.first)
        let walkRefusal = try #require(walk.err.first)

        #expect(walkRefusal.contains("unlock"))
        #expect(aliasRefusal.hasSuffix("\n" + DeviceWalkCommand.aliasLine))
        #expect(String(aliasRefusal.dropLast(DeviceWalkCommand.aliasLine.count + 1)) == walkRefusal.trimmingCharacters(in: .newlines))
    }

    @Test
    func validateDeviceLeavesTheDeviceOnlyNoteOutAndAPlainValidateKeepsIt() throws {
        let fixture = try Fixture(walkbook: #"{"name":"w","appBundleID":"x.y","screens":[{"id":"today","measure":true,"route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#)

        let plain = try ValidateCommand.parse([fixture.walkbookPath]).answer()
        let onDevice = try ValidateCommand.parse(["--device", fixture.walkbookPath]).answer()

        #expect(plain.text.contains("measure: device only, not run (today)"))
        #expect(!onDevice.text.contains("measure:"))
    }

    private static func log(in fixture: Fixture) -> UsageLog {
        UsageLog(directory: fixture.directory.url, now: { Date() })
    }

    private static func environment(_ fixture: Fixture) -> [String: String] {
        ["SIMWALK_USAGE_LOG": fixture.directory.url.appendingPathComponent("usage.jsonl").path]
    }

    @Test
    func aUDIDKnownToNeitherIsRefusedNamingThePhysicalUDIDsPresent() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) {
            try command(fixture, ["--device", "NO-SUCH"]).target(shell: machine.shell, leases: fixture.leases)
        })

        #expect(thrown.description.contains("physical devices present: \(Self.udid)"))
        #expect(thrown.description.contains("iPhone 17 Pro"))
    }

    @Test
    func settleMotionAndScreensReachTheDeviceRunner() throws {
        let fixture = try Fixture(walkbook: Self.twoScreens)
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        _ = try command(fixture, ["--device", Self.udid, "--team", "TEAM", "--settle", "900", "--motion", "--screens", "today"]).walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)

        let walk = try #require(machine.phone.calls.first { $0.arguments.contains("test-without-building") })
        #expect(walk.environment["TEST_RUNNER_SIMWALK_SETTLE_MS"] == "900")
        #expect(walk.environment[MotionOptIn.hostEnvironmentKey] == MotionOptIn.walkWideValue)
        let json = try #require(walk.environment["TEST_RUNNER_SIMWALK_WALKBOOK_JSON"])
        let sent = try JSONDecoder().decode(Walkbook.self, from: Data(json.utf8))
        #expect(sent.screens.map(\.id) == ["today"])
    }

    @Test
    func noSettleMotionOrScreensLeavesTheDeviceRunnerAsItWas() throws {
        let fixture = try Fixture(walkbook: Self.twoScreens)
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        _ = try command(fixture, ["--device", Self.udid, "--team", "TEAM"]).walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)

        let walk = try #require(machine.phone.calls.first { $0.arguments.contains("test-without-building") })

        #expect(walk.environment["TEST_RUNNER_SIMWALK_SETTLE_MS"] == nil)
        #expect(walk.environment[MotionOptIn.hostEnvironmentKey] == nil)
        #expect(walk.environment["TEST_RUNNER_SIMWALK_WALKBOOK_JSON"] == Self.twoScreens)
    }

    @Test
    func theDeviceWalkAliasEndsItsAnswerSayingItIsWalkDeviceNow() throws {
        let fixture = try Fixture()
        let keep = try TemporaryDirectory()
        let machine = machine(keep: keep)

        let answer = try fixture.command().aliasAnswer(shell: machine.phone.shell, builds: fixture.builds, resolveRunner: fixture.source(), leases: fixture.leases, holderPID: fixture.holderPID, now: Date())

        #expect(answer.residue.last == "device walk is walk --device now")
    }

    @Test
    func validateDeviceListsWhatADeviceWalkRefuses() throws {
        let fixture = try Fixture(walkbook: #"{"name":"w","appBundleID":"x.y","setup":{"increaseContrast":true,"statusBar":"clean"},"screens":[{"id":"a","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light","locale":"en_GB"}]}]}"#)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: fixture.walkbookPath))

        let plain = try ValidateCommand.parse([fixture.walkbookPath]).answer()
        let thrown = try #require(#expect(throws: WalkbookLoadError.self) { try ValidateCommand.parse(["--device", fixture.walkbookPath]).answer() })

        #expect(plain.verdict == .unqualified("1 capture planned"))
        for line in DeviceTargetSupport.unsupported(in: book) {
            #expect(thrown.description.contains(line))
        }
        #expect(thrown.description.contains("2 problems"))
    }
}

extension WalkDeviceRoutingTests {
    /// Answers `simctl list` with one simulator and everything else as the scripted phone does; `simctl` calls are kept apart from the phone's.
    final class Machine {
        let phone: DeviceWalkCommandTests.Phone
        private(set) var simctl: [[String]] = []

        init(phone: DeviceWalkCommandTests.Phone) {
            self.phone = phone
        }

        var shell: Shell {
            let inner = phone.shell
            return Shell(script: { executable, arguments, environment in
                guard arguments.first == "simctl" else {
                    return try inner.run(executable, arguments, environment: environment)
                }
                self.simctl.append(arguments)
                let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"SIM-1","name":"iPhone 17 Pro","state":"Shutdown"}]}}"#
                return Shell.Result(status: 0, standardOutput: devices, standardError: "")
            })
        }
    }

    /// `setup.increaseContrast` is the one setup key a device can apply (SimWalk#116, ruling 6), so `validate --device` lets it through.
    @Test
    func validateDeviceAcceptsIncreaseContrast() throws {
        let fixture = try Fixture(walkbook: DeviceWalkCommandTests.contrastWalkbook)

        let answer = try ValidateCommand.parse(["--device", fixture.walkbookPath]).answer()

        #expect(answer.verdict == .unqualified("1 capture planned"))
    }
}
