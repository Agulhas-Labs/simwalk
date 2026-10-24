//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk session start --app <bundle id> (--lease <token> | --device <udid>) [--state <json>]` — launches the app under a resident runner and prints the session's id.
///
/// A physical iPhone or iPad is ``performOnDevice(_:id:effects:note:)`` (SimWalk#116).
///
/// **The device must be the caller's**: taken by lease, or named by UDID. A session holds the device's XCUITest session until it ends or goes idle, which is not a thing to do to a device picked by name or by default.
struct SessionStartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Launch the app under a resident runner on a device you own, and print the session id."
    )

    @Option(name: .long, help: "The bundle identifier of the installed app to launch.")
    var app: String

    @Option(name: .long, help: "The UDID of a booted simulator that is yours, or of a paired physical iPhone or iPad (then --team is required), which the session leases for itself.")
    var device: String?

    @Option(name: .long, help: "A lease token from `simwalk lease acquire`: run on the leased device.")
    var lease: String?

    @Option(name: .long, help: "A capture state as JSON (a walkbook's `states` entry) to launch the app under.")
    var state: String?

    @Option(name: .long, help: "Physical device only, and required there: the Apple signing team ID the runner is built under.")
    var team: String?

    @Option(name: .long, help: "Physical device only: the runner's bundle identifier, when the default is not one your team can sign.")
    var runnerBundleId: String?

    @Flag(name: .long, help: "Keep UIKit animations on in the app. A simulator session switches them off by default so screens settle sooner.")
    var animations = false

    func validate() throws {
        guard (device == nil) != (lease == nil) else {
            throw ValidationError("pass --device <udid> or --lease <token> — exactly one; a session runs only on a device you own")
        }
    }

    func run() throws {
        LaunchedBinary.capture()
        // A SIGTERM or a Ctrl-C ends the session's progress `failed` / `cancelled` before the signal ends the process, as a walk's does.
        let cancellation = Cancellation()
        let signals = TerminationSignals(cancelling: cancellation)
        defer { withExtendedLifetime(signals) {} }
        try TimedCall.run(tool: "session start", target: app, defaultFailureKind: .runnerFailed) {
            try perform(builds: .standard(), cancellation: cancellation, animationsLibrary: WalkCommand.standardAnimationsLibrary(), note: StandardStreams.emitError)
        }
    }

    /// Resolves the runner, the device and the app as `inspect` does, then starts the session — every effect injectable.
    ///
    /// Writes the session's progress file beside the usage log `environment` names until the runner takes it over (``SessionStartProgress``); `cancellation` ends it `failed` / `cancelled`, and anything thrown ends it `failed`.
    ///
    /// `firstLaunch` is the start's one preflight, made before its first `simctl` call on either path (SimWalk#136).
    func perform(
        shell: Shell = Shell(),
        pause: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: @escaping () -> Date = { Date() },
        id: () -> String = { String(UUID().uuidString.prefix(8)).lowercased() },
        runner resolveRunner: (() throws -> RunnerSource)? = nil,
        builds: RunnerBuilds,
        leases: LeaseStore = .standard(),
        store: LiveSessionStore = .standard(),
        processes: any LiveSessionProcesses = LiveSessionSystemProcesses(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cancellation: Cancellation? = nil,
        deviceHello: ((DeviceSessionBind) throws -> LiveSessionReady)? = nil,
        firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check(),
        animationsLibrary: WalkCommand.AnimationsLibrary? = nil,
        note: (String) -> Void = { _ in }
    ) throws -> Answer {
        // The log `environment` names, resolved once for the progress file, the usage lines and the runner alike, so an injected `SIMWALK_USAGE_LOG` moves them all (SimWalk#196).
        let logFileURL = UsageLog.standard(environment: environment).fileURL
        // Which target, before the simulator path touches anything: a physical device has no progress file, as a device walk has none.
        if let route = try PhysicalDeviceRoute.resolve(device: device, lease: lease, shell: shell, leases: leases, firstLaunch: firstLaunch) {
            let effects = DeviceStartEffects(shell: shell, pause: pause, now: now, runner: resolveRunner, builds: builds, leases: leases, store: store, processes: processes, environment: environment, hello: deviceHello)
            return try performOnDevice(route, id: id(), effects: effects, cancellation: cancellation, note: note)
        }
        for (flag, value) in [("--team", team), ("--runner-bundle-id", runnerBundleId)] where value != nil {
            throw LiveSessionHostError.deviceOnly(flag: flag)
        }
        let progress = SessionStartProgress(environment: environment, logFileURL: logFileURL, cancellation: cancellation)
        do {
            // Refused before any `simctl` call when this Xcode's `simctl` would first wait on an administrator password (SimWalk#136);
            // already asked, and not asked again, when the route check's `simctl list` came first.
            try firstLaunch.preflight(shell: shell)
            let run: (String, [String]) throws -> Shell.Result = { try shell.run($0, $1) }
            let launchState = try state.map(Self.captureState)
            // Built before the device is touched, so a session that cannot have it is refused while that is cheap (SimWalk#154); `--animations` skips it.
            let animationsOffLibrary = try animations ? nil : animationsLibrary.map { try WalkCommand.builtLibrary($0).path }
            let source = try resolveRunner?() ?? RunnerProject.resolve(executable: LaunchedBinary.url, binaryHash: { LaunchedBinary.hash }, run: run)
            try builds.recordUse(of: source)

            let simulator = try Simulator.resolve(device, lease: lease, leases: leases, now: now(), shell: shell)
            if let device, device != simulator.udid {
                throw LiveSessionHostError.deviceNotOwned(requested: device, udid: simulator.udid)
            }
            guard simulator.isBooted else {
                throw LiveSessionHostError.notBooted(name: simulator.name, udid: simulator.udid)
            }
            guard let installedPath = try simulator.installedAppPath(bundleID: app, shell: shell) else {
                throw SimulatorError.appNotInstalled(bundleID: app, udid: simulator.udid)
            }
            // SimWalk#166: an iPhone-only app on an iPad runs in compatibility mode, so refuse before the runner is built. A physical iPad is not checked yet.
            try AppDeviceFamilies.require(bundleID: app, installedAt: installedPath, on: simulator)
            progress.resolved(simulator, app: app)
            let starter = LiveSessionStart(store: store, processes: processes)
            // Held from before the build and the settle until the record is written, so a second start cannot pass the one-session check in between.
            let claim = try starter.claim(udid: simulator.udid)
            defer { claim.release() }
            if let live = starter.liveSession(on: simulator.udid) {
                throw LiveSessionHostError.alreadyRunning(udid: simulator.udid, id: live.id, pid: live.pid)
            }
            let runner = RunnerInvocation(projectPath: source.projectPath, derivedDataPath: builds.directory(for: source).path, shell: shell)
            runner.coldBuildNote(commit: source.commit).map(note)
            try runner.build(for: simulator, note: note)
            progress.launching()

            // Read before anything changes the device: what the runner puts back on every exit and `end` puts back after it.
            let found = try DeviceAppearance.read(udid: simulator.udid, run: run)
            let settled = try launchState.flatMap { try Self.settle(simulator.udid, found: found, to: $0.theme, shell: shell) }
            let sessionID = id()
            let started: (record: LiveSessionRecord, ready: LiveSessionReady)
            do {
                started = try starter.perform(
                    id: sessionID,
                    udid: simulator.udid,
                    launch: LiveSessionLaunch(appBundleID: app, state: launchState),
                    foundAppearance: found,
                    leaseToken: lease,
                    effects: LiveSessionStart.Effects(
                        command: { layout in
                            runner.session(
                                layout: layout,
                                logFilePath: logFileURL.path,
                                runnerCommit: source.commit,
                                idleOverride: environment[LiveSessionIdle.overrideVariable],
                                deviceAppearance: found,
                                progress: progress.claim,
                                animationsOffLibrary: animationsOffLibrary,
                                on: simulator
                            )
                        },
                        diagnose: { layout in RunnerFailureDiagnosis.read(resultBundlePath: layout.resultBundle.path, testID: Self.testID, shell: shell).lines },
                        run: run,
                        pause: pause,
                        now: now,
                        spawned: progress.spawned,
                        recorded: claim.release,
                        isDeviceBusy: { now in
                            LiveSessionAccessibilityHandback.isHeldByAnother(udid: simulator.udid, session: (sessionID, lease), store: store, processes: processes, leases: leases, now: now)
                        },
                        holder: { now in
                            LiveSessionStop.Holder.on(udid: simulator.udid, session: (sessionID, lease), store: store, processes: processes, leases: leases, now: now)
                        }
                    )
                )
            } catch {
                throw Self.handingBack(after: error, settledInto: settled == nil ? nil : launchState?.theme, found: found, udid: simulator.udid, run: run)
            }
            let idle = LiveSessionIdle.timeout(fromOverride: environment[LiveSessionIdle.overrideVariable])
            return Answer(
                header: "live session: app: \(app)  device: \(started.ready.device.name) (\(started.ready.device.osVersion))  animations: \(animationsOffLibrary == nil ? "on" : "off")",
                verdict: .unqualified("session \(sessionID) ready"),
                residue: [
                    "id: \(sessionID)",
                    "read it: simwalk session read \(sessionID) [--match <text>] — prints the screen's hash",
                    "step it: simwalk session step \(sessionID) '<route step json>' [--guard <hash>]",
                    "save it: simwalk session save \(sessionID) --screen <id> --into <walkbook.json> [--expect <identifier>] — before end",
                    "end it: simwalk session end \(sessionID) — it ends itself after \(Int(idle)) s without a request",
                ] + (settled.map { [$0] } ?? []) + (started.ready.notes ?? []).map { "⚠ \($0)" }
            )
        } catch {
            progress.fail(error)
            throw error
        }
    }

    /// Reboots `udid` into `theme` before the runner starts when the device was found in another appearance (or in one that could not be read), answering the line `start` prints — or `nil` when it already matched.
    ///
    /// **A simulator can report an appearance it does not draw**: measured on a session started dark on a light device, the runner set Dark, `simctl ui` said so, and the screen stayed light. Walks meet the same behaviour and cure it with `DeviceSettle` — set, reboot, read back — and so does a session, only before its runner rather than between two passes, since a reboot ends an XCUITest session. The device is the session's own (a UDID or a lease), which is what a settle's reboot requires. The found appearance is what the runner and `end` put back.
    static func settle(_ udid: String, found: Walkbook.Theme?, to theme: Walkbook.Theme, shell: Shell) throws -> String? {
        guard found != theme else { return nil }
        let outcome = DeviceSettle.perform(udid: udid, found: theme) { try shell.run($0, $1, timeout: $2) }
        guard case let .failed(step, reason) = outcome else {
            let putBack = found.map { "`session end` puts it back to \($0.rawValue)" } ?? "its appearance before could not be read, so `session end` cannot put it back"
            return "settled: \(udid) was \(found?.rawValue ?? "unreadable") and the state is \(theme.rawValue), so it was rebooted \(theme.rawValue) first; \(putBack)"
        }
        throw LiveSessionHostError.settleFailed(udid: udid, theme: theme, step: step.name, reason: reason, command: DeviceSettle.command(udid: udid, found: theme))
    }

    /// `error`, once the device a settle rebooted into the state's theme is put back to the appearance `start` found — the one failure a settle leaves behind that the end procedure does not already hand back.
    ///
    /// A runner that never became ready was ended, which handed the device back; anything that stopped the start before that (a spawn that failed, a directory that could not be made) did not, and left the device in the state's theme.
    ///
    /// **A runner that never became ready after a settle is refused with the settle named** (SimWalk#69): its launch of the app came straight after the settle's reboot, which is where a walk's second runner failed in SimWalk#68 ("does not have a process ID"), so a reader of the refusal is told the reboot happened rather than left with the runner's failure alone. Only that is said — the cause of such a launch failure is not established — and the stop's own handback lines say what the appearance came back to.
    static func handingBack(after error: any Error, settledInto theme: Walkbook.Theme?, found: Walkbook.Theme?, udid: String, run: (String, [String]) throws -> Shell.Result) -> any Error {
        guard let theme else { return error }
        if case let .neverReady(reason, lines) = error as? LiveSessionHostError {
            return LiveSessionHostError.neverReady(reason: reason, lines: lines + [Self.settledBeforeRunner(udid, theme: theme)])
        }
        let line: String
        if let found {
            let handback = DeviceAppearance.restore(found, udid: udid, run: run)
            line = handback.note(udid: udid, by: "this session").map { "⚠ \($0)" } ?? "appearance: \(udid) was put back to \(found.rawValue), as start found it"
        } else {
            line = "⚠ appearance: \(udid) was settled, and its appearance before could not be read, so it was not put back"
        }
        return LiveSessionHostError.neverReady(reason: "\(error)", lines: [line])
    }

    /// The line a refusal after a settle carries: the runner was started straight after the settle's reboot — what happened, not a cause.
    static func settledBeforeRunner(_ udid: String, theme: Walkbook.Theme) -> String {
        "settled: \(udid) was rebooted \(theme.rawValue) just before this runner was started, so its launch of the app came straight after that reboot — a walk's runner has failed its launch there before (SimWalk#68), for a cause not yet established"
    }

    /// The runner's session test, as the result bundle names it.
    static var testID: String {
        "WalkRunner/testSession()"
    }

    static func captureState(_ json: String) throws -> Walkbook.CaptureState {
        let state: Walkbook.CaptureState
        do {
            state = try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))
        } catch {
            throw LiveSessionHostError.unreadableState(reason: DecodingReason.sentence(for: error))
        }
        if state.environment?.keys.contains(AnimationsOptIn.libraryEnvironmentKey) == true {
            throw LiveSessionHostError.stateSetsAnimations(variable: AnimationsOptIn.libraryEnvironmentKey)
        }
        return state
    }
}
