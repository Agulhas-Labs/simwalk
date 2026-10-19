//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `session start` on a physical iPhone or iPad (Brief, "Live sessions on a physical device", rulings 8 and 9).
extension SessionStartCommand {
    /// Starts the session on the physical device `route` names: the lease, `device check`'s prerequisites, the appearance read through devicectl, the claim, the device build, then ``LiveSessionDeviceStart``.
    ///
    /// **The lease comes before any call to the phone.** `--device` takes one for the session, held by the holder `lease acquire` uses (``HolderProcess/sessionHolder()``), not this process, which exits once the runner answers; a presented `--lease` is renewed and left to its holder.
    ///
    /// A failure before the spawn releases a lease this start took and leaves nothing behind; one after it is the device stop's, which releases that lease itself once the runner has stopped.
    ///
    /// **A cancel before the spawn releases that lease at once and refuses the spawn** (``PreSpawnLease``): the prerequisites and the build run on, as a simulator start's build does, but no runner is started and nothing is answered over MCP for a session nobody would know of.
    ///
    /// **A cancel after the spawn ends the wait for `hello`** and runs the device stop, which releases that lease, rather than answering ready to a caller who has gone (SimWalk#127).
    ///
    /// A state's `locale`, `location` and `resetPermissions` are refused by name before the lease, as `walk --device` refuses them before any call; its `theme` is the runner's to set, so the simulator's settle reboot is not done.
    func performOnDevice(_ route: PhysicalDeviceRoute, id sessionID: String, effects: DeviceStartEffects, cancellation: Cancellation?, note: (String) -> Void) throws -> Answer {
        let launchState = try state.map(Self.captureState)
        if let launchState {
            let unsupported = DeviceTargetSupport.unsupported(in: launchState, label: "--state")
            guard unsupported.isEmpty else {
                throw LiveSessionHostError.unsupportedOnDevice(lines: unsupported)
            }
        }
        let held: WalkLease
        if let udid = route.udid {
            held = try WalkLease.takePhysical(udid: udid, store: effects.leases, holderPID: HolderProcess.sessionHolder(), now: effects.now())
        } else {
            held = try WalkLease.presentedPhysical(token: lease ?? "", store: effects.leases)
            try held.requireRenewed(now: effects.now())
        }
        let gate = PreSpawnLease(held, cancellation: cancellation)
        do {
            return try startOnDevice(held, launch: LiveSessionLaunch(appBundleID: app, state: launchState), id: sessionID, effects: effects, gate: gate, note: note)
        } catch {
            gate.releaseUnlessSpawned()
            throw error
        }
    }

    private func startOnDevice(_ held: WalkLease, launch: LiveSessionLaunch, id sessionID: String, effects: DeviceStartEffects, gate: PreSpawnLease, note: (String) -> Void) throws -> Answer {
        let udid = held.udid
        let shell = effects.shell
        let device = try PhysicalDevicePrerequisites.check(udid: udid, team: team, shell: shell)
        // Read before the runner changes anything: what `end` hands back. One that cannot be read is recorded as such, and the stop says so.
        let found = try? PhysicalDeviceAppearance.read(udid: udid, shell: shell)

        let starter = LiveSessionStart(store: effects.store, processes: effects.processes)
        let claim = try starter.claim(udid: udid)
        defer { claim.release() }
        if let live = starter.liveSession(on: udid) {
            throw LiveSessionHostError.alreadyRunning(udid: udid, id: live.id, pid: live.pid)
        }
        let run: (String, [String]) throws -> Shell.Result = { try shell.run($0, $1) }
        let source = try effects.runner?() ?? RunnerProject.resolve(executable: LaunchedBinary.url, binaryHash: { LaunchedBinary.hash }, run: run)
        try effects.builds.recordUse(of: source)
        let runner = RunnerInvocation(projectPath: source.projectPath, derivedDataPath: effects.builds.directory(for: source).path, shell: shell)
        // A cancel during the prerequisites starts no build: 20–40 s on a phone, for a runner that would never be spawned.
        try gate.requireNotCancelled()
        runner.coldBuildNote(commit: source.commit).map(note)
        // The team is non-empty: the prerequisites refused otherwise.
        try runner.buildForDevice(udid: udid, team: team ?? "", runnerBundleID: runnerBundleId)
        // Before the renewal, which a cancel's release would otherwise answer as a lease that could not be renewed.
        try gate.requireNotCancelled()
        // A build can outlast a good part of the lease: renewed before the runner starts, and refused here if it cannot be.
        do {
            try held.requireRenewed(now: effects.now())
        } catch {
            // A cancel landing after the check above releases the lease under the renewal: that is the cancel, not a lease lost (SimWalk#127).
            try gate.requireNotCancelled()
            throw error
        }

        let launchJSON = try String(decoding: JSONEncoder().encode(launch), as: UTF8.self)
        let theme = found.flatMap { Walkbook.Theme(rawValue: $0.userInterfaceStyle) }
        let endpoint = LiveSessionRecord.DeviceEndpoint(
            address: "",
            port: LiveSessionDeviceStart.drawPort(),
            team: team ?? "",
            runnerBundleID: runnerBundleId,
            leaseToken: held.token,
            leaseTaken: held.taken,
            appearance: found
        )
        let idleOverride = effects.environment[LiveSessionIdle.overrideVariable]
        let hello = effects.hello ?? { try DeviceSessionClient(address: $0.address, port: $0.port, token: $0.token).hello() }
        let startEffects = LiveSessionDeviceStart.Effects(
            command: { layout in
                runner.deviceSession(layout: layout, launchJSON: launchJSON, udid: udid, runnerCommit: source.commit, idleOverride: idleOverride, deviceAppearance: theme)
            },
            diagnose: { layout in RunnerFailureDiagnosis.read(resultBundlePath: layout.resultBundle.path, testID: Self.testID, shell: shell).lines },
            shell: shell,
            hello: hello,
            pause: effects.pause,
            now: effects.now,
            spawning: gate.spawn,
            cancelled: { gate.isCancelled }
        )
        let started = try LiveSessionDeviceStart(store: effects.store, processes: effects.processes, leases: effects.leases)
            .perform(id: sessionID, udid: udid, launch: launch, endpoint: endpoint, effects: startEffects)

        let idle = LiveSessionIdle.timeout(fromOverride: idleOverride)
        let until = effects.leases.entry(token: held.token).map { " until \(LeaseError.time($0.lease.expiresAt))" } ?? ""
        let leaseLine = held.taken
            ? "lease: taken for this session\(until), held by pid \(effects.leases.entry(token: held.token)?.lease.holderPID ?? 0); `session end` releases it"
            : "lease: presented, renewed\(until); left to its holder"
        return Answer(
            header: "live session: app: \(app)  device: \(started.ready.device.name) (\(started.ready.device.osVersion))  animations: on",
            verdict: .unqualified("session \(sessionID) ready"),
            residue: [
                "id: \(sessionID)",
                "read it: simwalk session read \(sessionID) [--match <text>] — prints the screen's hash",
                "step it: simwalk session step \(sessionID) '<route step json>' [--guard <hash>]",
                "save it: simwalk session save \(sessionID) --screen <id> --into <walkbook.json> [--expect <identifier>] — before end",
                "end it: simwalk session end \(sessionID) — it ends itself after \(Int(idle)) s without a request",
                "device: \(device.name) · \(device.marketingName) · iOS \(device.osVersion) · \(udid)",
                "transport: \(device.transportType)",
                leaseLine,
            ]
        )
    }
}

