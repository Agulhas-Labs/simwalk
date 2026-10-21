//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

extension WalkCommand {
    /// What a `walk --parallel` hands its shard walks once shard 0 is prepared: the plan, the extra devices and the stop that ends them all.
    struct ParallelRun {
        /// Shard 0, prepared as a serial walk prepares its device.
        let prepared: Prepared
        /// The book the plan was made from: the walkbook, narrowed to `--screens` when they were given.
        let narrowedBook: Walkbook
        let plan: ShardPlan
        /// The devices shards 1 and up run on, in shard order.
        let extras: [ShardDevicePool.Shard]
        let pool: ShardDevicePool
        /// Stops every shard's runner and boot once one shard has failed.
        let stop: ChildStop
        let builds: RunnerBuilds
        /// Whether the walk may reboot shard 0, as a serial walk decides it; an extra's is its own ``ShardDevicePool/Shard/mayReboot``.
        let owned: Bool
        /// Whether the run has been interrupted (a SIGINT or SIGTERM), which a refusal says.
        var interrupted: () -> Bool = { false }
    }

    /// Walks every shard of `parallel` at once, one device each, and answers with one bundle merged in walkbook order, or refuses naming the shard that failed first.
    ///
    /// Each runner, and each extra's boot and install, runs through a shell `parallel.stop` can stop, so the first failure ends the others rather than waiting them out; device reads, setup and handback use the plain shell, so a stopped shard still hands its device back. Telemetry follows shard 0 alone.
    func walkShards(
        _ parallel: ParallelRun,
        shell: Shell = Shell(),
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: @escaping () -> Date = { Date() },
        nonce: @escaping () -> String = { UUID().uuidString },
        logFileURL: URL = UsageLog.standard().fileURL,
        leases: LeaseStore,
        telemetry: WalkTelemetry? = nil,
        provisioning: (Shell) -> SlimWalkProvisioning = { SlimWalkProvisioning(shell: $0) }
    ) throws -> Outcome {
        let output = parallel.prepared.outputURL
        _ = try CaptureBundleWriter(preparingAt: output)
        let count = parallel.plan.shards.count
        let lock = NSLock()
        var outcomes = [Outcome?](repeating: nil, count: count)
        var errors = [Error?](repeating: nil, count: count)
        var causeIndex: Int?
        withoutActuallyEscaping(pause) { pause in withoutActuallyEscaping(provisioning) { provisioning in
            let work = ShardWork { index in
                do {
                    let outcome = try walkShard(index, of: parallel, shell: shell, pause: pause, now: now, nonce: nonce, logFileURL: logFileURL, leases: leases, telemetry: index == 0 ? telemetry : nil, provisioning: provisioning)
                    lock.withLock { outcomes[index] = outcome }
                } catch {
                    let first = lock.withLock {
                        errors[index] = error
                        guard causeIndex == nil else { return false }
                        causeIndex = index
                        return true
                    }
                    // The first failure is the cause, and ends every other shard.
                    if first {
                        parallel.stop.stop()
                    }
                }
            }
            DispatchQueue.concurrentPerform(iterations: count) { work.body($0) }
        } }
        let devices = [parallel.prepared.simulator] + parallel.extras.map(\.simulator)
        if let causeIndex, let cause = errors[causeIndex] {
            for index in 0 ..< count {
                try? FileManager.default.removeItem(at: CaptureBundleLayout.shardScratchDirectory(in: output, index: index))
            }
            if (try? FileManager.default.contentsOfDirectory(atPath: output.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: output)
            }
            // Each other shard by what became of it: a shard that finished, or failed on its own, is not called stopped.
            let others = (0 ..< count).filter { $0 != causeIndex }.flatMap { index in
                let shard = "\(Self.label(devices[index])) (\(parallel.plan.shards[index].joined(separator: ", ")))"
                let line = if let outcome = outcomes[index] {
                    outcome.endedByStop ? "stopped: \(shard)" : "finished: \(shard)"
                } else if let error = errors[index], !Self.isStop(error) {
                    "failed: \(shard): \((error as? Refusal).map { String(describing: $0.underlying) } ?? String(describing: error))"
                } else {
                    "stopped: \(shard)"
                }
                return [line] + Self.shardNotes(outcomes[index], errors[index]).map { "  \($0)" }
            }
            throw ParallelWalkRefusal(
                device: Self.label(devices[causeIndex]),
                screens: parallel.plan.shards[causeIndex],
                cause: String(describing: cause),
                causeIsStop: Self.isStop(cause),
                interrupted: parallel.interrupted(),
                others: others,
                unreleased: parallel.pool.release(),
                usageFailureKind: (cause as? UsageFailureClassifiable)?.usageFailureKind ?? .runnerFailed
            )
        }
        let merged: ShardBundleMerge.Result
        do {
            merged = try ShardBundleMerge.merge(walkbook: parallel.narrowedBook, plan: parallel.plan, into: output)
        } catch {
            // Every shard walked and handed its device back: what each put back is said with the merge's failure, and what the pool could not give back.
            let notes = (0 ..< count).flatMap { index in
                let lines = Self.shardNotes(outcomes[index], nil)
                return lines.isEmpty ? [] : ["\(Self.label(devices[index])) (\(parallel.plan.shards[index].joined(separator: ", "))):"] + lines.map { "  \($0)" }
            }
            throw ParallelWalkFailure(underlying: error, notes: notes, unreleased: parallel.pool.release())
        }
        let walked = outcomes.compactMap(\.self)
        var outcome = walked[0]
        outcome.bundle = merged.bundle
        outcome.otherDevices = Array(walked.dropFirst())
        outcome.otherDeviceLabels = devices.dropFirst().map(Self.label)
        let unreleased = parallel.pool.release()
        outcome.parallelLines = Self.parallelLines(parallel, devices: devices, leftovers: merged.leftoverShardDirectories, unreleased: unreleased)
        outcome.parallelQualifications = unreleased.map { $0.command.hasPrefix("simctl") ? "a device the walk created was not deleted" : "a lease the walk took was not released" }
        return outcome
    }

