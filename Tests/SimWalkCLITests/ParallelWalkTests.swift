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

    /// Shard 0 on a lease whose device `lease acquire --clone-from` made is labelled `cloned` on the `walk.parallel` line, not `created` or an existing device's (SimWalk#189).
    @Test
    func shardZeroOnACloneMadeLeaseIsLabelledCloned() throws {
        let machine = try Machine()
        let lease = try machine.leases.acquire(udid: "UDID-1", ttl: 3600, holderPID: getpid(), now: Date(), createdDevice: true, clonedFrom: "SOURCE-1", token: "LEASE-1")
        let watch = Machine.Watch()
        machine.script.read(releaseClockFrom: watch)
        let telemetry = machine.telemetry(clock: watch.tick)

        _ = try machine.walk(machine.command(lease: lease.token), telemetry: telemetry, logFileURL: machine.usageLog)

        let line = try #require(machine.usageEntries().first { $0.tool == UsageLog.parallelTool })
        let timings = try #require(line.parallel)

        #expect(timings.shards.map(\.origin) == [.cloned, .cloned])
    }

    /// A two-shard walk on a telemetry clock that ticks a second at every read writes one `walk.parallel` line: each shard's origin, ready, runner start and runner end in that order and none past the line's own `ms`, and a merge time.
    ///
    /// The result file's `timings.parallel` is the same value.
    @Test
    func aTwoShardWalkWritesOneParallelUsageLineAndTheSameBreakdownInTheResult() throws {
        let machine = try Machine()
        let watch = Machine.Watch()
        machine.script.read(releaseClockFrom: watch)
        let telemetry = machine.telemetry(clock: watch.tick)

        _ = try machine.walk(machine.command(), telemetry: telemetry, logFileURL: machine.usageLog)

        let lines = try machine.usageEntries().filter { $0.tool == UsageLog.parallelTool }
        let line = try #require(lines.first)
        let timings = try #require(line.parallel)
        #expect(lines.count == 1)
        #expect(line.target == machine.walkbook)
        #expect(line.succeeded)
        #expect(timings.shards.map(\.index) == [0, 1])
        #expect(timings.shards.map(\.device) == ["UDID-1", ParallelScript.clone])
        #expect(timings.shards.map(\.origin) == [.existingShutDown, .cloned])
        for shard in timings.shards {
            let ready = try #require(shard.readyMs)
            let started = try #require(shard.runnerStartMs)
            let ended = try #require(shard.runnerEndMs)
            #expect(ready >= 0 && ready <= started && started <= ended && ended <= line.milliseconds)
        }
        #expect(try #require(timings.mergeMs) > 0)
        // The line ends at the merge, not after the clone is deleted: the clock ticks at every read, so a line written after the release is later than the clock was at the delete.
        let released = try #require(machine.script.clockAtRelease)
        #expect(line.milliseconds <= Int((released - watch.started) * 1000))
        let result = try WalkResult.decoder().decode(WalkResult.self, from: Data(contentsOf: machine.resultURL))
        #expect(result.timings.parallel == timings)
        #expect(try #require(result.timings.totalMs) >= line.milliseconds)
    }

    /// A walk whose clone fails still writes its `walk.parallel` line, `ok` false, with no merge.
    @Test
    func aFailedParallelWalkStillWritesItsParallelUsageLine() throws {
        let machine = try Machine(mode: .cloneFails)
        let telemetry = machine.telemetry(clock: Machine.Watch().tick)

        #expect(throws: ParallelWalkRefusal.self) {
            try machine.walk(machine.command(), telemetry: telemetry, logFileURL: machine.usageLog)
        }

        let line = try #require(machine.usageEntries().first { $0.tool == UsageLog.parallelTool })
        let timings = try #require(line.parallel)
        #expect(!line.succeeded)
        #expect(timings.shards.count == 2)
        #expect(timings.shards.allSatisfy { $0.readyMs != nil })
        // The clone's runner threw, and its end is marked all the same.
        #expect(timings.shards[1].runnerEndMs != nil)
        #expect(timings.mergeMs == nil)
        // The line says why it failed, as the `walk` line does, so a report does not count it as an unclassified failure.
        #expect(line.error != nil)
        #expect(line.kind == .runnerFailed)
    }

    /// A merge that fails still writes the line: `ok` false, the merge's duration in it, and the shards' marks.
    ///
    /// The clone's runner leaves the output directory unwritable, so the merge cannot move the screens into it.
    @Test
    func aWalkWhoseMergeFailsWritesItsParallelLineWithTheMergeTime() throws {
        let machine = try Machine(mode: .mergeFails)
        defer { machine.script.makeOutputWritable() }
        let telemetry = machine.telemetry(clock: Machine.Watch().tick)

        #expect(throws: ParallelWalkFailure.self) {
            try machine.walk(machine.command(), telemetry: telemetry, logFileURL: machine.usageLog)
        }

        let lines = try machine.usageEntries().filter { $0.tool == UsageLog.parallelTool }
        let line = try #require(lines.first)
        let timings = try #require(line.parallel)
        #expect(lines.count == 1)
        #expect(!line.succeeded)
        #expect(try #require(timings.mergeMs) > 0)
        #expect(timings.shards.allSatisfy { $0.runnerEndMs != nil })
    }

    /// An interruption writes the line at the cancel: a signal ends the process before the walk's own end, and the walk's end, which still runs in a test, writes nothing more.
    ///
    /// Only the cancel's handler says `interrupted`: the walk's own end would record the refusal's text.
    ///
    /// The line's `ms` is where the clock stood as the cancel was heard, not after the clone was deleted (SimWalk#189): the line's handler runs after the one that gives the devices back, and the clock ticks at every read, so a line that read it there is later than the clock was at the delete.
    @Test
    func anInterruptionWritesTheParallelLineOnceAtTheCancel() throws {
        let interruption = Cancellation()
        let machine = try Machine(mode: .cancelDuringClone(interruption, stopped: true))
        let watch = Machine.Watch()
        machine.script.read(releaseClockFrom: watch)
        let telemetry = machine.telemetry(clock: watch.tick)

        #expect(throws: ParallelWalkRefusal.self) {
            try machine.walk(machine.command(), interruption: interruption, telemetry: telemetry, logFileURL: machine.usageLog)
        }

        let lines = try machine.usageEntries().filter { $0.tool == UsageLog.parallelTool }
        #expect(lines.count == 1)
        #expect(lines.first?.succeeded == false)
        #expect(lines.first?.error == "interrupted")
        #expect(lines.first?.parallel?.mergeMs == nil)
        let released = try #require(machine.script.clockAtRelease)
        let milliseconds = try #require(lines.first?.milliseconds)
        #expect(milliseconds <= Int((released - watch.started) * 1000))
        let marks = (lines.first?.parallel?.shards ?? []).flatMap { [$0.readyMs, $0.runnerStartMs, $0.runnerEndMs, $0.retryStartMs, $0.retryEndMs] }
        #expect(marks.compactMap(\.self).allSatisfy { $0 <= milliseconds })
    }

    /// The clone's runner exits 65 over a complete bundle (SimWalk#176).
    ///
    /// XCTest blamed it for a host `xctest` crash the Mac's reports show. The shard did not fail, the walk is `ok`, and the excused line is in the answer.
    @Test
    func aShardWhoseFailureIsAHostXCTestCrashBlameLeavesTheWalkOk() throws {
        let machine = try Machine(mode: .cloneFailsBlamingACrash)
        let reports = try TemporaryDirectory()
        try WalkCommandTests.hostCrashReport.write(to: reports.url.appendingPathComponent("xctest-2026-10-21-102515.ips"), atomically: true, encoding: .utf8)

        let outcome = try machine.walk(machine.command(), crashReports: XCTestCrashEvidence(directory: reports.url))
        let answer = outcome.answer()

        #expect(outcome.bundle.manifest.screens.map(\.id) == ["progress", "browse"])
        #expect(answer.verdict.exitCode == 0)
        #expect(!answer.verdict.line.contains("a runner failure this bundle survived"))
        #expect(answer.text.contains("XCTest reported 1 \"Critical process xctest crashed\" failure for crash reports of a host process named xctest, not this walk"))
    }

    /// The same shard failure with no report to explain it qualifies the walk and adds the unexplained line.
    @Test
    func aShardWhoseFailureIsACrashBlameNoReportExplainsQualifiesTheWalk() throws {
        let machine = try Machine(mode: .cloneFailsBlamingACrash)
        let reports = try TemporaryDirectory()

        let outcome = try machine.walk(machine.command(), crashReports: XCTestCrashEvidence(directory: reports.url))
        let answer = outcome.answer()

        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(answer.verdict.line.contains("a runner failure this bundle survived"))
        #expect(answer.text.contains("the runner failure is 1 \"Critical process xctest crashed\" failure; "))
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

    /// SimWalk#182: the same interruption gives back the lease and the claim on shard 0's device — the walk's own — before the cancel returns, not only the extra's: the signal then ends the process without reaching the walk's own release.
    ///
    /// Read at the cancel, not after the walk, whose own release would hide a cancel that gave nothing back.
    @Test
    func anInterruptionReleasesTheLeaseAndClaimOnShardZerosDeviceBeforeTheCancelReturns() throws {
        let interruption = Cancellation()
        let machine = try Machine(mode: .cancelDuringClone(interruption, stopped: true))

        _ = try? machine.walk(machine.command(), interruption: interruption)

        let before = try #require(machine.script.heldBeforeCancel)
        let held = try #require(machine.script.heldAtCancel)

        // Shard 0's device was leased and claimed when the cancel came, so an empty store at the cancel is the cancel's doing.
        #expect(before.leased.contains("UDID-1") && before.claimed.contains("UDID-1"))
        #expect(!held.leased.contains("UDID-1"))
        #expect(!held.claimed.contains("UDID-1"))
    }

    /// SimWalk#187: the interruption waits for shard 0's handback, which is under way as the cancel comes, before it gives the device back; the clone, which the walk deletes, holds nothing up, though the cancel is raised on its own shard's thread, which a wait for it would wait on until the bound.
    @Test
    func anInterruptionWaitsForShardZerosHandbackAndNotForTheClone() throws {
        let interruption = Cancellation()
        let machine = try Machine(mode: .cancelDuringClone(interruption, stopped: true))
        let notes = NoteRecorder()

        _ = try? machine.walk(machine.command(), interruption: interruption, interruptionNote: notes.write)

        #expect(machine.script.firstHandedBackAtCancel == true)
        #expect(notes.lines == ["⚠ interrupted — handing the device back before exiting"])
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

    /// A shard whose appearance retry ran marks the second pass on the `walk.parallel` line, ordered after its first runner pass and within the line's `ms`; a shard that did not retry has neither mark, absent and not 0 (SimWalk#189).
    @Test
    func theAppearanceRetryPassIsMarkedOnTheShardThatRetriedAndNoOther() throws {
        let machine = try Machine(mode: .cloneFailsDuringRetry, firstShardRefusedOnAppearance: true)
        let watch = Machine.Watch()
        machine.script.read(releaseClockFrom: watch)
        let telemetry = machine.telemetry(clock: watch.tick)

        _ = try? machine.walk(machine.command(), telemetry: telemetry, logFileURL: machine.usageLog)

        let line = try #require(machine.usageEntries().first { $0.tool == UsageLog.parallelTool })
        let shards = try #require(line.parallel).shards
        let retried = try #require(shards.first)
        let runnerEnd = try #require(retried.runnerEndMs)
        let retryStart = try #require(retried.retryStartMs)
        let retryEnd = try #require(retried.retryEndMs)

        #expect(runnerEnd <= retryStart && retryStart <= retryEnd && retryEnd <= line.milliseconds)
        #expect(shards.dropFirst().allSatisfy { $0.retryStartMs == nil && $0.retryEndMs == nil })
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
            environment: ["SIMWALK_USAGE_LOG": machine.usageLog.path, WalkCommand.sessionVariable: "parallel-mcp"],
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
        // The log the injected environment names, never the machine's own (SimWalk#192).
        #expect(try machine.usageEntries().count { $0.tool == UsageLog.parallelTool } == 1)
    }
}

extension ParallelWalkTests.Machine {
    /// A monotonic clock that moves a second at each read, from any shard's thread.
    final class Watch: @unchecked Sendable {
        private let lock = NSLock()
        private var seconds: TimeInterval = 0
        private var first: TimeInterval?

        func tick() -> TimeInterval {
            lock.withLock {
                seconds += 1
                first = first ?? seconds
                return seconds
            }
        }

        /// The last time read, without a tick; the telemetry's start is the first read, so the walk's offset now is this less ``started``.
        var current: TimeInterval {
            lock.withLock { seconds }
        }

        /// The first time read, which the walk's offsets count from.
        var started: TimeInterval {
            lock.withLock { first ?? 0 }
        }
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
        ///
        /// `auditTimedOut` names the screens whose capture carries an Apple audit record of XCTest's audit timeout (SimWalk#173).
        init(mode: ParallelScript.Mode = .clean, screens: [String] = ["progress", "browse"], bootedExtra: Bool = false, setup: Bool = false, deleteFails: Bool = false, firstShardRefusedOnAppearance: Bool = false, auditTimedOut: Set<String> = []) throws {
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
                let capture = CaptureBundleFixture.Capture(screenID: screen, state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen(), appleAudit: auditTimedOut.contains(screen) ? TestManagerRestartTests.timedOut : nil)
                let refused = (bootedExtra && !setup && screen == "browse") || (firstShardRefusedOnAppearance && screen == "progress") ? [Walkbook.CaptureState(theme: .dark)] : []
                let outcome: ScreenOutcome = refused.isEmpty ? .captured : .stateNotApplied(reason: "the appearance did not apply")
                let spec = CaptureBundleFixture.ScreenSpec(id: screen, outcome: outcome, captures: [capture], refusedStates: refused, refusedOnAppearance: refused)
                bundles[screen] = try CaptureBundleFixture.writeWalk(in: stage, screens: [spec], appBundleID: "com.example.probe").url
            }
            self.staged = staged
            script = try ParallelScript(appPath: WalkCommandTests.fakeApp(in: directory), bundles: bundles, mode: mode, leases: leases, bootedExtra: bootedExtra, deleteFails: deleteFails)
        }

        /// `lease` walks shard 0 under that `--lease` token instead of `--device UDID-1`.
        func command(parallel: Int = 2, lease: String? = nil) throws -> WalkCommand {
            let device = lease.map { ["--lease", $0] } ?? ["--device", "UDID-1"]
            return try WalkCommand.parse([walkbook, "--output", output] + device + ["--parallel", "\(parallel)"])
        }

        /// Where the walk's result file goes when it is watched.
        var resultURL: URL {
            directory.url.appendingPathComponent("result.json")
        }

        /// The usage log a watched walk writes to, in scratch.
        var usageLog: URL {
            directory.url.appendingPathComponent("usage.jsonl")
        }

        /// A telemetry on `clock`, writing its progress and result into scratch.
        func telemetry(clock: @escaping () -> TimeInterval) -> WalkTelemetry {
            WalkTelemetry(writer: ProgressWriter(url: directory.url.appendingPathComponent("progress.json"), clock: { Date() }, pid: 1), resultURL: resultURL, clock: clock)
        }

        /// Every line of ``usageLog``, decoded; none when nothing was written.
        func usageEntries() throws -> [UsageLog.Entry] {
            guard FileManager.default.fileExists(atPath: usageLog.path) else { return [] }
            return try String(contentsOf: usageLog, encoding: .utf8).split(separator: "\n").map { try JSONDecoder().decode(UsageLog.Entry.self, from: Data($0.utf8)) }
        }

        /// The walk on the script, with the script's stop and the override root in scratch, logging to ``usageLog`` unless told otherwise: never the machine's own usage log.
        func walk(_ command: WalkCommand, interruption: Cancellation? = nil, crashReports: XCTestCrashEvidence = XCTestCrashEvidence(), telemetry: WalkTelemetry? = nil, logFileURL: URL? = nil, interruptionNote: @escaping @Sendable (String) -> Void = { _ in }) throws -> WalkCommand.Outcome {
            let overrideRoot = overrideRoot
            return try command.performWalk(
                shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { WalkCommandTests.runner }, logFileURL: logFileURL ?? usageLog,
                builds: WalkCommandTests.builds(in: directory), leases: leases, telemetry: telemetry,
                provisioning: { SlimWalkProvisioning(shell: $0, overrides: DisabledServicesOverride(root: overrideRoot)) },
                interruption: interruption, childStop: script.stop, interruptionNote: interruptionNote, crashReports: crashReports
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
        private let leases: LeaseStore
        private var held: (leased: [String], claimed: Set<String>)?
        private var heldBefore: (leased: [String], claimed: Set<String>)?
        private var firstHandedBack: Bool?
        private var releaseClock: Machine.Watch?
        private var releaseReading: TimeInterval?
        private var lockedOutput: URL?
        private var leasedAtLaunchctl: [[String]] = []

        init(appPath: String, bundles: [String: URL], mode: Mode, leases: LeaseStore, bootedExtra: Bool = false, deleteFails: Bool = false) {
            self.leases = leases
            self.deleteFails = deleteFails
            self.appPath = appPath
            self.bundles = bundles
            self.mode = mode
            self.bootedExtra = bootedExtra
            booted = bootedExtra ? ["UDID-2"] : []
        }

        /// Reads `watch` when the clone is deleted, for ``clockAtRelease``.
        func read(releaseClockFrom watch: Machine.Watch) {
            lock.withLock { releaseClock = watch }
        }

        /// What the watch last read when the walk deleted the clone; `nil` when it did not, or nothing was watched.
        var clockAtRelease: TimeInterval? {
            lock.withLock { releaseReading }
        }

        /// Puts back the write permission ``Mode/mergeFails`` took from the output directory, so the scratch can be removed.
        func makeOutputWritable() {
            guard let url = lock.withLock({ lockedOutput }) else { return }
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
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

        /// The devices the lease store held a lease on and the devices with a live claim, as the cancel returned; `nil` when nothing cancelled.
        var heldAtCancel: (leased: [String], claimed: Set<String>)? {
            lock.withLock { held }
        }

        /// Whether shard 0's appearance had been put back by the time the cancel returned; `nil` when no cancel was raised.
        var firstHandedBackAtCancel: Bool? {
            lock.withLock { firstHandedBack }
        }

        /// The same, read just before the cancel: what the walk held for the cancel to give back.
        var heldBeforeCancel: (leased: [String], claimed: Set<String>)? {
            lock.withLock { heldBefore }
        }

        /// The devices the lease store held a lease on at each `launchctl` call, in call order.
        var leasedAtRestart: [[String]] {
            lock.withLock { leasedAtLaunchctl }
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
                if arguments.starts(with: ["xcresulttool", "get", "test-results", "tests"]) {
                    return Shell.Result(status: 0, standardOutput: WalkCommandTests.crashFailuresJSON(1), standardError: "")
                }
                if deleteFails, arguments.starts(with: ["simctl", "delete"]) {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "An error was encountered processing the command (code=164)\n")
                }
                if case .buildFails = mode, arguments.contains("build-for-testing") {
                    return Shell.Result(status: 65, standardOutput: "", standardError: "** BUILD FAILED **\n")
                }
                if arguments.contains("launchctl") {
                    let leased = leases.all().map(\.udid)
                    lock.withLock { leasedAtLaunchctl.append(leased) }
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
            case .mergeFails:
                // The clone's runner writes last, then takes the output directory's write permission, which the merge needs to move the screens in.
                guard udid == Self.clone else { break }
                waitUntil { self.lock.withLock { self.appearance["UDID-1"] != nil } }
                let written = write(udid, environment)
                // A missing variable would resolve to the current directory, whose permissions this must not touch (SimWalk#195).
                guard written.status == 0, let path = environment["TEST_RUNNER_SIMWALK_OUTPUT"] else { return written }
                let output = URL(fileURLWithPath: path).deletingLastPathComponent()
                lock.withLock { lockedOutput = output }
                try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: output.path)
                return written
            case .cloneFailsBlamingACrash:
                // The clone's runner writes its bundle and its result bundle, then exits 65: XCTest's failure, not a lost walk.
                guard udid == Self.clone else { break }
                if let flag = arguments.firstIndex(of: "-resultBundlePath") {
                    try FileManager.default.createDirectory(atPath: arguments[flag + 1], withIntermediateDirectories: true)
                }
                let written = write(udid, environment)
                return Shell.Result(status: written.status == 0 ? 65 : written.status, standardOutput: "", standardError: written.standardError)
            case .cloneCrashesBeforeItsManifestAfterShardZeroFails:
                guard udid == Self.clone else {
                    waitUntil { self.lock.withLock { self.started.contains(Self.clone) } }
                    return Shell.Result(status: 65, standardOutput: "", standardError: "** TEST EXECUTE FAILED **\n")
                }
                waitUntil { self.stop.isStopped }
                let written = write(udid, environment)
                // A missing variable would resolve to the current directory, whose manifest.json this must not delete (SimWalk#195).
                guard written.status == 0, let path = environment["TEST_RUNNER_SIMWALK_OUTPUT"] else { return written }
                try FileManager.default.removeItem(at: CaptureBundle.manifestURL(in: URL(fileURLWithPath: path)))
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
                let before = (leases.all().map(\.udid), WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive))
                lock.withLock { heldBefore = before }
                cancellation.cancel()
                let handedBack = ran(["simctl", "ui", "UDID-1", "appearance", "light"])
                lock.withLock { firstHandedBack = handedBack }
                let gone = ran(["simctl", "delete", Self.clone])
                let left = (leases.all().map(\.udid), WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive))
                lock.withLock { (deleted, held) = (gone, left) }
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
                releaseReading = releaseReading ?? releaseClock?.current
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
        /// The clone's runner writes its bundle and its result bundle and exits 65; `xcresulttool` lists one `Critical process xctest crashed` failure for it.
        case cloneFailsBlamingACrash
        /// The clone's runner exits 65 once shard 0's has started, which waits for the walk's stop.
        case cloneFails
        /// Shard 0's runner exits 65, writing nothing, once the clone's has started; the clone's, once the walk's stop is called, files its captures and audit records and exits 65 without a manifest, as a runner that crashed before it finalised one does — a shard that failed on its own after the first.
        case cloneCrashesBeforeItsManifestAfterShardZeroFails
        /// Both runners write their bundles; the clone's, last, leaves the output directory unwritable, so the merge fails.
        case mergeFails
        /// The clone's runner exits 65 once shard 0's second runner, the appearance retry's, has started, which waits for the walk's stop.
        case cloneFailsDuringRetry
        /// The runner build on shard 0 fails, after the clone was made.
        case buildFails
        /// The clone's runner cancels `cancellation` once shard 0's has started; `stopped` says whether the runners then end as stopped children do, or carry on.
        case cancelDuringClone(Cancellation, stopped: Bool)
    }
}

extension ParallelWalkTests {
    /// What an interruption wrote on the way out, from whichever thread the cancel ran on.
    final class NoteRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var written: [String] = []

        var write: @Sendable (String) -> Void {
            { [self] line in lock.withLock { written.append(line) } }
        }

        var lines: [String] {
            lock.withLock { written }
        }
    }
}
