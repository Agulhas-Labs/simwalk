//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk inspect --device <udid|name> --app <bundle id> [--match <text>]` — the screen a running app is on right now, in the form `bundle screen` serves a captured one, with no walkbook and no capture bundle (SimWalk#49).
///
/// **It reads the device as it stands and changes nothing it does not put back.** A device that is not booted is refused rather than booted, and an app that is not running is refused rather than launched — a boot or a launch would serve a screen nobody left the app on. The XCUITest session still switches the device's accessibility off, so the device is handed back as a walk's is, and the handback rides on the answer or the refusal alike. It holds a walk claim from its appearance read until that handback, so a session's handback leaves the device alone meanwhile (SimWalk#128).
struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Read the screen a running app is on right now — its screen identifier and text, in accessibility order — launching nothing and capturing nothing."
    )

    @Option(name: .long, help: "Simulator name or UDID. Defaults to a booted device another caller has not leased. A device that is not booted is refused, never booted.")
    var device: String?

    @Option(name: .long, help: "A lease token from `simwalk lease acquire`: read the leased device.")
    var lease: String?

    @Option(name: .long, help: "The bundle identifier of the running app to read.")
    var app: String

    /// `.unconditional` for the reason `bundle screen`'s is: `--match -2` is a search for "-2", not `--match` given nothing.
    @Option(name: .long, parsing: .unconditional, help: "Only the text elements whose label or value contains this text (case-insensitive).")
    var match: String?

    @OptionGroup var screenshot: ScreenshotOptions

    func validate() throws {
        if device != nil, lease != nil {
            throw ValidationError("pass --device or --lease, not both — a lease already names its device")
        }
    }

    func run() throws {
        LaunchedBinary.capture()
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) {
            try perform(builds: .standard(), note: StandardStreams.emitError)
        }
    }

    /// The same run with its three effects and the read itself injectable, so the exit code a refusal earns is checked without a simulator.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, read: () throws -> Answer) throws {
        // An unmapped failure here is the runner's own machinery — its build, its run, the file it writes — never a caller's argument.
        try TimedCall.run(tool: LiveScreenQuery.logName, target: app, log: log, emit: emit, emitError: emitError, defaultFailureKind: .runnerFailed, isStdoutPiped: isStdoutPiped, body: read)
    }

    /// Resolves the runner, finds the booted device and the installed app, runs the runner in its live-read mode, reads back the file it wrote, and hands the device back.
    ///
    /// Every child goes through `shell`, and the handback's waits through `pause` and `now` — the seams `WalkDryRun.perform` has. `nonce` is passed the runner, checked back against its file and names that file under `scratch`, which is deleted here whatever came of the run. `firstLaunch` is the read's one preflight, made before its first `simctl` call (SimWalk#136).
    func perform(
        shell: Shell = Shell(),
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: () -> Date = { Date() },
        nonce: () -> String = { UUID().uuidString },
        runner resolveRunner: (() throws -> RunnerSource)? = nil,
        logFileURL: URL = UsageLog.standard().fileURL,
        builds: RunnerBuilds,
        leases: LeaseStore = .standard(),
        scratch: URL = FileManager.default.temporaryDirectory,
        screenshotsDirectory: URL = HomeDirectories.simwalk().appendingPathComponent("screenshots", isDirectory: true),
        firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check(),
        crashReports: URL = HomeDirectories.diagnosticReports(),
        note: (String) -> Void = { _ in }
    ) throws -> Answer {
        // Refused before any `simctl` call when this Xcode's `simctl` would first wait on an administrator password (SimWalk#136).
        try firstLaunch.preflight(shell: shell)
        let run: (String, [String]) throws -> Shell.Result = { try shell.run($0, $1) }
        // Resolved and recorded before the device is looked at, as a walk's is (`WalkCommand.prepare`), so a prune keeps
        // the build this read is about to use.
        let source = try resolveRunner?() ?? RunnerProject.resolve(executable: LaunchedBinary.url, binaryHash: { LaunchedBinary.hash }, run: run)
        try builds.recordUse(of: source)

        let simulator = try Simulator.resolve(device, lease: lease, leases: leases, now: now(), shell: shell)
        guard simulator.isBooted else {
            if device == nil, lease == nil {
                throw SimulatorError.noSimulatorBooted
            }
            throw SimulatorError.notBooted(name: simulator.name, udid: simulator.udid)
        }
        guard try simulator.installedAppPath(bundleID: app, shell: shell) != nil else {
            throw SimulatorError.appNotInstalled(bundleID: app, udid: simulator.udid)
        }
        let runner = RunnerInvocation(projectPath: source.projectPath, derivedDataPath: builds.directory(for: source).path, shell: shell)
        runner.coldBuildNote(commit: source.commit).map(note)
        try runner.build(for: simulator, note: note)

        // Held from the read of the appearance the handback puts back until that handback is made, so a `session end` or
        // `session list` on this device leaves it alone, under a session's own `--lease` too (a walk claim is exempt under
        // no token). A claim and not a lease: a lease would change who may use the device while it is read, and whether two
        // callers share a device is the lease's question. Not before the build, which does not touch the device, so a cold
        // build does not keep a session's handback off a device nothing is changing (SimWalk#128).
        let claim = try LeaseError.takingClaim(udid: simulator.udid, in: leases)
        defer { claim.release() }
        // Read before the runner, so the handback has something to put back; a read stalled behind `xcodebuild -runFirstLaunch` refuses (SimWalk#136).
        let foundAppearance = try DeviceAppearance.read(udid: simulator.udid, run: run)
        let runNonce = nonce()
        let outputURL = scratch.appendingPathComponent("simwalk-inspect-\(runNonce).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let screenshotRequest = try screenshot.request()
        let runnerPNG = scratch.appendingPathComponent("simwalk-inspect-\(runNonce).png")
        defer { try? FileManager.default.removeItem(at: runnerPNG) }
        // Named before the run, as a walk's is, so a refusal reads this run's result bundle (SimWalk#50).
        let resultBundlePath = runner.resultBundlePath(launchedAt: now(), id: runNonce)
        var runnerFailure: Error?
        do {
            try runner.inspect(
                appBundleID: app,
                outputPath: outputURL.path,
                logFilePath: logFileURL.path,
                runnerCommit: source.commit,
                nonce: runNonce,
                screenshotPath: screenshotRequest == nil ? nil : runnerPNG.path,
                resultBundlePath: resultBundlePath,
                on: simulator
            )
        } catch {
            runnerFailure = error
        }
        let read = Result { try LiveScreen.read(at: outputURL, appBundleID: app, nonce: runNonce) }
        let handback = DeviceHandback.perform(udid: simulator.udid, found: foundAppearance, runnerFinished: (try? read.get()) != nil, run: run, pause: pause, now: now)
        return try Self.outcome(
            runnerFailure: runnerFailure,
            handback: handback,
            diagnosingRunnerFailure: { RunnerFailureDiagnosis.read(resultBundlePath: resultBundlePath, shell: shell) },
            readingScreen: { try read.get() },
            match: match,
            // Since the device's boot, so a crash on an earlier boot is not named as why the app is not running now.
            crashReport: { AppCrashReport.latest(bundleID: app, udid: simulator.udid, since: simulator.bootedAt(now: now(), shell: shell), in: crashReports) },
            screenshotOutcome: screenshotRequest.map { request in
                { tree in
                    Self.screenshotOutcome(runnerPNG: runnerPNG, nonce: runNonce, tree: tree, request: request, in: screenshotsDirectory)
                }
            }
        )
    }

    /// The screenshot outcome once the runner has had its say: the image it left at `runnerPNG` fitted and filed as `inspect-<nonce>.png` in `directory`, which is then pruned; or the refusal saying the runner wrote none.
    static func screenshotOutcome(runnerPNG: URL, nonce: String, tree: AXNode, request: ScreenshotFit.Request, in directory: URL) -> ScreenshotFit.Outcome {
        let outcome = ScreenshotOption.outcome(
            png: try? Data(contentsOf: runnerPNG),
            refusal: nil,
            absentReason: "the runner wrote no image",
            tree: tree,
            request: request,
            to: directory.appendingPathComponent("inspect-\(nonce).png")
        )
        ScreenshotOption.prune(directory)
        return outcome
    }

    /// What a live read answers once the runner has had its say — the whole decision and none of the I/O, as `WalkDryRun.outcome` is for a dry run.
    ///
    /// No readable file is a refusal naming the runner's own failure when there was one, with its diagnosis. An app that was not running is a refusal too, but of the device as the caller left it; both carry the handback, the one place a reader of a refused read learns what the session did to the device.
    static func outcome(
        runnerFailure: Error?,
        handback: DeviceHandback?,
        diagnosingRunnerFailure diagnose: () -> RunnerFailureDiagnosis? = { nil },
        readingScreen read: () throws -> LiveScreen,
        match: String?,
        crashReport: () -> AppCrashReport? = { nil },
        screenshotOutcome: ((AXNode) -> ScreenshotFit.Outcome)? = nil
    ) throws -> Answer {
        let screen: LiveScreen
        do {
            screen = try read()
        } catch {
            let refusal = runnerFailure ?? error
            guard let handback else { throw refusal }
            throw WalkCommand.Refusal(underlying: refusal, handback: handback, actor: "this inspect", runnerDiagnosis: runnerFailure == nil ? [] : diagnose()?.lines ?? [])
        }
        let survived = runnerFailure.map { "⚠ the runner reported a failure and this read survived it: \($0)" }
        let query = LiveScreenQuery(
            screen,
            qualifiedBy: (runnerFailure == nil ? [] : ["a runner failure this read survived"]) + (handback?.qualifications ?? []),
            notes: [survived].compactMap(\.self) + (handback?.notes(by: "this inspect") ?? [])
        )
        do {
            return try query.answer(match: match, screenshot: screen.tree.flatMap { tree in screenshotOutcome?(tree) })
        } catch {
            // An app that is not running may have crashed, which sends the caller to a different fix than a launch (SimWalk#243).
            let refusal = if case let LiveScreenError.appNotRunning(bundleID, udid) = error, let report = crashReport() {
                LiveScreenError.appCrashed(bundleID: bundleID, udid: udid, report: report)
            } else {
                error
            }
            guard let handback else { throw refusal }
            throw WalkCommand.Refusal(underlying: refusal, handback: handback, actor: "this inspect")
        }
    }
}
