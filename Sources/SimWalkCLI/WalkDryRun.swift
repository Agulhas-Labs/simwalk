//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk walk --dry-run` — every screen's route followed against the booted app, nothing captured, and a route-probe report written in place of a bundle (SimWalk#1 item 4).
///
/// **Everything before the runner is a walk's own** (`WalkCommand.prepare`): the same refusals at the same points, the same runner, the same device. What differs is what the runner is told to do and what is read back — a ``RouteProbeReport``, held to the walkbook the runner was handed — and that the device is handed back the same way whatever came of it, because the XCUITest session switched accessibility off all the same.
struct WalkDryRun {
    /// Prepares as a walk does, runs the runner in its dry-run mode, reads back the report it wrote, and hands the device back.
    ///
    /// Every child goes through `shell`, and the handback's waits through `pause` and `now` — the same seams as `WalkCommand.performWalk`, so a test can run the whole sequence against a script. `nonce` is the seam for the value passed the runner and checked back against the report — a test names a fixed one to match a report staged ahead of the run. `firstLaunch` is the dry run's one preflight (SimWalk#136).
    static func perform(
        _ command: WalkCommand,
        shell: Shell = Shell(),
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: () -> Date = { Date() },
        nonce: () -> String = { UUID().uuidString },
        runner resolveRunner: (() throws -> RunnerSource)? = nil,
        logFileURL: URL = UsageLog.standard().fileURL,
        builds: RunnerBuilds,
        leases: LeaseStore,
        telemetry: WalkTelemetry? = nil,
        firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check(),
        provisioning: (Shell) -> SlimWalkProvisioning = { SlimWalkProvisioning(shell: $0) },
        animationsLibrary: WalkCommand.AnimationsLibrary? = nil,
        note: (String) -> Void = { _ in }
    ) throws -> Outcome {
        try WalkTelemetry.recording(on: telemetry) {
            let prepared = try command.prepare(shell: shell, runner: resolveRunner, builds: builds, leases: leases, now: now(), logPath: logFileURL.path, telemetry: telemetry, firstLaunch: firstLaunch, provisioning: provisioning, animationsLibrary: animationsLibrary, note: note)
            defer { WalkCommand.discardTemporary(prepared.temporaryWalkbook) }
            // Released once the device is handed back, as a walk's is; a `--lease` lease is left to its holder.
            defer {
                prepared.claim.release()
                prepared.lease.release()
            }
            let run: (String, [String]) throws -> Shell.Result = { try shell.run($0, $1) }
            // Launching and probing are one phase here: a dry run's runner writes no progress of its own, so the host says `running`.
            telemetry?.enter(.running)

            // Read before the runner, so the handback has something to put back. A dry run never changes the
            // appearance — it changes no label — but the device is handed back exactly as a walk's is.
            let foundAppearance = try DeviceAppearance.read(udid: prepared.simulator.udid, run: run)
            // The walkbook's setup, made as a walk makes it: a route that relies on a grant rather than a `systemTap` would
            // otherwise probe as drifted. Handed back below whichever way the runner went; not made at all under a lease that could
            // no longer be renewed.
            // Recorded on disk change by change until handed back, as a walk's is (SimWalk#63), after a leftover is settled (SimWalk#72) —
            // settled with no setup too, under a lease that still renews, as a walk's is (SimWalk#73, SimWalk#75).
            let journal = DeviceSetupJournal.beside(leases)
            let (made, setupNotMade) = try WalkCommand.makeSetup(
                WalkCommand.SetupRequest(
                    setup: prepared.book.setup,
                    udid: prepared.simulator.udid,
                    bundleID: prepared.book.appBundleID,
                    owned: DeviceSettle.mayReboot(prepared.simulator, requested: command.device, leased: command.lease != nil)
                ),
                lease: prepared.lease,
                now: now(),
                journal: journal,
                run: run
            )

            var runnerFailure: Error?
            // Taken just before the runner launches; a report that started earlier is not this run's.
            let launchedAt = now()
            // Generated fresh per dry run and passed the runner below: what tells this run's report from one an
            // overlapping run of the same build left, which the build hash and `startedAt` slack alone cannot
            // (SimWalk#36) — a second run launched before this one's runner starts probing can read this one's
            // report, started after the second's own launch.
            let runNonce = nonce()
            // Named before the run, as a walk's is, so a refusal reads this run's result bundle (SimWalk#50).
            let resultBundlePath = prepared.runner.resultBundlePath(launchedAt: launchedAt, id: runNonce)
            do {
                try WalkTelemetry.measure(telemetry, \.runMs, runnerOwnsFile: false) {
                    try prepared.runner.walk(
                        walkbookPath: prepared.executedPath,
                        outputPath: prepared.outputURL.path,
                        buildHash: prepared.buildHash,
                        logFilePath: logFileURL.path,
                        settleMilliseconds: command.settle,
                        animationsOffLibrary: prepared.animationsOffLibrary,
                        runnerCommit: prepared.source.commit,
                        dryRun: true,
                        nonce: runNonce,
                        resultBundlePath: resultBundlePath,
                        on: prepared.simulator
                    )
                }
            } catch {
                runnerFailure = error
            }
            // Held to the walkbook the runner was handed — the `--screens` subset when there was one — read from the
            // same file, so the report is compared with exactly the plan that ran. It is this run's because the path
            // was refused above unless nothing was there, and because it names the build this run installed, started
            // after this run launched its runner, and carries the nonce this run generated — closing the gap the
            // build and start-time checks alone leave in an overlapping run of the same build (SimWalk#36).
            let executed = Result { try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: prepared.executedPath)) }
            let read = Result {
                try RouteProbeReport.read(at: prepared.outputURL, of: executed.get(), buildHash: prepared.buildHash, runnerLaunchedAt: launchedAt, nonce: runNonce)
            }

