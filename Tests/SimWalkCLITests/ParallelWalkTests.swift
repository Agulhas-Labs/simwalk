//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimulatorServices
@testable import SimWalkCLI
@testable import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `walk --parallel N` on a scripted machine: what it refuses, the one bundle it merges, and the stop and the release that end every shard and give back every device it took, whichever way the walk ends.
struct ParallelWalkTests {
    @Test
    func aParallelCountBelowOneIsRefusedAtTheCommandLine() throws {
        let thrown = try #require(#expect(throws: Error.self) {
            try WalkCommand.parse(["book.json", "--output", "out.simwalk", "--parallel", "0"])
        })

        #expect(WalkCommand.message(for: thrown).contains("--parallel takes a device count of at least 1"))
    }

    @Test
    func aParallelDryRunIsRefusedAtTheCommandLine() throws {
        let thrown = try #require(#expect(throws: Error.self) {
            try WalkCommand.parse(["book.json", "--output", "out.simwalk", "--parallel", "2", "--dry-run"])
        })

        #expect(WalkCommand.message(for: thrown).contains("--parallel shards a walk's captures, and a dry run captures nothing"))
    }

    @Test
    func aParallelWalkOnAPhysicalDeviceIsRefusedBeforeAnythingRuns() throws {
        let fixture = try DeviceWalkCommandTests.Fixture()
        let keep = try TemporaryDirectory()
        let machine = WalkDeviceRoutingTests.Machine(phone: DeviceWalkCommandTests().phone(appearances: [DeviceWalkCommandTests.appearance("light")], keep: keep))
        let command = try WalkCommand.parse([fixture.walkbookPath, "--output", fixture.output, "--device", WalkDeviceRoutingTests.udid, "--team", "TEAM", "--parallel", "2"])

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) {
            try command.walked(shell: machine.shell, runner: fixture.source(), builds: fixture.builds, leases: fixture.leases)
        })

        #expect(thrown.description == DeviceWalkRefusal.parallelOnDevice.description)
        #expect(!machine.phone.calls.contains { $0.arguments.contains("build-for-testing") })
        #expect(machine.simctl.allSatisfy { $0.starts(with: ["simctl", "list"]) })
    }

    /// Two screens on two devices: shard 0 walks `progress` on the walk's own device, a clone of it walks `browse`, and the answer is one bundle in walkbook order that names the device each screen was captured on.
    ///
    /// The clone is deleted and every lease released, and its override is removed from the walk's own override root rather than the machine's.
    @Test
    func aTwoShardWalkMergesOneBundleInWalkbookOrderAndDeletesTheClone() throws {
        let machine = try Machine()
        try DisabledServicesOverride(root: machine.overrideRoot).write(["com.example.gizmod"], for: ParallelScript.clone)

        let outcome = try machine.walk(machine.command())

        #expect(outcome.bundle.manifest.screens.map(\.id) == ["progress", "browse"])
        #expect(outcome.bundle.manifest.screens.map(\.capturedOn?.udid) == ["UDID-1", ParallelScript.clone])
        #expect(outcome.parallelLines.first == "parallel: 2 devices — iPhone 17 Pro UDID-1 (progress), iPhone 17 Pro (SimWalk lease) C1013E00 (browse); 1 created, deleted")
        #expect(outcome.servedAnswer().residue.contains(outcome.parallelLines[0]))
        #expect(machine.script.ran(["simctl", "delete", ParallelScript.clone]))
        #expect(machine.leases.all().isEmpty)
        #expect(try !FileManager.default.fileExists(atPath: DisabledServicesOverride(root: machine.overrideRoot).directory(for: ParallelScript.clone).path))
    }

    /// The clone's runner exits 65: the walk stops shard 0's runner rather than waiting it out, refuses naming the clone and its screens, and still deletes the clone and releases every lease.
    @Test
    func aFailedShardStopsTheOtherAndTheRefusalNamesItsDeviceAndScreens() throws {
        let machine = try Machine(mode: .cloneFails)

        let refusal = try #require(#expect(throws: ParallelWalkRefusal.self) {
            try machine.walk(machine.command())
        })

        #expect(machine.script.stoppedRunners == ["UDID-1"])
        #expect(refusal.device == "iPhone 17 Pro (SimWalk lease) C1013E00")
        #expect(refusal.screens == ["browse"])
        #expect(refusal.others.first == "stopped: iPhone 17 Pro UDID-1 (progress)")
        #expect(!refusal.interrupted)
        #expect(machine.script.terminatedRunnerBeforeHandback(of: "UDID-1"))
        #expect(machine.script.ran(["simctl", "delete", ParallelScript.clone]))
        #expect(machine.leases.all().isEmpty)
    }

    /// A SIGTERM or Ctrl-C (the run's `interruption`) during the clone's runner stops every runner and deletes the clone before the cancel returns, so the signal can end the process with nothing left behind.
    @Test
    func anInterruptionStopsEveryShardAndDeletesTheCloneBeforeTheSignalEndsTheProcess() throws {
        let interruption = Cancellation()
        let machine = try Machine(mode: .cancelDuringClone(interruption, stopped: true))

        let refusal = try #require(#expect(throws: ParallelWalkRefusal.self) {
            try machine.walk(machine.command(), interruption: interruption)
        })

        #expect(machine.script.deletedAtCancel == true)
        #expect(machine.script.stoppedRunners.contains("UDID-1"))
        #expect([["progress"], ["browse"]].contains(refusal.screens))
        #expect(refusal.others.filter { $0.hasPrefix("stopped: ") }.count == 1)
        #expect(refusal.interrupted)
        #expect(refusal.description.hasPrefix("the walk was interrupted, so every shard was stopped\n"))
        #expect(machine.leases.all().isEmpty)
    }

    /// A walk that fails before its shards run — here, the runner build on shard 0, after the clone was made — still deletes the clone and releases every lease: the release in `performWalk`'s defer is what gives it back.
    @Test
    func aWalkThatFailsBeforeItsShardsRunStillDeletesTheClone() throws {
        let machine = try Machine(mode: .buildFails)

        #expect(throws: (any Error).self) {
            try machine.walk(machine.command())
        }

        #expect(machine.script.ran(["simctl", "clone", "UDID-1", "iPhone 17 Pro (SimWalk lease)"]))
        #expect(machine.script.ran(["simctl", "delete", ParallelScript.clone]))
        #expect(machine.leases.all().isEmpty)
    }

    /// The walk's stop can end shard 0's appearance-retry runner, not only its first: the retry's runner app is ended before the handback puts the appearance back, or it would flip it again, and the shard is not called finished.
    @Test
    func aStopThatEndsTheAppearanceRetryRunnerTerminatesItsAppBeforeTheHandback() throws {
        let machine = try Machine(mode: .cloneFailsDuringRetry, firstShardRefusedOnAppearance: true)

        let refusal = try #require(#expect(throws: ParallelWalkRefusal.self) {
            try machine.walk(machine.command())
        })

        #expect(machine.script.stoppedRunners == ["UDID-1"])
        #expect(machine.script.terminatedRetryRunnerBeforeHandback(of: "UDID-1"))
        #expect(refusal.others.first == "stopped: iPhone 17 Pro UDID-1 (progress)")
    }

    /// An existing extra found booted is not the walk's to reboot, as a serial walk judges a device it found booted: its screen refused on appearance is not settled — the device is never shut down or rebooted — and the answer gives the command instead.
    @Test
    func anExistingExtraFoundBootedIsNeverRebootedByTheAppearanceRetry() throws {
        let machine = try Machine(bootedExtra: true)

        let outcome = try machine.walk(machine.command())

        #expect(outcome.otherDeviceLabels == ["iPhone 17 Pro UDID-2"])
        let retry = try #require(outcome.otherDevices.first?.appearanceRetry)
        guard case let .notSettled(screens, _) = retry else {
            Issue.record("the extra's retry was \(retry), not a settle declined")
            return
        }
        #expect(screens == ["browse"])
        #expect(!machine.script.calls.contains { $0.starts(with: ["simctl", "shutdown", "UDID-2"]) })
    }

    /// A walkbook whose setup changes the device takes no extra the walk would not own: the booted existing device is passed over — never leased, booted, set up or handed back — and shard 0 is cloned instead, where a serial walk on such a device would be refused.
    @Test
    func aSetupThatChangesTheDeviceTakesNoExtraTheWalkDoesNotOwn() throws {
        let machine = try Machine(bootedExtra: true, setup: true)

        let outcome = try machine.walk(machine.command())

        #expect(outcome.otherDeviceLabels == ["iPhone 17 Pro (SimWalk lease) C1013E00"])
        #expect(!machine.script.calls.contains { $0.contains("UDID-2") && !$0.starts(with: ["simctl", "list"]) })
        #expect(machine.leases.all().isEmpty)
    }

    /// A walk that fails before its shards run, whose clone then cannot be deleted, names the clone in its refusal rather than leaving it unsaid.
    @Test
    func aCloneThatCannotBeDeletedAfterAFailureBeforeTheShardsIsNamedInTheRefusal() throws {
        let machine = try Machine(mode: .buildFails, deleteFails: true)

        let failure = try #require(#expect(throws: ParallelWalkFailure.self) {
            try machine.walk(machine.command())
        })

        #expect(failure.unreleased.map(\.udid) == [ParallelScript.clone])
        #expect(failure.description.contains("⚠ not given back: \(ParallelScript.clone)"))
        #expect(String(describing: failure.underlying).contains("BUILD FAILED"))
    }

    /// More devices than screens is clamped: one screen walks serially, clones nothing, and the answer says what was asked for.
    @Test
    func aParallelCountAboveTheScreenCountIsClampedAndWalksSerially() throws {
        let machine = try Machine(screens: ["progress"])

        let outcome = try machine.walk(machine.command(parallel: 3))

        #expect(outcome.parallelLines == ["parallel: 1 device (asked for 3; the plan has 1 screen)"])
        #expect(outcome.servedAnswer().residue.contains(outcome.parallelLines[0]))
        #expect(!machine.script.calls.contains { $0.starts(with: ["simctl", "clone"]) })
        #expect(outcome.bundle.manifest.screens.map(\.id) == ["progress"])
    }

    /// The MCP face hands the walk no interruption: a client's cancel ends the progress file, the walk carries on to its one merged bundle, and the clone is deleted at the walk's end rather than at the cancel.
    @Test
    func anMCPCancelNeverReleasesThePoolAndTheWalkCarriesOn() throws {
        let cancellation = Cancellation()
        let machine = try Machine(mode: .cancelDuringClone(cancellation, stopped: false))
        let overrideRoot = machine.overrideRoot

        let answer = try machine.command().answer(
            environment: ["SIMWALK_USAGE_LOG": machine.directory.url.appendingPathComponent("usage.jsonl").path, WalkCommand.sessionVariable: "parallel-mcp"],
            cancellation: cancellation,
            shell: Shell(script: machine.script.run),
            runner: { WalkCommandTests.runner },
            builds: WalkCommandTests.builds(in: machine.directory),
            leases: machine.leases,
            provisioning: { SlimWalkProvisioning(shell: $0, overrides: DisabledServicesOverride(root: overrideRoot)) }
        )

        #expect(machine.script.deletedAtCancel == false)
        #expect(machine.script.stoppedRunners.isEmpty)
        #expect(answer.residue.contains { $0.hasPrefix("parallel: 2 devices") })
        #expect(machine.script.ran(["simctl", "delete", ParallelScript.clone]))
        #expect(machine.leases.all().isEmpty)
    }
}