    /// One shard's walk: an extra is booted, given the app and checked against shard 0's build first; then its screens are walked into its own scratch bundle.
    private func walkShard(
        _ index: Int,
        of parallel: ParallelRun,
        shell: Shell = Shell(),
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: @escaping () -> Date = { Date() },
        nonce: @escaping () -> String = { UUID().uuidString },
        logFileURL: URL = UsageLog.standard().fileURL,
        leases: LeaseStore,
        telemetry: WalkTelemetry? = nil,
        provisioning: (Shell) -> SlimWalkProvisioning = { SlimWalkProvisioning(shell: $0) }
    ) throws -> Outcome {
        let prepared = parallel.prepared
        let stoppable = shell.stopped(by: parallel.stop)
        var simulator = prepared.simulator
        var lease = prepared.lease
        var bootNote: String?
        if index > 0 {
            let shard = parallel.extras[index - 1]
            simulator = shard.simulator
            bootNote = try shard.boot(with: provisioning(stoppable), stockRequested: stock, appPath: appPath) { try $0.boot(shell: stoppable) }
            if let appPath {
                try simulator.install(appPath: appPath, shell: stoppable)
            }
            guard let installed = try simulator.installedAppPath(bundleID: prepared.book.appBundleID, shell: stoppable) else {
                throw SimulatorError.appNotInstalled(bundleID: prepared.book.appBundleID, udid: simulator.udid)
            }
            let hash = try AppBuildIdentity.hash(ofAppAt: installed)
            guard hash == prepared.buildHash else {
                throw ParallelWalkRefusal.BuildDiffers(udid: simulator.udid, expected: prepared.buildHash, found: hash)
            }
            guard let held = parallel.pool.lease(for: shard) else {
                throw ShardDevicePoolError.released
            }
            lease = held
        }
        let executed = try Self.walkbookToExecute(prepared.book, at: walkbook, screens: parallel.plan.shards[index])
        defer { Self.discardTemporary(executed.temporaryURL) }
        let runner = RunnerInvocation(projectPath: prepared.source.projectPath, derivedDataPath: parallel.builds.directory(for: prepared.source).path, shell: stoppable)
        let run = DeviceRun(
            book: prepared.book,
            outputURL: CaptureBundleLayout.shardScratchDirectory(in: prepared.outputURL, index: index),
            source: prepared.source,
            simulator: simulator,
            buildHash: prepared.buildHash,
            executedPath: executed.path,
            runner: runner,
            lease: lease,
            animationsOffLibrary: prepared.animationsOffLibrary,
            owned: index == 0 ? parallel.owned : parallel.extras[index - 1].mayReboot
        )
        var outcome = try walkDevice(run, shell: shell, pause: pause, now: now, nonce: nonce, logFileURL: logFileURL, leases: leases, telemetry: telemetry)
        outcome.deviceNote = bootNote
        return outcome
    }

    /// Whether `error` is the walk's own stop ending a shard's runner, boot or install, rather than a failure of its own.
    static func isStop(_ error: Error) -> Bool {
        let underlying = (error as? Refusal)?.underlying ?? error
        return underlying as? ShellError == .stopped
    }

    /// What a shard handed its device back in and its setup's lines, from its outcome or its refusal.
    private static func shardNotes(_ outcome: Outcome?, _ error: Error?) -> [String] {
        if let outcome {
            return (outcome.handback?.notes ?? []) + (outcome.setup?.lines ?? []) + [outcome.setupNotMade].compactMap(\.self)
        }
        guard let refusal = error as? Refusal else { return [] }
        return refusal.handback.notes + (refusal.setup?.lines ?? []) + [refusal.setupNotMade].compactMap(\.self)
    }

    /// The answer's lines about the shards: which device walked which screens, how many were created and deleted, a clamp, and anything left behind.
    private static func parallelLines(_ parallel: ParallelRun, devices: [Simulator], leftovers: [URL], unreleased: [ShardDevicePool.Unreleased]) -> [String] {
        let created = parallel.extras.filter(\.createdByWalk).count
        let shards = zip(devices, parallel.plan.shards).map { "\(label($0)) (\($1.joined(separator: ", ")))" }
        let made = created == 0 ? "none created" : "\(created) created, \(unreleased.isEmpty ? "deleted" : "not all given back")"
        return ["parallel: \(devices.count) devices — \(shards.joined(separator: ", ")); \(made)"]
            + (parallel.plan.clamped ? [clampNote(parallel.plan, screens: parallel.narrowedBook.screens.count)] : [])
            + leftovers.map { "⚠ shard directory left in the bundle: \($0.path)" }
            + unreleased.map { "⚠ not given back: \($0)" }
    }

    /// The line a plan clamped to its screen count carries.
    static func clampNote(_ plan: ShardPlan, screens: Int) -> String {
        "parallel: \(plan.shards.count) device\(plan.shards.count == 1 ? "" : "s") (asked for \(plan.requested); the plan has \(screens) screen\(screens == 1 ? "" : "s"))"
    }

    /// A device as the answer names it: its name and the first eight characters of its UDID.
    static func label(_ simulator: Simulator) -> String {
        "\(simulator.name) \(simulator.udid.prefix(8))"
    }
}