            let handback = DeviceHandback.perform(
                udid: prepared.simulator.udid,
                found: foundAppearance,
                runnerFinished: (try? read.get()) != nil,
                run: run,
                pause: pause,
                now: now
            )
            let setup = made.map { DeviceSetup.Report(applied: $0.applied, leftover: $0.leftover, handback: DeviceSetup.handBack($0.applied, udid: prepared.simulator.udid, bundleID: prepared.book.appBundleID, journal: journal, run: run)) }
            let launchConditionGaps = (try? executed.get()).map(RouteProbeSummary.LaunchConditionGap.all(in:)) ?? []
            var answered = try outcome(
                runnerFailure: runnerFailure,
                handback: handback,
                launchConditionGaps: launchConditionGaps,
                setup: setup,
                setupNotMade: setupNotMade,
                diagnosingRunnerFailure: { RunnerFailureDiagnosis.read(resultBundlePath: resultBundlePath, shell: shell) },
                readingReport: { try read.get() }
            )
            // `prepare` slimmed or stocked the device for a dry run as for a walk, so the answer says so as a walk's does.
            answered.deviceNote = prepared.deviceNote
            telemetry?.finish(dryRun: answered.report)
            return answered
        }
    }

    /// What a dry run answers once the runner has had its say: the report when one was written and is readable, and the runner's own failure when it was not.
    ///
    /// The whole decision and none of the I/O, as `WalkCommand.outcome` is for a walk — and decided the same way: the runner's error is preferred when both failed, because "the runner could not run" explains "there is no report", and a refusal still carries the handback.
    static func outcome(
        runnerFailure: Error?,
        handback: DeviceHandback?,
        launchConditionGaps: [RouteProbeSummary.LaunchConditionGap] = [],
        setup: DeviceSetup.Report? = nil,
        setupNotMade: String? = nil,
        diagnosingRunnerFailure diagnose: () -> RunnerFailureDiagnosis? = { nil },
        readingReport read: () throws -> RouteProbeReport
    ) throws -> Outcome {
        let report: RouteProbeReport
        do {
            report = try read()
        } catch {
            let refusal = runnerFailure ?? error
            guard let handback else { throw refusal }
            throw WalkCommand.Refusal(underlying: refusal, handback: handback, setup: setup, setupNotMade: setupNotMade, runnerDiagnosis: runnerFailure == nil ? [] : diagnose()?.lines ?? [])
        }
        return Outcome(
            report: report,
            launchConditionGaps: launchConditionGaps,
            survivedRunnerFailure: runnerFailure.map { String(describing: $0) },
            handback: handback,
            setup: setup,
            setupNotMade: setupNotMade
        )
    }
}

extension WalkDryRun {
    /// What a dry run produced: the report, and what it cannot say about the run — a runner failure it outlived, and what the device was handed back in.
    struct Outcome {
        let report: RouteProbeReport
        /// The screens whose states name a locale, argument list or environment the runner did not probe their route under.
        let launchConditionGaps: [RouteProbeSummary.LaunchConditionGap]
        /// The runner's own failure, when a readable report was on disk in spite of it.
        let survivedRunnerFailure: String?
        /// What the run put back on the device; `nil` only where a caller supplied a report without a run.
        let handback: DeviceHandback?
        /// The walkbook's setup — what the run made and what the handback put back, and a leftover another walk left, settled first; `nil` when the walkbook made none and there was no leftover (SimWalk#73).
        let setup: DeviceSetup.Report?
        /// Why the walkbook's setup was not made, or a setup an earlier walk left was not handed back — the lease could not be renewed before it; `nil` when it was made or handed back, or there was none.
        let setupNotMade: String?
        /// What the run did about the device's launchd services (``SlimWalkProvisioning/afterBoot(_:)``); `nil` when nothing was decided.
        var deviceNote: String?

        init(
            report: RouteProbeReport,
            launchConditionGaps: [RouteProbeSummary.LaunchConditionGap] = [],
            survivedRunnerFailure: String? = nil,
            handback: DeviceHandback? = nil,
            setup: DeviceSetup.Report? = nil,
            setupNotMade: String? = nil
        ) {
            self.report = report
            self.launchConditionGaps = launchConditionGaps
            self.survivedRunnerFailure = survivedRunnerFailure
            self.handback = handback
            self.setup = setup
            self.setupNotMade = setupNotMade
        }

        /// The report's answer, qualified by what the run knows and the file cannot.
        func answer() -> Answer {
            RouteProbeSummary(
                report,
                launchConditionGaps: launchConditionGaps,
                // A privacy reset nothing can read back is printed with the setup's lines, not a qualification: the route-probe
                // verdict is about routes, and the reset is the same one a walk makes (the SimWalk#63 review).
                qualifiedBy: (survivedRunnerFailure == nil ? [] : ["a runner failure this report survived"]) + (handback?.qualifications ?? []) + (setup?.qualifications(countingResets: false) ?? [])
                    + [setupNotMade].compactMap(\.self),
                notes: notes
            ).answer()
        }

        /// The failure's own text, and what the run handed the device back in.
        private var notes: [String] {
            var lines: [String] = []
            if let survivedRunnerFailure {
                lines.append("⚠ the runner reported a failure and this report survived it — every route above is what the run actually followed: \(survivedRunnerFailure)")
            }
            if let handback, !handback.notes.isEmpty {
                lines += (lines.isEmpty ? [] : [""]) + handback.notes
            }
            if let deviceNote {
                lines += (lines.isEmpty ? [] : [""]) + [deviceNote]
            }
            if let setup {
                lines += (lines.isEmpty ? [] : [""]) + setup.lines
            }
            return lines
        }
    }
}