extension SessionStartCommand {
    /// What the device start reaches beyond its arguments, passed through from ``perform(shell:pause:now:id:runner:logFileURL:builds:leases:store:processes:environment:cancellation:deviceHello:note:)``.
    struct DeviceStartEffects {
        let shell: Shell
        let pause: (TimeInterval) -> Void
        let now: () -> Date
        let runner: (() throws -> RunnerSource)?
        let builds: RunnerBuilds
        let leases: LeaseStore
        let store: LiveSessionStore
        let processes: any LiveSessionProcesses
        let environment: [String: String]
        /// Stands in for the runner's `hello` in a test; `nil` is ``DeviceSessionClient``.
        let hello: ((DeviceSessionBind) throws -> LiveSessionReady)?
    }
}

/// The lease a device start holds until its runner is spawned, and the cancel that may end the start first (SimWalk#116).
///
/// **A cancel before the spawn releases the lease at once, on the cancelling thread.** A SIGINT or SIGTERM to the CLI ends the process straight after the cancel (``TerminationSignals``), so a release left to the start's own `catch` would never run; and a `--device` lease is held by the agent's session process, not this one, so it would outlive the CLI and refuse every walk and session on the phone until it expired, with no session record or printed token to release it by.
///
/// **The check and the spawn are one step under a lock**, so a cancel lands wholly before the spawn, which is then refused, or wholly after it, when the device stop owns the lease: never between, which would release the lease of a runner that is running.
///
/// A cancel after the spawn is recorded and nothing more: ``isCancelled`` ends the start's wait for `hello`, whose device stop releases the lease once the runner has stopped (SimWalk#127).
final class PreSpawnLease: @unchecked Sendable {
    private let lock = NSLock()
    private let held: WalkLease
    private var cancelled = false
    private var spawned = false

    init(_ held: WalkLease, cancellation: Cancellation?) {
        self.held = held
        cancellation?.onCancel { [self] in
            lock.withLock {
                cancelled = true
                if !spawned {
                    held.release()
                }
            }
        }
    }

    /// Whether the start has been cancelled, before its spawn or after it.
    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// Refuses a start that has been cancelled.
    func requireNotCancelled() throws {
        if isCancelled {
            throw LiveSessionHostError.startCancelled(udid: held.udid)
        }
    }

    /// Runs `spawn` unless the start has been cancelled, marking the lease the device stop's once it returns.
    func spawn(_ spawn: () throws -> Int32) throws -> Int32 {
        try lock.withLock {
            guard !cancelled else {
                throw LiveSessionHostError.startCancelled(udid: held.udid)
            }
            let pid = try spawn()
            spawned = true
            return pid
        }
    }

    /// Releases a lease the start took when no runner was spawned; once one was, the device stop releases it.
    func releaseUnlessSpawned() {
        lock.withLock {
            if !spawned {
                held.release()
            }
        }
    }
}
