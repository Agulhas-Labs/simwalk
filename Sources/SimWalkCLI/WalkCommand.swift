//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver
import SimWalkMCP

/// `simwalk walk <walkbook.json> --output <bundle.simwalk>` — runs a walk and writes its capture bundle.
///
/// The orchestration face of Brief §2.1: validate the plan, get a device, confirm the app is really there, identify the build about to be walked, build the runner once, run it, and report what came back. Everything it drives — `simctl`, `xcodebuild` — it drives rather than reimplements (§7.5).
///
/// **It refuses before it walks, wherever refusing is cheaper than discovering.** An invalid walkbook, a missing device and an app that is not installed are all knowable in under a second, and each would otherwise surface as a bundle full of unreachable screens blaming the walkbook for the environment. So are an `--output` that already holds something and a binary with no runner of its own — both refused before anything boots, the first because the bundle left there would otherwise be read back as this walk's.
struct WalkCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "walk",
        abstract: "Run a walkbook against a simulator, or a physical iPhone or iPad, and write a capture bundle."
    )

    @Argument(help: "Path to a walkbook JSON file.")
    var walkbook: String

    @Option(name: .shortAndLong, help: "Where to write the capture bundle (a directory ending in .simwalk, which is added when it is missing and nothing exists at the path) — or, with --dry-run, the route-probe report (a .json file). Either must not exist yet.")
    var output: String

    @Option(name: .long, help: "Simulator name or UDID. Defaults to a booted device, else the newest available — never one another caller has leased. A walk reboots only a device leased to it, named by UDID, or booted by the walk.")
    var device: String?

    @Option(name: .long, help: "A lease token from `simwalk lease acquire`: walk the leased device, which is this walk's to reboot.")
    var lease: String?

    @Option(name: .long, help: "An .app bundle to install before walking. Omit when the app is already installed.")
    var appPath: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Walk only these screen ids, in walkbook order. The bundle records the subset as the plan it ran, so it does not stand in for a full walk."
    )
    var screens: [String] = []

    @Option(
        name: .long,
        help: "How long the screen must hold still before each capture, in milliseconds. Raise it for content that streams in after the screen appears."
    )
    var settle: Int?

    @Flag(
        name: .long,
        help: "Record on every screen's captures when the tree last changed before the capture, at the cadence it was read. A screen asks for it alone with \"motion\": true."
    )
    var motion = false

    @Flag(
        name: .long,
        help: "Keep UIKit animations on in the app under walk. A simulator walk switches them off by default so screens settle sooner; a walk that records motion keeps them on."
    )
    var animations = false

    @Flag(
        name: .long,
        help: "Boot a device SimWalk created with every launchd service on. Without it, a device a `simwalk lease acquire --clone-from` lease created boots with the services the app at --app-path does not need switched off."
    )
    var stock = false

    @Option(name: .long, help: "Physical device only: the Apple signing team ID the runner is built under. Required with a physical --device or a lease on one; refused on a simulator walk.")
    var team: String?

    @Option(name: .long, help: "Physical device only: the runner's bundle identifier, when the default is not one your team can sign. Refused on a simulator walk.")
    var runnerBundleId: String?

    @Flag(
        name: .long,
        help: "Follow every screen's route against the booted app and report each step that no longer lands, capturing nothing. Writes a route-probe report to --output; exits 2 when any route drifted."
    )
    var dryRun = false

    @Flag(name: .long, help: "Write the full result file: every state's artefacts and the routes taken, uncapped.")
    var verbose = false

    /// What a dry run is logged as — `SimWalkTool.walkDryRunLogName`, which the MCP face's `dryRun` logs under too, so `simwalk usage` prices a probe apart from the walks it is minutes cheaper than.
    static var dryRunLogName: String {
        SimWalkTool.walkDryRunLogName
    }

    /// Refuses a quiet period the runner would discard, rather than walking under a threshold nobody asked for.
    ///
    /// `--settle 0` and `--settle -1` both fell through the runner's `milliseconds > 0` guard to the 250ms default: the walk ran, the bundle was written, and nothing anywhere said the flag had been ignored. Same class as the state axes a walkbook now refuses — an input that is neither honoured nor rejected is the silent-discard failure this tool exists to not have.
    func validate() throws {
        if device != nil, lease != nil {
            throw ValidationError("pass --device or --lease, not both — a lease already names its device")
        }
        if verbose, dryRun {
            throw ValidationError("--verbose shapes a walk's result file, and a dry run writes none — drop one of them")
        }
        if motion, dryRun {
            throw ValidationError("--motion records what each capture's watch saw, and a dry run captures nothing — drop one of them")
        }
        guard let settle else { return }
        guard settle > 0 else {
            throw ValidationError("--settle takes a quiet period in milliseconds greater than zero; \(settle) would be discarded and the walk would run at the default instead")
        }
    }

    func run() throws {
        LaunchedBinary.capture()
        // A SIGTERM or a Ctrl-C ends the run `failed` / `cancelled` before the signal ends the process as it would have.
        let cancellation = Cancellation()
        let signals = TerminationSignals(cancelling: cancellation)
        defer { withExtendedLifetime(signals) {} }
        let telemetry = telemetry(cancellation: cancellation)
        guard dryRun else {
            try runServing(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped, answering: { try walked(builds: .standard(), leases: .standard(), telemetry: telemetry, animationsLibrary: Self.standardAnimationsLibrary(), note: StandardStreams.emitError) })
            return
        }
        try runDryRun(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) {
            try probed(builds: .standard(), leases: .standard(), telemetry: telemetry, animationsLibrary: Self.standardAnimationsLibrary(), note: StandardStreams.emitError)
        }
    }

    /// The dry run itself: refuses a dry run on a device, and a device-only flag on a simulator, before the probe boots anything.
    ///
    /// Shared by the CLI's `run()` and the MCP face's ``answer(environment:cancellation:shell:builds:leases:)`` so a test can drive the refusal through the entry both take.
    ///
    /// `firstLaunch` is the dry run's one preflight, made before its first `simctl` call (SimWalk#136).
    func probed(shell: Shell = Shell(), runner resolveRunner: (() throws -> RunnerSource)? = nil, builds: RunnerBuilds, leases: LeaseStore, telemetry: WalkTelemetry? = nil, firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check(), animationsLibrary: AnimationsLibrary? = nil, note: (String) -> Void = { _ in }) throws -> WalkDryRun.Outcome {
        _ = try target(shell: shell, leases: leases, firstLaunch: firstLaunch)
        return try WalkDryRun.perform(self, shell: shell, runner: resolveRunner, builds: builds, leases: leases, telemetry: telemetry, firstLaunch: firstLaunch, animationsLibrary: animationsLibrary, note: note)
    }

    /// What this run writes about itself: the progress file `<session>.json` beside the usage log, and a walk's result file beside that — a dry run writes none (`Docs/SIMWALK-PROGRESS.md` §1).
    ///
    /// The session is `CLAUDE_CODE_SESSION_ID` — the MCP server and the walk it serves are one process — and `default` without one; the directory is the usage log's, so `SIMWALK_USAGE_LOG` moves both. A run that starts while another of the session's is alive writes `<session>.2.json` instead, and so on: the telemetry holds a ``ProgressClaim`` on its files for as long as it lives (SimWalk#83).
    ///
    /// `cancellation` ends the run `failed` / `cancelled` once it has begun (SimWalk#83).
    func telemetry(environment: [String: String] = ProcessInfo.processInfo.environment, cancellation: Cancellation? = nil) -> WalkTelemetry {
        let claim = ProgressClaim.take(session: environment[Self.sessionVariable], in: UsageLog.standard(environment: environment).directory)
        let writer = ProgressWriter(url: claim.progressURL, clock: { Date() }, pid: ProcessInfo.processInfo.processIdentifier)
        return WalkTelemetry(writer: writer, resultURL: dryRun ? nil : claim.resultURL, verbose: verbose, claim: claim, cancellation: cancellation)
    }

    /// The variable Claude Code names its session by, which names the progress file.
    static var sessionVariable: String {
        "CLAUDE_CODE_SESSION_ID"
    }

    /// A dry run with its three effects and the probe itself injectable — the same seam as `run(log:emit:emitError:walk:)`, so the exit code a drifted route earns is checked without a simulator.
    func runDryRun(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, probe: () throws -> WalkDryRun.Outcome) throws {
        try TimedCall.run(tool: Self.dryRunLogName, target: walkbook, log: log, emit: emit, emitError: emitError, defaultFailureKind: .runnerFailed, isStdoutPiped: isStdoutPiped) {
            try probe().answer()
        }
    }

    /// The same run with its three effects and the walk itself injectable, so the exit code can be checked without a simulator.
    ///
    /// Two review rounds recorded this contract as unpinned, on the grounds that exercising it needs a booted device, an installed app and a two-minute walk. That is true of the *walk*; it is not true of the decision, which is a question about a manifest and nothing else. Separating them is what lets `swift test` hold the half a pipeline actually reads — and the field report that reopened it (SimWalk#1) was about the code, not about the walk.
    ///
    /// The qualification is read from the manifest rather than tracked through the walk, so it is a property of the bundle a later reader would open and not of this process's memory of it — the one exception being a runner failure the bundle survived, which is by definition a fact about the run and not about the file, and is handed to the summary as a qualification for exactly that reason.
    ///
    /// The exit code is no longer computed here: the verdict on the answer's second line names every qualification, and `TimedCall` exits on what that verdict says. A shortfall, an unsettled capture, a chrome-only capture and a survived runner failure all mean "the bundle is honest and qualified"; the verdict names which, and a pipeline that wants to gate on one and not the other reads the manifest it already has.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, walk: () throws -> Outcome) throws {
        try runServing(log: log, emit: emit, emitError: emitError, isStdoutPiped: isStdoutPiped, answering: { try walk().servedAnswer() })
    }

    /// The same, for a walk that may be a device's and so answers with an ``Answer`` and no ``Outcome``; logged as `walk` whichever target it took.
    func runServing(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, answering: () throws -> Answer) throws {
        // An unmapped failure here is the runner's own machinery — including a walk's own file writes,
        // like the temporary walkbook `--screens` narrows to — never a caller's argument.
        try TimedCall.run(tool: "walk", target: walkbook, log: log, emit: emit, emitError: emitError, defaultFailureKind: .runnerFailed, isStdoutPiped: isStdoutPiped, body: answering)
    }

    /// The answer, without the printing — what the MCP face serves, so one verb cannot come to answer differently depending on which face asked.
    ///
    /// Minutes pass inside this call and not a byte of it reaches a stream: the MCP face's stdout carries JSON-RPC only, and a walk that reported progress there would corrupt the protocol for the rest of the session.
    ///
    /// `cancellation` is the MCP client's cancel of this call: it ends the progress file `failed` / `cancelled`, and the walk carries on to its end with the file kept that way.
    ///
    /// `started` hears the claimed progress-file stem and the progress as begun. The claim and the `begin` come first, before the target and the device are resolved, so a bounded MCP server has the walk's handle within milliseconds of the call (`Docs/Reference.md`, "Bounded walks"). A run that nothing else ended — a physical device's, which writes no result, or one refused while its target was resolved — is ended here, by its answer or its refusal.
    ///
    /// `shell`, `builds` and `leases` are the seams a test uses to drive this entry against a fake `devicectl`.
    func answer(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cancellation: Cancellation? = nil,
        started: SimWalkMCPServer.WalkStarted? = nil,
        shell: Shell = Shell(),
        runner resolveRunner: (() throws -> RunnerSource)? = nil,
        builds: RunnerBuilds = .standard(),
        leases: LeaseStore = .standard(),
        animationsLibrary: AnimationsLibrary? = nil
    ) throws -> Answer {
        try WalkStart(telemetry: telemetry(environment: environment, cancellation: cancellation), tool: dryRun ? Self.dryRunLogName : "walk", logPath: UsageLog.standard().fileURL.path, started: started).run { telemetry in
            try dryRun ? probed(shell: shell, runner: resolveRunner, builds: builds, leases: leases, telemetry: telemetry, animationsLibrary: animationsLibrary).answer() : walked(shell: shell, runner: resolveRunner, builds: builds, leases: leases, telemetry: telemetry, animationsLibrary: animationsLibrary)
        }
    }

    /// Boots what the walk needs, runs the runner, hands the device back, and reads back the bundle it wrote.
    ///
    /// Every child goes through `shell`, and the handback's waits through `pause` and `now`, which is what lets a test run this whole sequence against a script and check the part no unit of it can show — that the device is read before the runner and handed back after it, whichever way the runner went.
    ///
    /// `runner` decides which runner to build; `nil` resolves it the way an installed binary does — a test cannot choose the process it runs in, and the test runner is not a binary anything was installed with.
    ///
    /// `logFileURL` is resolved here, at the face, rather than inside the runner: `UsageLog.standard()` is what honours `SIMWALK_USAGE_LOG`, and resolving it once and handing the runner the *file* it names is what keeps the two processes' lines in the same place. A runner computing its own path from a bare `.simwalk` directory would agree with the driver only when nobody had moved the log — which a test always does.
    ///
    /// `builds` is where the runner is built, and a walk writes its record there before the build starts — so a test hands it a scratch directory, never the machine's own.
    ///
    /// `provisioning` makes the slim-boot step for the shell in use: the live one writes the machine's override directory, so a test hands one rooted in its own.
    ///
    /// `firstLaunch` is the walk's one preflight (SimWalk#136): a caller that has already asked it hands it on, so it is not asked twice.
    func performWalk(
        shell: Shell = Shell(),
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: @escaping () -> Date = { Date() },
        nonce: @escaping () -> String = { UUID().uuidString },
        runner resolveRunner: (() throws -> RunnerSource)? = nil,
        logFileURL: URL = UsageLog.standard().fileURL,
        builds: RunnerBuilds,
        leases: LeaseStore,
        telemetry: WalkTelemetry? = nil,
        firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check(),
        provisioning: (Shell) -> SlimWalkProvisioning = { SlimWalkProvisioning(shell: $0) },
        animationsLibrary: AnimationsLibrary? = nil,
        note: (String) -> Void = { _ in }
    ) throws -> Outcome {
        try WalkTelemetry.recording(on: telemetry) {
            let prepared = try prepare(shell: shell, runner: resolveRunner, builds: builds, leases: leases, now: now(), logPath: logFileURL.path, telemetry: telemetry, firstLaunch: firstLaunch, provisioning: provisioning, animationsLibrary: animationsLibrary, note: note)
            defer { Self.discardTemporary(prepared.temporaryWalkbook) }
            // Released once the device is handed back, whichever way the walk went; a `--lease` lease is left to its holder.
            defer {
                prepared.claim.release()
                prepared.lease.release()
            }
            let (book, outputURL, source, simulator, buildHash, runner) = (prepared.book, prepared.outputURL, prepared.source, prepared.simulator, prepared.buildHash, prepared.runner)
            // From here until the runner takes the file over, `xcodebuild` is starting the runner and the app.
            telemetry?.enter(.launching)
            let run: (String, [String]) throws -> Shell.Result = { try shell.run($0, $1) }

            // Read before any state touches it, on the host: what the walk puts back afterwards, and what the
            // state check decides a failed light/dark comparison by. `nil` when it cannot be read, which the
            // check answers by refusing both sides; a read stalled behind `xcodebuild -runFirstLaunch` refuses the walk (SimWalk#136).
            let foundAppearance = try DeviceAppearance.read(udid: simulator.udid, run: run)
            // And the locale it is already in, which the state check needs to tell a discarded locale from one the
            // device already had (SimWalk#18). Nothing to put back: a locale state is a launch argument.
            let foundLocale = DeviceLocale.read(udid: simulator.udid, run: run)
            // The walkbook's setup, made before the runner and handed back after it, whichever way the runner went. A step
            // that fails refuses here, having handed back what the steps before it made. Not made at all under a lease that
            // could no longer be renewed. Each change is recorded on disk before it is made and the record removed once handed
            // back, so a walk killed in between leaves one (SimWalk#63) — which the next walk on the device settles first, setup or
            // not (SimWalk#72, SimWalk#73): a walk that makes none hands it back only on a device it owns, as a setup is made only on one,
            // and only under a lease that still renews, as a setup is (SimWalk#75).
            let journal = DeviceSetupJournal.beside(leases)
            let (made, setupNotMade) = try Self.makeSetup(
                SetupRequest(
                    setup: book.setup,
                    udid: simulator.udid,
                    bundleID: book.appBundleID,
                    owned: DeviceSettle.mayReboot(simulator, requested: device, leased: lease != nil)
                ),
                lease: prepared.lease,
                now: now(),
                journal: journal,
                run: run
            )
            let applied = made?.applied
            // Set by the settle's hook when a status bar override could not be made again after its reboot.
            var statusBarNotReapplied: String?
            // Named by the second pass's runner call, for the diagnosis of that runner's failure — as the first pass's is (SimWalk#70).
            var retryResultBundlePath: String?

            // **A failed runner is not a lost bundle.** `xcodebuild test` exits non-zero for any recorded
            // XCTest failure, and the simulator's pasteboard XPC wedges an app under test for 30s on this
            // toolchain — for reasons entirely outside the app, and outside this tool (SimWalk#3). Thrown
            // here, that took eleven perfectly good captures down with the one screen that stalled, where the
            // Brief's contract is per-screen outcomes. So the failure is held, the bundle is read, and it
            // decides: a readable bundle is the answer and the failure qualifies it; no bundle and the
            // failure is the answer.
            var runnerFailure: Error?
            // Taken just before the runner launches; a bundle whose manifest started earlier is not this walk's.
            let launchedAt = now()
            // Generated fresh per walk and passed the runner below: what tells this walk's bundle from one an
            // overlapping walk of the same build left, which the build hash and `startedAt` slack alone cannot
            // (SimWalk#41) — a second walk launched before this one's runner starts capturing can read this
            // one's bundle, started after the second's own launch.
            let runNonce = nonce()
            // Named before the run, so a refusal reads this run's result bundle rather than searching for the
            // newest (SimWalk#50); the nonce names it, as the dry run's does.
            let resultBundlePath = runner.resultBundlePath(launchedAt: launchedAt, id: runNonce)
            // The first runner alone is handed the progress file and timed as `runMs`: a second pass runs during `matching`, and
            // one that took the file over would write `running` after it.
            do {
                try WalkTelemetry.measure(telemetry, \.runMs) {
                    try runner.walk(
                        walkbookPath: prepared.executedPath,
                        outputPath: outputURL.path,
                        buildHash: buildHash,
                        logFilePath: logFileURL.path,
                        settleMilliseconds: settle,
                        motion: motion,
                        animationsOffLibrary: prepared.animationsOffLibrary,
                        deviceAppearance: foundAppearance,
                        deviceLocale: foundLocale,
                        runnerCommit: source.commit,
                        nonce: runNonce,
                        resultBundlePath: resultBundlePath,
                        progressPath: telemetry?.writer.url.path,
                        on: simulator
                    )
                }
            } catch {
                runnerFailure = error
            }
            telemetry?.takeBack()
            // Read back rather than trusted. The runner wrote it in another process on another machine's
            // filesystem view; reading it here is what turns "the test passed" into "a bundle exists that
            // this build will accept" — and it is the same refusal any later reader would give. Read *before*
            // the handback because it is also the evidence the handback needs: the runner resets the device and
            // only then finalises the manifest, so a finalised bundle means the last reset ran, whatever
            // `xcodebuild` exited with — it exits non-zero for any recorded XCTest failure, on a runner that
            // finished (the SimWalk#19 review). It is *this walk's* bundle because the path was refused above
            // unless empty, and a manifest from another build, another walk's start, or another walk's nonce is
            // refused all the same (SimWalk#41). Reading it touches nothing on the device.
            let read = Result { try Self.bundleWrittenBy(walkLaunchedAt: launchedAt, buildHash: buildHash, nonce: runNonce, at: outputURL) }

            // SimWalk#26: screens with a state refused on appearance are walked again once, after the device is
            // settled — set dark, rebooted, put back. Only with a found appearance to put back, and only over a bundle
            // this walk wrote; on a device that drew what it reported, nothing happens.
            let retry = foundAppearance.flatMap { found in
                (try? read.get()).flatMap { first in
                    AppearanceRetryPass(
                        udid: simulator.udid,
                        found: found,
                        walkbookPath: walkbook,
                        mayReboot: DeviceSettle.mayReboot(simulator, requested: device, leased: lease != nil),
                        buildHash: buildHash,
                        nonce: nonce,
                        // A `simctl status_bar` override does not survive the settle's reboot, so it is made again before the second pass.
                        afterSettle: { statusBarNotReapplied = applied.flatMap { DeviceSetup.reapplyStatusBar($0, udid: simulator.udid, run: run) } },
                        renew: { prepared.lease.renew(now: $0) },
                        walk: { walkbookPath, outputPath, retryNonce in
                            let resultBundlePath = runner.resultBundlePath(launchedAt: now(), id: retryNonce)
                            retryResultBundlePath = resultBundlePath
                            try runner.walk(
                                walkbookPath: walkbookPath,
                                outputPath: outputPath,
                                buildHash: buildHash,
                                logFilePath: logFileURL.path,
                                settleMilliseconds: settle,
                                motion: motion,
                                animationsOffLibrary: prepared.animationsOffLibrary,
                                deviceAppearance: found,
                                deviceLocale: foundLocale,
                                runnerCommit: source.commit,
                                nonce: retryNonce,
                                resultBundlePath: resultBundlePath,
                                on: simulator
                            )
                        },
                        diagnose: { retryResultBundlePath.map { RunnerFailureDiagnosis.read(resultBundlePath: $0, shell: shell).lines } ?? [] }
                    )
                    .perform(after: first, of: book, run: { try shell.run($0, $1, timeout: $2) }, now: now)
                }
            }
            // Read again after a second pass: the fold rewrote the bundle, and what is on disk now is the answer —
            // still under this walk's own nonce, which the fold never changes.
            let final = retry == nil ? read : Result { try Self.bundleWrittenBy(walkLaunchedAt: launchedAt, buildHash: buildHash, nonce: runNonce, at: outputURL) }

            // Handed back whether the runner succeeded or not: the XCUITest session ended either way, its
            // teardown switched the device's accessibility off either way (SimWalk#5), and the runner left the
            // appearance at whatever its last state set. `AccessibilityPreference` carries the measurements —
            // which key decides it, which `defaults` can see it, and why the restore waits for the teardown.
            // After a settle that stopped short the device may be down or wedged mid-boot, and the handback's calls go to it
            // next: each is bounded then, so a wedge ends as a handback that could not put things back — the commands
            // printed — rather than a walk that never answers.
            let handbackRun: (String, [String]) throws -> Shell.Result = { executable, arguments in
                try shell.run(executable, arguments, timeout: retry?.handbackBound)
            }
            let handback = DeviceHandback.perform(
                udid: simulator.udid,
                found: foundAppearance,
                runnerFinished: retry?.lastRunnerFinished ?? ((try? read.get()) != nil),
                run: handbackRun,
                pause: pause,
                now: now
            )

            // The setup handed back last, bounded as the rest of the handback is, and recorded in the manifest when there is
            // one to record it in — the record `bundle inspect` reads a week later.
            let setup = made.map { DeviceSetup.Report(applied: $0.applied, leftover: $0.leftover, statusBarNotReapplied: statusBarNotReapplied, handback: DeviceSetup.handBack($0.applied, udid: simulator.udid, bundleID: book.appBundleID, journal: journal, run: handbackRun)) }
            let recorded = setup.flatMap { report in (try? final.get()).flatMap { try? report.record.write(into: $0) } }

            var outcome = try Self.outcome(
                runnerFailure: runnerFailure,
                handback: retry?.judging(handback) ?? handback,
                appearanceRetry: retry?.report,
                setup: setup,
                setupNotMade: setupNotMade,
                diagnosingRunnerFailure: { RunnerFailureDiagnosis.read(resultBundlePath: resultBundlePath, shell: shell) },
                readingBundle: { try recorded ?? final.get() }
            )
            // A simulator walk measures nothing (SimWalk#67, M4); said on the answer so the absence of figures is not read as none.
            if let measureNote = MeasureOptIn.walkNote(for: book, screens: screens) {
                outcome.measureNote = measureNote
            }
            outcome.animationsNote = Self.animationsNote(for: prepared.animations)
            outcome.deviceNote = prepared.deviceNote
            if prepared.outputSuffixAdded {
                outcome.bundle = outcome.bundle.noting("output: \(outputURL.path) (suffix added)")
            }
            telemetry?.finish(walk: outcome.bundle, logPath: logFileURL.path)
            outcome.resultPath = telemetry?.writer.current.resultPath
            return outcome
        }
    }

    /// Everything a walk and a dry run do before the runner runs, in the order a walk has always done it: the walkbook loaded, the output refused unless fresh, the runner resolved and its use recorded, the device booted, the app found and hashed, the walkbook to execute written, and the runner built.
    ///
    /// One sequence for both modes, so a dry run refuses what a walk refuses and at the same point — before anything boots wherever that is knowable — and differs only in which artefact the output path has to be fresh for.
    ///
    /// **The caller owns the temporary walkbook once this returns**; if the build throws, it is deleted here, because the caller never gets a `Prepared` to delete it from. `scratch` is where it is written — the system's temporary directory, or a test's own, which is the only way to see it gone.
    func prepare(
        shell: Shell,
        runner resolveRunner: (() throws -> RunnerSource)?,
        builds: RunnerBuilds,
        leases: LeaseStore,
        now: Date,
        scratch: URL = FileManager.default.temporaryDirectory,
        logPath: String? = nil,
        telemetry: WalkTelemetry? = nil,
        firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check(),
        provisioning: (Shell) -> SlimWalkProvisioning = { SlimWalkProvisioning(shell: $0) },
        animationsLibrary: AnimationsLibrary? = nil,
        note: (String) -> Void = { _ in }
    ) throws -> Prepared {
        telemetry?.begin(tool: dryRun ? Self.dryRunLogName : "walk", logPath: logPath)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: walkbook))
        // The screens the run executes, counted as `walkbookToExecute` narrows them; left out when the subset is refused, which it is below.
        telemetry?.plan(screens: screens.isEmpty ? book.screens.count : (try? WalkbookSubset.narrow(book, to: screens))?.screens.count)
        // Checked here, before anything is booted or built. The runner enforces it too — it is the
        // writer — but discovering it there costs a build, a boot and a launch to learn something
        // knowable from the argument itself.
        // A name without `.simwalk` is completed when nothing is there, and the walk's answer says so (SimWalk#107); a dry run writes a different artefact and keeps the path as given.
        let requested = URL(fileURLWithPath: output).standardizedFileURL
        let resolution = dryRun ? CaptureBundleLayout.Resolution(url: requested, suffixAdded: false) : CaptureBundleLayout.resolvingOutput(requested)
        let outputURL = resolution.url
        // And the path must be empty (the SimWalk#19 review): the runner would refuse a non-empty one in
        // its own process, and the artefact left there would then be read back below as this run's.
        if dryRun {
            try RouteProbeReport.requireFresh(outputURL)
        } else {
            try CaptureBundleWriter.requireFresh(outputURL)
        }

        // A `--screens` id the walkbook lacks is knowable now, so it is refused before the library is built or the runner resolved (SimWalk#154).
        if !screens.isEmpty {
            _ = try WalkbookSubset.narrow(book, to: screens)
        }

        let run: (String, [String]) throws -> Shell.Result = { try shell.run($0, $1) }
        // The runner installed with this binary, never the live checkout (SimWalk#16), built in a directory
        // keyed to what it builds so no other source's walk can share or overwrite its products. Resolved
        // before anything is booted or installed: a binary with no runner of its own is a refusal knowable
        // from the machine, and finding it out after a boot and an install costs both for nothing.
        let source = try resolveRunner?() ?? RunnerProject.resolve(executable: LaunchedBinary.url, binaryHash: { LaunchedBinary.hash }, run: run)
        // Recorded the moment the runner is resolved, so a prune can tell what this directory builds and that a
        // walk is using it now — and so keeps the build, its snapshot and the binding naming it through the boot
        // and the install still to come, which take tens of seconds. A build directory's name is a hash nothing
        // can read back (SimWalk#22).
        try builds.recordUse(of: source)

        // The animations-off library, built after the cheaper refusals above and before anything is booted: a walk that cannot have it is refused while that is cheap (SimWalk#154).
        let animations = try animationsPlan(for: book, library: animationsLibrary)

        // The device, a lease on it and the walk's claim, taken before anything touches the device: a walk that names no lease
        // takes one of its own on the device it resolves, so no other simwalk session can take that device for the length of the walk.
        // Refused before any `simctl` call when this Xcode's `simctl` would first wait on an administrator password (SimWalk#136);
        // already asked, and not asked again, when the route check's `simctl list` came first.
        try firstLaunch.preflight(shell: shell)
        let held = try HeldDevice.take(for: self, shell: shell, leases: leases, now: now)
        let simulator = held.simulator
        telemetry?.resolved(simulator, app: book.appBundleID)
        // Everything after the acquisition releases a lease the walk took, and its claim, if it refuses: the caller only gets a
        // `Prepared` to release them from once this returns.
        do {
            // A setup changes device-wide state — a grant, the status bar, an accessibility setting — so it is made only on a
            // device this walk owns, the rule a settle's reboot follows; refused here, before the boot, so nothing is touched.
            if book.setup?.changesDevice == true, !DeviceSettle.mayReboot(simulator, requested: device, leased: lease != nil) {
                throw DeviceSetupError.notOwned(udid: simulator.udid)
            }
            let deviceNote = try provisioning(shell).boot(simulator, createdByWalk: held.lease.createdDevice, stockRequested: stock, appPath: appPath) { device in
                try WalkTelemetry.segment(telemetry, .booting, \.bootMs) { try device.boot(shell: shell) }
            }
            if let appPath {
                try WalkTelemetry.segment(telemetry, .installing, \.installMs) { try simulator.install(appPath: appPath, shell: shell) }
            }
            guard let installedPath = try simulator.installedAppPath(bundleID: book.appBundleID, shell: shell) else {
                throw SimulatorError.appNotInstalled(bundleID: book.appBundleID, udid: simulator.udid)
            }
            // Hashed from the installed bundle, so the manifest attests to the binary that was walked
            // rather than to whatever a caller believed it installed.
            let buildHash = try AppBuildIdentity.hash(ofAppAt: installedPath)

            // A subset is executed as its own walkbook, written beside nothing and hashed as itself, so the
            // manifest names the plan that ran. Passing the full walkbook and filtering inside the runner
            // would produce a bundle claiming a twelve-screen plan while holding three.
            let executed = try Self.walkbookToExecute(book, at: walkbook, screens: screens, in: scratch)

            let runner = RunnerInvocation(projectPath: source.projectPath, derivedDataPath: builds.directory(for: source).path, shell: shell)
            runner.coldBuildNote(commit: source.commit).map(note)
            do {
                try WalkTelemetry.segment(telemetry, .building, \.buildMs) { try runner.build(for: simulator) }
            } catch {
                Self.discardTemporary(executed.temporaryURL)
                throw error
            }
            return Prepared(
                book: book,
                outputURL: outputURL,
                outputSuffixAdded: resolution.suffixAdded,
                source: source,
                simulator: simulator,
                buildHash: buildHash,
                executedPath: executed.path,
                temporaryWalkbook: executed.temporaryURL,
                runner: runner,
                lease: held.lease,
                claim: held.claim,
                deviceNote: deviceNote,
                animations: animations?.decision,
                animationsOffLibrary: animations?.path
            )
        } catch {
            held.release()
            throw error
        }
    }

    /// What a walk or a dry run makes of the walkbook's `setup` before its runner, with `lease` renewed first: the setup made, or — when it makes none — a setup record an earlier walk left settled (SimWalk#72, SimWalk#73); and `notMade`, the qualification that says why a change was not made.
    ///
    /// **Either changes device-wide state, so either waits on the lease.** A lease that can no longer be renewed keeps nobody off the device, which may by now be another session's: the setup is not made, and a leftover is not handed back but left where it is, each said in the same words (SimWalk#75). A walk that makes no setup renews only where it would hand back — on a device it `owns`, with a record on it — so a walk with nothing left on its device renews nothing and its answer is unchanged.
    static func makeSetup(
        _ request: SetupRequest,
        lease: WalkLease,
        now: Date,
        journal: DeviceSetupJournal,
        run: (String, [String]) throws -> Shell.Result
    ) throws -> (made: DeviceSetup.Made?, notMade: String?) {
        let setup = request.setup
        let udid = request.udid
        let bundleID = request.bundleID
        let owned = request.owned
        if let setup, setup.changesDevice {
            guard let reason = lease.renew(now: now) else {
                return try (DeviceSetup.apply(setup, udid: udid, bundleID: bundleID, journal: journal, run: run), nil)
            }
            return try (DeviceSetup.settleLeftover(udid: udid, owned: false, leaseLapsed: true, journal: journal, run: run), leaseNotRenewed(lease, reason: reason, so: "the setup was not made"))
        }
        let lapsed = owned && journal.hasRecord(onDevice: udid) ? lease.renew(now: now) : nil
        let made = try DeviceSetup.settleLeftover(udid: udid, owned: owned && lapsed == nil, leaseLapsed: lapsed != nil, journal: journal, run: run)
        guard let lapsed else { return (made, nil) }
        // The suffix is true only of a record this walk left in place for want of the lease: a still-running walk's was never this walk's to hand back.
        let lapsedInPlace = if case .leftInPlace(_, .leaseLapsed, _)? = made?.leftover {
            true
        } else {
            false
        }
        return (made, leaseNotRenewed(lease, reason: lapsed, so: lapsedInPlace ? "the setup an earlier walk left was not handed back" : nil))
    }

    private static func leaseNotRenewed(_ lease: WalkLease, reason: String, so consequence: String?) -> String {
        "the lease on \(lease.udid) could not be renewed: \(reason)" + (consequence.map { "; \($0)" } ?? "")
    }

    /// What a walk answers once the runner has had its say: the bundle when one was written and is readable, and the runner's own failure when it was not.
    ///
    /// Separated from `performWalk` because it is the whole decision and none of the I/O — the half that has to be checkable without a simulator, a build and a two-minute walk. The runner's error is preferred over the bundle's when both failed, because "the walk could not run" explains "there is no bundle here" and the reverse explains nothing.
    ///
    /// **A refusal still carries the handback.** A walk with no readable bundle ended an XCUITest session all the same, so the device was switched off all the same, and the line saying whether it was put back — with the command when it was not — is the one a reader of that refusal most needs.
    ///
    /// **And what the runner's result bundle says about its failure** (SimWalk#50), asked of `diagnose` only when a runner failure is the refusal — never for a walk that answered with a bundle, so a run that worked prints nothing new.
    static func outcome(
        runnerFailure: Error?,
        handback: DeviceHandback?,
        appearanceRetry: AppearanceRetryPass.Report? = nil,
        setup: DeviceSetup.Report? = nil,
        setupNotMade: String? = nil,
        diagnosingRunnerFailure diagnose: () -> RunnerFailureDiagnosis? = { nil },
        readingBundle read: () throws -> CaptureBundle
    ) throws -> Outcome {
        let bundle: CaptureBundle
        do {
            bundle = try read()
        } catch {
            let refusal = runnerFailure ?? error
            guard let handback else { throw refusal }
            throw Refusal(
                underlying: refusal,
                handback: handback,
                appearanceRetry: appearanceRetry?.notes(udid: handback.accessibility.udid, recorded: false) ?? [],
                setup: setup,
                setupNotMade: setupNotMade,
                runnerDiagnosis: runnerFailure == nil ? [] : diagnose()?.lines ?? []
            )
        }
        return Outcome(
            bundle: bundle,
            survivedRunnerFailure: runnerFailure.map { String(describing: $0) },
            handback: handback,
            appearanceRetry: appearanceRetry,
            setup: setup,
            setupNotMade: setupNotMade
        )
    }

    /// The bundle at `url`, provided it is this walk's own: its manifest started no earlier than the walk launched its runner, was written against `buildHash`, and carries `nonce` — the value this walk's host generated and passed its own runner, which catches what the build hash and the start-time slack alone miss: two overlapping walks of the same build to the same path, each able to read the other's bundle (SimWalk#41), the way `RouteProbeReport.read` closes the same gap for a dry run (SimWalk#36).
    ///
    /// A second's slack on the start, because the manifest rounds to the millisecond and the runner's clock is the simulator's, not this process's.
    static func bundleWrittenBy(walkLaunchedAt launchedAt: Date, buildHash: String, nonce: String, at url: URL) throws -> CaptureBundle {
        let bundle = try CaptureBundle.read(at: url)
        let problems = CaptureBundleError.problems(bundle.manifest, walkLaunchedAt: launchedAt, buildHash: buildHash, nonce: nonce)
        guard problems.isEmpty else {
            throw CaptureBundleError.bundleFromAnotherWalk(path: url.path, problems: problems)
        }
        return bundle
    }

    /// The walkbook the runner is handed: the original's own file when every screen is walked, or a subset written to a temporary one.
    ///
    /// The original file is passed through untouched in the common case rather than re-serialised, so a walk of the whole walkbook hashes exactly as it always did and nothing about `--screens` existing changes a run that does not use it.
    static func walkbookToExecute(_ book: Walkbook, at originalPath: String, screens: [String], in scratch: URL = FileManager.default.temporaryDirectory) throws -> (path: String, temporaryURL: URL?) {
        guard !screens.isEmpty else {
            return (URL(fileURLWithPath: originalPath).standardizedFileURL.path, nil)
        }
        let narrowed = try WalkbookSubset.narrow(book, to: screens)
        let url = scratch
            .appendingPathComponent("simwalk-subset-\(UUID().uuidString)")
            .appendingPathExtension("json")
        // The bytes only have to decode — `WalkbookIdentity` hashes the decoded walkbook's canonical
        // encoding, not this file, so formatting here cannot change the plan's identity.
        try JSONEncoder().encode(narrowed).write(to: url)
        return (url.path, url)
    }

    static func discardTemporary(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension WalkCommand {
    /// What a walk produced: the bundle, and the two things a reader has to know that the bundle cannot say.
    ///
    /// The bundle is the answer and it stays the answer. What it cannot carry is a fact about the *run* rather than the walk — that `xcodebuild` reported a failure the bundle outlived, and what the walk handed the device back in. Both are printed under the summary and neither is written into a manifest, because a manifest attests to a walk and these are not part of one.
    struct Outcome {
        var bundle: CaptureBundle
        /// The result file the run's progress file names once it ended — `nil` when nobody was watching or it could not be written.
        var resultPath: String?
        /// That a simulator walk measured nothing for the screens that ask (`MeasureOptIn.deviceOnlyNote`); `nil` when none did.
        var measureNote: String?
        /// What a simulator walk did about UIKit animations (``WalkCommand/animationsNote(for:)``); `nil` when they were asked for or nothing was decided.
        var animationsNote: String?
        /// Whether SimWalk slimmed the device it booted, and how that was read back; `nil` when it decided nothing.
        var deviceNote: String?
        /// The runner's own failure, when a readable bundle was on disk in spite of it.
        let survivedRunnerFailure: String?
        /// What the walk put back on the device — every walk has one; `nil` only where a caller supplied a bundle without a walk.
        let handback: DeviceHandback?
        /// What came of screens that had a state refused on appearance (SimWalk#26); `nil` when none did.
        ///
        /// The manifest records the settle whichever way it went — folded, stopped short, or with nothing to fold. This carries what a file cannot: the qualification on this run's verdict, and the command that leaves the device usable.
        let appearanceRetry: AppearanceRetryPass.Report?
        /// The walkbook's setup — what was made and what the handback put back, and a leftover another walk left, settled first; `nil` when the walkbook made none and there was no leftover (SimWalk#73).
        let setup: DeviceSetup.Report?
        /// Why the walkbook's setup was not made, or a setup an earlier walk left was not handed back — the walk's lease could not be renewed before it (``WalkCommand/makeSetup(_:lease:now:journal:run:)``); `nil` when it was made or handed back, or there was none.
        let setupNotMade: String?

        init(
            bundle: CaptureBundle,
            survivedRunnerFailure: String? = nil,
            handback: DeviceHandback? = nil,
            appearanceRetry: AppearanceRetryPass.Report? = nil,
            setup: DeviceSetup.Report? = nil,
            setupNotMade: String? = nil
        ) {
            self.bundle = bundle
            self.survivedRunnerFailure = survivedRunnerFailure
            self.handback = handback
            self.appearanceRetry = appearanceRetry
            self.setup = setup
            self.setupNotMade = setupNotMade
        }

        /// Whether the call worked and the answer is qualified — the exit-2 question, asked of the verdict rather than of a second copy of its reasoning.
        var isQualified: Bool {
            answer().verdict.isQualified
        }

        /// The whole answer a caller reads: the bundle's, qualified by what the run knows and the file cannot.
        func answer() -> Answer {
            // The handback's qualifications ride the verdict, not only the notes: a device left unable to run
            // the next accessibility suite, or in an appearance it was not found in, is exactly what an agent
            // reading the verdict line has to act on.
            CaptureBundleSummary(
                bundle,
                qualifiedBy: (survivedRunnerFailure == nil ? [] : ["a runner failure this bundle survived"])
                    + [appearanceRetry?.qualification].compactMap(\.self)
                    + (handback?.qualifications ?? [])
                    + (setup?.qualifications ?? [])
                    + [setupNotMade].compactMap(\.self),
                notes: notes
            ).answer()
        }

        /// ``answer()`` as a face serves it: the result file, when the run wrote one, named on one trailing residue line (`Docs/SIMWALK-PROGRESS.md` §4).
        func servedAnswer() -> Answer {
            Self.naming(result: resultPath, in: answer())
        }

        /// `answer` with `result: <path>` as its last residue line when there is a `path`, and nothing else changed — after the notes, which ``CaptureBundleSummary/answer(appending:)`` would put the line ahead of.
        static func naming(result path: String?, in answer: Answer) -> Answer {
            if let path {
                return Answer(header: answer.header, verdict: answer.verdict, residue: answer.residue + ["result: \(path)"], weighing: answer.weighing)
            }
            return answer
        }

        /// Lines printed under the residue: the failure's own text, and what the walk handed the device back in — whose qualifications, if any, are on the verdict as well.
        private var notes: [String] {
            var lines: [String] = []
            if let survivedRunnerFailure {
                lines.append("⚠ the runner reported a failure and this bundle survived it — every screen above is what the run actually recorded, and the screens it never reached say so: \(survivedRunnerFailure)")
            }
            // The device the walk settled, as the handback names it — not the one the manifest records, which is
            // the runner's own reading and agrees in every real walk, but is not what the host acted on.
            if let appearanceRetry {
                lines += appearanceRetry.notes(
                    udid: handback?.accessibility.udid ?? bundle.manifest.device.udid,
                    recorded: bundle.manifest.appearanceSettle != nil
                )
            }
            if let handback, !handback.notes.isEmpty {
                lines += (lines.isEmpty ? [] : [""]) + handback.notes
            }
            if let measureNote {
                lines += (lines.isEmpty ? [] : [""]) + [measureNote]
            }
            if let animationsNote {
                lines += (lines.isEmpty ? [] : [""]) + [animationsNote]
            }
            if let deviceNote {
                lines += (lines.isEmpty ? [] : [""]) + [deviceNote]
            }
            // The manifest's record prints with the bundle's own residue; only a record that could not be written is said here.
            if let setup, bundle.manifest.deviceSetup == nil {
                lines += (lines.isEmpty ? [] : [""]) + setup.lines + ["⚠ the setup above is not recorded in the bundle's manifest — rewriting it failed"]
            }
            return lines
        }
    }
}

extension WalkCommand {
    /// What `prepare` leaves ready for the runner: the plan, where its output goes, the runner built, and the device with the app on it.
    struct Prepared {
        /// The walkbook as the caller named it — every screen, whatever `--screens` narrowed the executed one to.
        let book: Walkbook
        let outputURL: URL
        /// Whether `outputURL` is the caller's `--output` with `.simwalk` added (SimWalk#107), which the answer says.
        let outputSuffixAdded: Bool
        let source: RunnerSource
        let simulator: Simulator
        /// The installed app's hash, which the runner writes into what it produces.
        let buildHash: String
        /// The walkbook file the runner is handed — the original, or the `--screens` subset.
        let executedPath: String
        /// The subset's temporary file, for the caller to delete; `nil` when the original is executed.
        let temporaryWalkbook: URL?
        let runner: RunnerInvocation
        /// The lease the walk runs under — its own, taken on the device it resolved, or the `--lease` it was handed — which the caller releases once the walk ends (``WalkLease/release()`` leaves a handed-in one be).
        let lease: WalkLease
        /// The walk's mark on the device, which no lease token exempts from a handback (SimWalk#128); the caller releases it with the lease.
        let claim: WalkClaim
        /// The line the answer carries about how the device was booted; `nil` when nothing was decided.
        let deviceNote: String?
        /// What the walk decided about UIKit animations (SimWalk#154); `nil` when no library was offered, which launches the app untouched.
        let animations: AnimationsOptIn.Decision?
        /// The library to insert into the app's launch, when the decision is `.off`.
        let animationsOffLibrary: String?
    }
}

extension WalkCommand {
    /// A walk that produced no readable bundle, carrying what it handed the device back in.
    ///
    /// The underlying error is the answer; the handback rides with it because the session that failed still switched the device's accessibility off, and the refusal is the only thing a reader of that walk will see.
    struct Refusal: Error, CustomStringConvertible {
        let underlying: Error
        let handback: DeviceHandback
        /// What an appearance retry came to, when the walk made one — above all a fold that failed and could not be undone, whose line is the only place the answer says where the first attempt was set aside.
        var appearanceRetry: [String] = []
        /// The walkbook's setup and its handback — made before the runner, so put back whichever way the runner went.
        var setup: DeviceSetup.Report?
        /// Why the walkbook's setup was not made, or a leftover not handed back — the lease could not be renewed before it; `nil` when nothing was refused.
        var setupNotMade: String?
        /// What the failed runner's result bundle says — its path, the activities before the failure, where the hierarchy went (SimWalk#50) — printed a line each under the rest, because the titles are a list and read as one.
        var runnerDiagnosis: [String] = []

        var description: String {
            let underlyingDescription = String(describing: underlying)
            let notes = appearanceRetry + handback.notes + (setup?.lines ?? []) + [setupNotMade].compactMap(\.self)
            // A multi-line description (`CaptureBundleError.bundleFromAnotherWalk`'s bulleted problem list, say)
            // already ends its own thought on its last bullet — joining a note onto it with " — " reads as
            // though the note were part of that bullet. A single-line description has no such line to land on,
            // so it keeps the inline join it always had.
            let summary = underlyingDescription.contains("\n")
                ? ([underlyingDescription] + notes).joined(separator: "\n")
                : ([underlyingDescription] + notes).joined(separator: " — ")
            return ([summary] + runnerDiagnosis).joined(separator: "\n  ")
        }
    }
}

extension WalkCommand.Refusal: UsageFailureClassifiable {
    /// This is thrown only once the runner has already run and left no readable bundle behind (``WalkCommand/outcome(runnerFailure:handback:readingBundle:)``), no readable route-probe report (``WalkDryRun/outcome(runnerFailure:handback:readingReport:)``), or no live read (``InspectCommand/outcome(runnerFailure:handback:diagnosingRunnerFailure:readingScreen:match:)``): `underlying` is always either a `RunnerError` from the runner itself, or a `CaptureBundleError`, `RouteProbeError` or `LiveScreenError` from reading back what that same runner just wrote — never a `WalkbookLoadError`, a `SimulatorError` or anything else refused before the runner was invoked, which throw raw and never reach this type.
    ///
    /// Those mean the runner, not a caller's argument, so this does not defer to `underlying`'s own kind — which would answer `.inputRefused` for the `CaptureBundleError` half by that type's own (differently-sited) default. **The one exception is a live read of an app that was not running**: the runner read the device correctly and the refusal is the device as the caller left it, which `LiveScreenError` itself classifies as `.inputRefused`; it rides in a refusal only so the handback reaches the reader.
    var usageFailureKind: UsageFailureKind {
        (underlying as? LiveScreenError).map(\.usageFailureKind) ?? .runnerFailed
    }
}

extension WalkCommand {
    /// What ``makeSetup(_:lease:now:journal:run:)`` is asked to make, and for whom: the walkbook's `setup`, the device and app it is for, and whether the walk `owned` the device (it may reboot it).
    struct SetupRequest {
        let setup: Walkbook.Setup?
        let udid: String
        let bundleID: String
        let owned: Bool
    }
}