extension ParallelWalkTests {
    /// One test's scratch, removed with it: the walkbook, the app, a canned bundle per shard, the lease store, the override root and the script.
    struct Machine {
        let directory: TemporaryDirectory
        let staged: [TemporaryDirectory]
        let script: ParallelScript
        let walkbook: String
        let output: String
        let leases: LeaseStore
        let overrideRoot: URL

        /// `firstShardRefusedOnAppearance` makes `progress` come back with a state refused on appearance too, so shard 0 walks it again once the device is settled.
        ///
        /// `bootedExtra` lists `UDID-2`, booted and of `UDID-1`'s type and runtime, and — without `setup` — `browse` comes back with a state refused on appearance; `setup` gives the walkbook a setup that changes the device.
        init(mode: ParallelScript.Mode = .clean, screens: [String] = ["progress", "browse"], bootedExtra: Bool = false, setup: Bool = false, deleteFails: Bool = false, firstShardRefusedOnAppearance: Bool = false) throws {
            directory = try TemporaryDirectory()
            let url = directory.url.appendingPathComponent("book.json")
            let book = screens.map { #"{"id":"\#($0)","route":[{"tab":{"label":"\#($0)"}}],"states":[{"theme":"light"}]}"# }.joined(separator: ",")
            try Data((#"{"name":"probe","appBundleID":"com.example.probe","# + (setup ? WalkCommandTests.setupJSON : "") + #""screens":[\#(book)]}"#).utf8).write(to: url)
            walkbook = url.path
            output = directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)").path
            leases = WalkCommandTests.leases(in: directory)
            overrideRoot = directory.url.appendingPathComponent("override-root", isDirectory: true)
            var staged: [TemporaryDirectory] = []
            var bundles: [String: URL] = [:]
            for screen in screens {
                let stage = try TemporaryDirectory()
                staged.append(stage)
                let capture = CaptureBundleFixture.Capture(screenID: screen, state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen())
                let refused = (bootedExtra && !setup && screen == "browse") || (firstShardRefusedOnAppearance && screen == "progress") ? [Walkbook.CaptureState(theme: .dark)] : []
                let outcome: ScreenOutcome = refused.isEmpty ? .captured : .stateNotApplied(reason: "the appearance did not apply")
                let spec = CaptureBundleFixture.ScreenSpec(id: screen, outcome: outcome, captures: [capture], refusedStates: refused, refusedOnAppearance: refused)
                bundles[screen] = try CaptureBundleFixture.writeWalk(in: stage, screens: [spec], appBundleID: "com.example.probe").url
            }
            self.staged = staged
            script = try ParallelScript(appPath: WalkCommandTests.fakeApp(in: directory), bundles: bundles, mode: mode, bootedExtra: bootedExtra, deleteFails: deleteFails)
        }

        func command(parallel: Int = 2) throws -> WalkCommand {
            try WalkCommand.parse([walkbook, "--output", output, "--device", "UDID-1", "--parallel", "\(parallel)"])
        }

        /// The walk on the script, with the script's stop and the override root in scratch.
        func walk(_ command: WalkCommand, interruption: Cancellation? = nil) throws -> WalkCommand.Outcome {
            let overrideRoot = overrideRoot
            return try command.performWalk(
                shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { WalkCommandTests.runner },
                builds: WalkCommandTests.builds(in: directory), leases: leases,
                provisioning: { SlimWalkProvisioning(shell: $0, overrides: DisabledServicesOverride(root: overrideRoot)) },
                interruption: interruption, childStop: script.stop
            )
        }
    }

    /// Stands in for `simctl` and `xcodebuild` on two devices at once: `UDID-1`, shut down, and the clone `simctl clone` makes of it, each with its own boot, appearance and accessibility state, under one lock.
    ///
    /// The runner keys on `-destination id=` and copies the canned bundle of the screens its walkbook names to `TEST_RUNNER_SIMWALK_OUTPUT`, stamped with the build hash, nonce and device the driver passed — or, as `mode` says, fails, waits for the walk's stop, or cancels the walk.
    final class ParallelScript: @unchecked Sendable {
        /// The UDID `simctl clone` answers with: shaped like a real one, which the override directory keys on.
        static var clone: String {
            "C1013E00-0000-4000-8000-000000000001"
        }

        /// The stop the walk is handed, which a waiting runner watches.
        let stop = ChildStop()
        private let lock = NSLock()
        private let appPath: String
        private let bundles: [String: URL]
        private let mode: Mode
        private var recorded: [[String]] = []
        private var elapsed: TimeInterval = 0
        private var cloned = false
        private let bootedExtra: Bool
        private let deleteFails: Bool
        private var booted: Set<String> = []
        private var appearance: [String: String] = [:]
        private var accessibility: [String: String] = [:]
        private var started: Set<String> = []
        private var runs: [String: Int] = [:]
        private var stopped: [String] = []
        private var deleted: Bool?

        init(appPath: String, bundles: [String: URL], mode: Mode, bootedExtra: Bool = false, deleteFails: Bool = false) {
            self.deleteFails = deleteFails
            self.appPath = appPath
            self.bundles = bundles
            self.mode = mode
            self.bootedExtra = bootedExtra
            booted = bootedExtra ? ["UDID-2"] : []
        }

        /// Every call's arguments, in the order they were made.
        var calls: [[String]] {
            lock.withLock { recorded }
        }

        /// The devices whose runner the walk's stop ended while it ran.
        var stoppedRunners: [String] {
            lock.withLock { stopped }
        }

        /// Whether the clone had been deleted by the time the cancel returned; `nil` when nothing cancelled.
        var deletedAtCancel: Bool? {
            lock.withLock { deleted }
        }

        /// Whether a call with exactly these arguments was made.
        func ran(_ arguments: [String]) -> Bool {
            calls.contains(arguments)
        }

        /// Whether the runner app on `udid` was terminated after its runner was started and before the first other call that names the device, which is the handback's.
        func terminatedRunnerBeforeHandback(of udid: String) -> Bool {
            let calls = calls
            let terminate = ["simctl", "terminate", udid, RunnerInvocation.deviceContainerBundleID(runnerBundleID: nil)]
            guard let runner = calls.firstIndex(where: { $0.contains("test-without-building") && Self.destination($0) == udid }),
                  let terminated = calls.firstIndex(of: terminate), terminated > runner
            else { return false }
            return !calls[(runner + 1) ..< terminated].contains { $0.contains(udid) }
        }

        /// Whether the runner app on `udid` was terminated after its last runner, the appearance retry's, and before the handback's accessibility restore — the pass's own put-back from the host comes between the two, and the handback's reads of the device after.
        func terminatedRetryRunnerBeforeHandback(of udid: String) -> Bool {
            let calls = calls
            let terminate = ["simctl", "terminate", udid, RunnerInvocation.deviceContainerBundleID(runnerBundleID: nil)]
            guard let runner = calls.lastIndex(where: { $0.contains("test-without-building") && Self.destination($0) == udid }),
                  let terminated = calls.firstIndex(of: terminate), terminated > runner
            else { return false }
            return calls[(terminated + 1)...].contains { $0.starts(with: ["simctl", "spawn", udid]) }
        }

        var now: () -> Date {
            { [self] in lock.withLock { Date(timeIntervalSince1970: elapsed) } }
        }

        var run: (String, [String], [String: String]) throws -> Shell.Result {
            { [self] _, arguments, environment in
                lock.withLock {
                    recorded.append(arguments)
                    elapsed += 0.2
                }
                if arguments.contains("test-without-building") {
                    return try runner(arguments, environment)
                }
                if deleteFails, arguments.starts(with: ["simctl", "delete"]) {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "An error was encountered processing the command (code=164)\n")
                }
                if case .buildFails = mode, arguments.contains("build-for-testing") {
                    return Shell.Result(status: 65, standardOutput: "", standardError: "** BUILD FAILED **\n")
                }
                return lock.withLock { answer(arguments) }
            }
        }

        private func runner(_ arguments: [String], _ environment: [String: String]) throws -> Shell.Result {
            let udid = Self.destination(arguments)
            lock.withLock {
                started.insert(udid)
                runs[udid, default: 0] += 1
            }
            switch mode {
            case .clean, .buildFails:
                break
            case .cloneFailsDuringRetry:
                // Shard 0's first runner writes its bundle; its second, the appearance retry's, waits for the stop the clone's failure calls.
                guard udid == Self.clone else {
                    return lock.withLock { runs[udid] } == 1 ? write(udid, environment) : try waitForStop(udid, arguments, environment)
                }
                waitUntil { self.lock.withLock { self.runs["UDID-1", default: 0] >= 2 } }
                return Shell.Result(status: 65, standardOutput: "", standardError: "** TEST EXECUTE FAILED **\n")
            case .cloneFails:
                guard udid == Self.clone else { return try waitForStop(udid, arguments, environment) }
                waitUntil { self.lock.withLock { self.started.contains("UDID-1") } }
                return Shell.Result(status: 65, standardOutput: "", standardError: "** TEST EXECUTE FAILED **\n")
            case let .cancelDuringClone(cancellation, endsStopped):
                guard udid == Self.clone else {
                    return try endsStopped ? waitForStop(udid, arguments, environment) : write(udid, environment)
                }
                waitUntil { self.lock.withLock { self.started.contains("UDID-1") } }
                cancellation.cancel()
                let gone = ran(["simctl", "delete", Self.clone])
                lock.withLock { deleted = gone }
                if endsStopped {
                    throw ShellError.stopped
                }
            }
            return write(udid, environment)
        }

        /// A runner that ends as a stopped child does once the walk's stop is called, or writes its bundle when ``waitBound`` passes without it.
        private func waitForStop(_ udid: String, _: [String], _ environment: [String: String]) throws -> Shell.Result {
            waitUntil { self.stop.isStopped }
            guard stop.isStopped else { return write(udid, environment) }
            lock.withLock { stopped.append(udid) }
            throw ShellError.stopped
        }

        /// How long a scripted runner waits for what its mode expects (the walk's stop, the other shard's start) before giving up, in seconds. Only a hang guard: every mode expects the condition, so a passing run never waits it out. Five seconds was too short under a loaded machine's full parallel suite (load 150-330): three tests timed out at 6.03 s with the stop never seen.
        private static let waitBound: TimeInterval = 60

        private func waitUntil(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(Self.waitBound)
            while !condition(), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        /// Copies the canned bundle of the screens the runner's walkbook names to its output, stamped as the real runner stamps its manifest.
        private func write(_ udid: String, _ environment: [String: String]) -> Shell.Result {
            let book = environment["TEST_RUNNER_SIMWALK_WALKBOOK"].flatMap { try? WalkbookLoader.load(contentsOf: URL(fileURLWithPath: $0)) }
            let output = URL(fileURLWithPath: environment["TEST_RUNNER_SIMWALK_OUTPUT"] ?? "")
            guard let screen = book?.screens.first?.id, let canned = bundles[screen], book?.screens.count == 1 else {
                return Shell.Result(status: 1, standardOutput: "", standardError: "no canned bundle\n")
            }
            do {
                try FileManager.default.copyItem(at: canned, to: output)
                try Self.stamp(output, udid: udid, environment: environment)
            } catch {
                return Shell.Result(status: 1, standardOutput: "", standardError: "\(error)\n")
            }
            lock.withLock { appearance[udid] = "light" }
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        }

        /// Rewrites the copied manifest with the driver's build hash and nonce, the device that ran, and a start no earlier than now.
        private static func stamp(_ url: URL, udid: String, environment: [String: String]) throws {
            let manifestURL = CaptureBundle.manifestURL(in: url)
            let original = try CaptureBundle.read(at: url).manifest
            let start = max(original.startedAt, Date())
            var stamped = CaptureManifest(
                formatVersion: original.formatVersion,
                walkName: original.walkName,
                appBundleID: original.appBundleID,
                appBuildHash: environment["TEST_RUNNER_SIMWALK_BUILD_HASH"] ?? original.appBuildHash,
                walkbookHash: original.walkbookHash,
                device: CaptureManifest.Device(name: name(of: udid), udid: udid, osVersion: original.device.osVersion),
                startedAt: start,
                finishedAt: start.addingTimeInterval(1),
                settleQuietMilliseconds: original.settleQuietMilliseconds,
                runnerCommit: original.runnerCommit,
                appearanceSettle: original.appearanceSettle,
                nonce: environment["TEST_RUNNER_SIMWALK_NONCE"] ?? original.nonce,
                appBuildProvenance: original.appBuildProvenance,
                animations: original.animations,
                screens: original.screens
            )
            stamped.deviceSetup = original.deviceSetup
            try FileManager.default.removeItem(at: manifestURL)
            _ = try CaptureBundleWriter(reopening: url).finalise(stamped)
        }

        private static func name(of udid: String) -> String {
            udid == clone ? "iPhone 17 Pro (SimWalk lease)" : "iPhone 17 Pro"
        }

        /// The UDID in `-destination …,id=<udid>`.
        private static func destination(_ arguments: [String]) -> String {
            guard let index = arguments.firstIndex(of: "-destination"), index + 1 < arguments.count else { return "" }
            let field = arguments[index + 1].split(separator: ",").first { $0.hasPrefix("id=") }
            return field.map { String($0.dropFirst(3)) } ?? ""
        }

        /// The device a `simctl` call names: its third argument.
        private static func device(_ arguments: [String]) -> String {
            arguments.count > 2 ? arguments[2] : ""
        }

        private func listing() -> String {
            // The device type is listed only beside the booted extra, which the pool takes only when it is like shard 0.
            let type = bootedExtra ? #","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro""# : ""
            let devices = (["UDID-1"] + (bootedExtra ? ["UDID-2"] : []) + (cloned ? [Self.clone] : [])).map { udid in
                #"{"udid":"\#(udid)","name":"\#(Self.name(of: udid))","state":"\#(booted.contains(udid) ? "Booted" : "Shutdown")"\#(type)}"#
            }
            return #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[\#(devices.joined(separator: ","))]}}"#
        }

        /// Everything but the runner, under the lock.
        private func answer(_ arguments: [String]) -> Shell.Result {
            let udid = Self.device(arguments)
            let output: String
            switch arguments {
            case _ where arguments.starts(with: ["simctl", "list"]):
                output = listing()
            case _ where arguments.starts(with: ["simctl", "clone"]):
                cloned = true
                output = Self.clone
            case _ where arguments.starts(with: ["simctl", "boot"]):
                booted.insert(udid)
                output = ""
            case _ where arguments.starts(with: ["simctl", "shutdown"]):
                booted.remove(udid)
                output = ""
            case _ where arguments.starts(with: ["simctl", "delete"]):
                cloned = false
                output = ""
            case _ where arguments.starts(with: ["simctl", "get_app_container"]):
                output = appPath
            case _ where arguments.starts(with: ["simctl", "ui"]) && arguments.count > 3 && arguments[3] == "increase_contrast":
                output = "disabled"
            case _ where arguments.starts(with: ["simctl", "ui"]):
                if arguments.count == 5, arguments[3] == "appearance" {
                    appearance[udid] = arguments[4]
                }
                output = appearance[udid] ?? "light"
            case _ where arguments.contains("-g") && arguments.last == "AppleLocale":
                output = "en_GB"
            case _ where arguments.contains("-g") && arguments.last == "AppleLanguages":
                output = "(\n    \"en-GB\"\n)"
            case _ where arguments.contains("write"):
                accessibility[udid] = "1"
                output = ""
            case _ where arguments.contains("read"):
                output = accessibility[udid] ?? "0"
            case _ where arguments.starts(with: ["simctl", "status_bar"]):
                output = "Current Status Bar Overrides:\n============================="
            default:
                output = ""
            }
            return Shell.Result(status: 0, standardOutput: "\(output)\n", standardError: "")
        }
    }
}

extension ParallelWalkTests.ParallelScript {
    /// How the runners behave.
    enum Mode {
        /// Every runner writes its bundle and exits 0.
        case clean
        /// The clone's runner exits 65 once shard 0's has started, which waits for the walk's stop.
        case cloneFails
        /// The clone's runner exits 65 once shard 0's second runner, the appearance retry's, has started, which waits for the walk's stop.
        case cloneFailsDuringRetry
        /// The runner build on shard 0 fails, after the clone was made.
        case buildFails
        /// The clone's runner cancels `cancellation` once shard 0's has started; `stopped` says whether the runners then end as stopped children do, or carry on.
        case cancelDuringClone(Cancellation, stopped: Bool)
    }
}
