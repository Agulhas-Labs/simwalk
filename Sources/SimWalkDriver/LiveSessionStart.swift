//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Starts a live session's resident runner in the background and waits for its word that it is ready.
///
/// **One session per device.** A second runner on a device would be a second XCUITest session fighting the first for the app, so a device whose session is alive is refused before anything is created.
///
/// **A runner that never becomes ready leaves nothing behind**: its diagnosis is read while its result bundle still exists, then the end procedure stops it, hands the device back (leaving it alone when another holder is on it, as `end` does) and removes the directory.
public struct LiveSessionStart {
    public let store: LiveSessionStore
    public let processes: any LiveSessionProcesses

    public init(store: LiveSessionStore, processes: any LiveSessionProcesses) {
        self.store = store
        self.processes = processes
    }

    /// How long a runner is given to build its session, launch the app and write `ready.json`.
    public static var readyTimeout: TimeInterval {
        180
    }

    /// The live session on `udid`, if there is one: its record's runner alive — not a stranger that inherited its pid — and no exit record written.
    public func liveSession(on udid: String) -> LiveSessionRecord? {
        store.all().compactMap(\.record).first { record in
            record.udid == udid && processes.isRunning(record) && (try? LiveSessionChannel(layout: store.layout(id: record.id)).exitRecord()) == nil
        }
    }

    /// Claims `udid` for this start until its record is written: taken before the build and the settle, and refused while another live start holds it (``LiveSessionClaim``).
    public func claim(udid: String, holder: Int32 = getpid()) throws -> LiveSessionClaim {
        try LiveSessionClaim.take(udid: udid, in: store, holder: holder, isAlive: processes.isAlive)
    }

    /// Spawns the runner for `launch` on `udid` and waits for it to be ready, stopping it and handing the device back when it never is.
    ///
    /// `foundAppearance` is what `end` puts back, recorded before the runner (or a settle) changed anything.
    public func perform(id: String, udid: String, launch: LiveSessionLaunch, foundAppearance: Walkbook.Theme?, leaseToken: String? = nil, effects: Effects) throws -> (record: LiveSessionRecord, ready: LiveSessionReady) {
        if let live = liveSession(on: udid) {
            throw LiveSessionHostError.alreadyRunning(udid: udid, id: live.id, pid: live.pid)
        }
        let layout = try store.create(id: id)
        let channel = LiveSessionChannel(layout: layout)
        let pid: Int32
        do {
            try channel.writeLaunch(launch)
            pid = try processes.spawn(effects.command(layout), log: layout.runnerLog)
            effects.spawned(pid)
        } catch {
            try? FileManager.default.removeItem(at: layout.directory)
            throw error
        }
        let record = LiveSessionRecord(id: id, pid: pid, udid: udid, app: launch.appBundleID, startedAt: effects.now(), foundAppearance: foundAppearance, leaseToken: leaseToken)
        let started = effects.now()
        var reason: String
        do {
            try store.write(record)
            effects.recorded()
            reason = try awaitReady(channel, pid: pid, since: started, pause: effects.pause, now: effects.now)
        } catch {
            reason = "\(error)"
        }
        if let ready = try? channel.readyRecord() {
            return (record, ready)
        }
        let diagnosis = effects.diagnose(layout)
        // When `store.write(record)` threw, `recorded` never ran, and this start's own claim, still held, would read as another holder and keep the handback from ever being made. Releasing is idempotent: a claim is removed only while it is still this one's.
        effects.recorded()
        let report = LiveSessionStop(record: record, store: store, processes: processes, isDeviceBusy: effects.isDeviceBusy).perform(run: effects.run, pause: effects.pause, now: effects.now)
        throw LiveSessionHostError.neverReady(reason: reason, lines: report.lines + report.qualifications.map { "⚠ \($0)" } + diagnosis)
    }

    /// Polls until the runner is ready (returning nothing to say), or why it never will be.
    private func awaitReady(_ channel: LiveSessionChannel, pid: Int32, since started: Date, pause: (TimeInterval) -> Void, now: () -> Date) throws -> String {
        while try channel.readyRecord() == nil {
            if let exit = try channel.exitRecord() {
                return exit.summary
            }
            guard processes.isAlive(pid) else {
                return "xcodebuild (pid \(pid)) exited without writing ready.json — its output is in runner.log"
            }
            guard now().timeIntervalSince(started) < Self.readyTimeout else {
                return "no ready.json within \(Int(Self.readyTimeout)) s"
            }
            pause(LiveSessionChannel.pollInterval)
        }
        return ""
    }
}

public extension LiveSessionStart {
    /// What `perform` reaches beyond the session's own directory — the runner's command line and diagnosis, the child processes the end procedure runs, and time — so a test states each.
    struct Effects {
        /// The resident runner's command line for the session's layout.
        public let command: (LiveSessionLayout) -> RunnerCommand
        /// The runner's own account of why it never became ready, read from its result bundle.
        public let diagnose: (LiveSessionLayout) -> [String]
        /// Runs a command for the end procedure's handback.
        public let run: (String, [String]) throws -> Shell.Result
        public let pause: (TimeInterval) -> Void
        public let now: () -> Date
        /// Told the runner's pid as soon as it is spawned — the process whose life is the session's, which the progress file names from then on (SimWalk#83).
        public let spawned: (Int32) -> Void
        /// Told once the session's record is written, before the wait for the runner.
        ///
        /// The start's claim is done with, since the one-session check sees the record from then on, and a claim held through the wait would make the session's own `end` take its start for another holder (SimWalk#128). Also told before the stop of a start that never became ready, so that claim is not taken for another holder either.
        public let recorded: () -> Void
        /// Asked by the stop of a start that never became ready, before it hands the device back: whether another holder is on the device, which leaves the handback undone (SimWalk#128).
        public let isDeviceBusy: (Date) -> Bool

        public init(
            command: @escaping (LiveSessionLayout) -> RunnerCommand,
            diagnose: @escaping (LiveSessionLayout) -> [String],
            run: @escaping (String, [String]) throws -> Shell.Result,
            pause: @escaping (TimeInterval) -> Void,
            now: @escaping () -> Date,
            spawned: @escaping (Int32) -> Void = { _ in },
            recorded: @escaping () -> Void = {},
            isDeviceBusy: @escaping (Date) -> Bool = { _ in false }
        ) {
            self.command = command
            self.diagnose = diagnose
            self.run = run
            self.pause = pause
            self.now = now
            self.spawned = spawned
            self.recorded = recorded
            self.isDeviceBusy = isDeviceBusy
        }
    }
}
