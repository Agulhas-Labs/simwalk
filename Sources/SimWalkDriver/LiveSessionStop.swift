//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore

/// Ends a live session: asks the runner to stop, signals it only when it will not and is provably the runner this session started, hands the device back, and removes the session's directory — unless the runner is still running, or another holder has the device and the handback is deferred.
///
/// **A signal reaches the recorded pid's group and nothing else, and only when that pid leads its own group, is `xcodebuild`, and started no later than the session's record.** A pid outlives its process: a runner that died days ago leaves a number the system may since have given to anything, and `killpg` on it would stop somebody else's work. `start` spawned the runner as its group's leader, so a pid that is not one — or is not `xcodebuild` — is not this session's runner. Every runner passes those two, so a stale session's pid reused by *another* session's runner would too; its start time does not, since this session's runner started before its record was written. A pid that fails any of the three is not this session's runner, which has therefore exited: it is left alone — not asked to end, not waited on, not signalled — and said so.
///
/// **A pid gone at any of those reads — or when the signal is sent — is the runner having exited**, not a stranger (SimWalk#75): a runner that exits while it is being checked leaves nothing to stop, so the stop's goal is met. It is not signalled, the session is not kept as still running, and the step says it exited. **So is a pid reused after the first check** — while `end` or `SIGTERM` is waited on (SimWalk#77): every later check asks whether this session's runner is running (``LiveSessionProcesses/isRunning(_:)``), not whether its pid is alive, so a stranger that took the number is neither waited on nor reported as the runner left running, with a `kill` aimed at it.
///
/// **The handback runs on every path** — ended, exited by itself, signalled, or left running — because the XCUITest teardown switches the device's accessibility off however the session ended.
///
/// **A runner that had exited before `end` is handed back from when it stopped, not from now** (SimWalk#91). Its teardown may be long past, so a wait from now spends the teardown's whole budget on nothing and qualifies a device that is fine with "a later teardown may undo". The stop is ``LiveSessionChannel/latestStop()`` — `exit.json`'s stop time, else the heartbeat's bound, else none and the whole wait from now, as before — the same reading `session list` makes. **And a restore `list` already made and recorded for it is reported, not made again — when it covers every stop on the device** (SimWalk#92): the runner was gone before this `end`, so nothing has run on its behalf since, and a second restore would only wait again. But `list` makes one restore per device and writes it into every stopped session there, and another session on the device can stop after it, its teardown still to come when the record was made; reported then, the record says on over a device the later teardown switched off. So a record is reused only when the stop it was dated from is no earlier than every stopped session's on the device, this one's included — each ``LiveSessionChannel/latestStop()``, else the stop that session's own record covers, else unknown, which forbids reuse; running sessions are not counted, since their own `end` hands back. A file from before #92 names no stop and is never reused. **Refused, the restore is dated from that device-wide latest stop, not from this session's own**: dated from its own older stop it could read the key on before a later session's teardown lands, which is the same bug made by `end` instead of `list`; dated from the latest, one `end` covers every teardown on the device, at the cost of at most the rest of a later session's teardown budget. A recorded restore that failed, could not be confirmed, or never saw the teardown is made again, since this is the last handback before the record is removed with the directory. A runner `end` itself saw running is handed back from now, once its exit was seen — not from its `exit.json`, which is written before XCTest's teardown and before `xcodebuild` returns, so a runner slow to exit after it, or signalled, would have its teardown taken as long past; not from its heartbeat, for the same reason; and never from a record, which `list` makes only for a runner that is not running. One still running is handed back from now too.
///
/// **A device something else is using is not handed back** (SimWalk#96), as `session list` leaves it alone: a walk's lease or a `session start`'s claim means another holder's runner is on it, and `end` writing its accessibility or appearance would land under that holder's walk. The step says why and the answer is qualified. **And the session is kept, so the handback is deferred rather than dropped** (SimWalk#128): removed, nothing would restore the device's accessibility or appearance once that holder is done. The kept directory carries a ``Deferral`` naming the holder `end` found, the step names the `session end` that completes it, `session list` keeps switching the device's accessibility back on for it once the device is free, as for any stopped session, and the next `end` with the device free makes the whole handback and removes the session. A holder that takes the device during the teardown wait, after the busy question answered free, is met the same way: the re-ask leaves the rest of the handback undone, and the session is kept with a ``Deferral`` naming that holder. **Except when nothing but the session's own lease makes the device busy** and that lease is no longer held — it lapsed on a clone, or a release is deleting the clone: no holder will ever be done with a device on its way to `simctl delete`, so a deferral would only be re-deferred until the device is gone. The session is removed with nothing handed back, one step says why, and the answer is not qualified, since nothing is owed to a device about to be deleted. **The same holds when the lease lapses during the handback**, after part of it was made: one step says the rest was not handed back, the answer keeps the lines for what was handed back, and drops the lines and qualifications for the parts the re-ask left undone, which no holder interrupted.
///
/// **A runner still running keeps its session.** Removing the directory would hide the orphan from `list` and from the one-session-per-device check, so it stays, and `end` can be run again once the runner has stopped.
public struct LiveSessionStop {
    public let record: LiveSessionRecord
    public let layout: LiveSessionLayout
    public let processes: any LiveSessionProcesses
    /// Where the session lives, and the other sessions on its device whose stops a reused `list` record must cover.
    let store: LiveSessionStore
    /// Whether something else is using the device at the given time, asked when the handback would start and again before each of its writes (SimWalk#128); a handback made then would write over its holder's work.
    let isDeviceBusy: (Date) -> Bool
    /// What kind of holder has the device, asked only once ``isDeviceBusy`` has answered busy: whose the device is decides whether the handback is deferred, and names the holder in the step that says so.
    let holder: (Date) -> Holder

    public init(
        record: LiveSessionRecord,
        store: LiveSessionStore,
        processes: any LiveSessionProcesses,
        isDeviceBusy: @escaping (Date) -> Bool = { _ in false },
        holder: @escaping (Date) -> Holder = { _ in .another("a walk or another session") }
    ) {
        self.record = record
        self.store = store
        self.isDeviceBusy = isDeviceBusy
        self.holder = holder
        layout = store.layout(id: record.id)
        self.processes = processes
    }

    /// How long the runner is given to exit after `end`, and again after `SIGTERM`.
    public static var grace: TimeInterval {
        10
    }

    public func perform(run: (String, [String]) throws -> Shell.Result, pause: (TimeInterval) -> Void, now: () -> Date) -> Report {
        let channel = LiveSessionChannel(layout: layout)
        var steps: [String] = []
        let runner = LiveSessionRunnerGuard(record: record, processes: processes, grace: Self.grace, waitedAfter: "end").stop(
            steps: &steps,
            askToEnd: { (try? channel.exitRecord()) == nil ? askToEnd(channel, pause: pause, now: now) : nil },
            pause: pause,
            now: now
        )
        let stillRunning = runner.stillRunning
        let exitedBeforeEnd = !runner.sawRunner
        let exit = try? channel.exitRecord()
        let deviceStop = exitedBeforeEnd ? latestStopOnDevice() : nil
        let listed = exitedBeforeEnd ? listsHandback() : nil
        let recorded = listed.flatMap { $0.covers(deviceStop) ? $0.restoration : nil }
        if recorded != nil {
            steps.append("`session list` already switched accessibility back on after the runner stopped and recorded it in \(layout.accessibilityHandback.path) — reported as recorded, not restored again")
        } else if listed != nil {
            steps.append("`session list` recorded switching accessibility back on in \(layout.accessibilityHandback.path), but not from a stop as late as every stopped session's on \(record.udid) — restored again")
        }
        // A runner this `end` saw running is waited on from now, after its exit was seen: `exit.json` is written before
        // XCTest's teardown and before `xcodebuild` returns, so dating the stop from it would start the teardown's budget
        // early and could read a teardown still to come as one long past (#91 review).
        let stoppedAt = exitedBeforeEnd ? deviceStop : nil
        let deferred = Deferral.read(from: layout.deferredHandback)
        let busy = isDeviceBusy(now())
        let holder = busy ? holder(now()) : nil
        switch holder {
        case let .another(name)?:
            steps.append("did not hand \(record.udid) back: \(name) holds it, and writing its accessibility or appearance now would land under that holder")
        case .ownLeaseNotHeld?:
            steps.append(ownLeaseNotHeldStep)
        case nil:
            if let deferred {
                steps.append("handing \(record.udid) back now: an earlier `end` deferred it while \(deferred.holder) held the device")
            }
        }
        let handback = busy ? nil : DeviceHandback.perform(
            udid: record.udid,
            found: record.foundAppearance,
            runnerFinished: false,
            stoppedAt: stoppedAt,
            recorded: recorded,
            isDeviceBusy: isDeviceBusy,
            run: run,
            pause: pause,
            now: now
        )
        // Free when the handback began, the device can still be taken during its teardown wait, and the re-ask then leaves
        // a part undone: kept, the next `end` makes it; removed, it would be dropped for good (SimWalk#128 review).
        let tookDuring = handback.map(Self.leftPartUndone) == true ? self.holder(now()) : nil
        switch tookDuring {
        case let .another(name)?:
            steps.append("did not finish handing \(record.udid) back: \(name) took it during the handback, so what was left would land under that holder")
        case .ownLeaseNotHeld?:
            steps.append("did not finish handing \(record.udid) back: the session's own lease stopped being held during the handback (lapsed, or being released), so the device awaits deletion and the rest was not handed back")
        case nil:
            break
        }
        var removal: String?
        var completedBy: String?
        if stillRunning {
            steps.append("kept \(layout.directory.path): the runner is still running, so the session stays listed — end it again once it has stopped")
        } else if let name = (holder ?? tookDuring)?.anotherHolder, store.record(id: record.id) != nil {
            // Removed, nothing would hand the device back once that holder is done (SimWalk#128).
            try? Deferral(holder: name).write(to: layout.deferredHandback)
            completedBy = "`simwalk session end \(record.id)`"
            steps.append("kept \(layout.directory.path): the handback is deferred until \(name) is done with \(record.udid) — `simwalk session end \(record.id)` then hands it back and removes the session")
        } else {
            // Kept without its record, a session is one no `end` can find, so its directory would never be removed.
            let unrecorded = (holder ?? tookDuring)?.anotherHolder != nil
            do {
                try FileManager.default.removeItem(at: layout.directory)
                steps.append("removed \(layout.directory.path)" + (unrecorded ? ": no session record was written, so no later `end` could find it to complete the handback" : ""))
            } catch {
                removal = "\(layout.directory.path) could not be removed: \(error.localizedDescription)"
            }
        }
        return Report(steps: steps, exit: exit, handback: handback, stillRunning: stillRunning, removalFailure: removal, accessibilityBy: recorded == nil ? "this session" : "`session list`", skippedHandback: holder?.anotherHolder != nil, completedBy: completedBy, ownLeaseLapsedDuring: tookDuring?.isOwnLeaseNotHeld ?? false)
    }

    private var ownLeaseNotHeldStep: String {
        "did not hand \(record.udid) back: the session's own lease is no longer held (lapsed, or being released), so the device awaits deletion and nothing was handed back"
    }

    /// Whether a holder that took the device during the handback left its accessibility or its appearance unwritten.
    private static func leftPartUndone(_ handback: DeviceHandback) -> Bool {
        if case .leftToAnotherHolder = handback.appearance {
            return true
        }
        return handback.accessibility.state == .leftToAnotherHolder
    }

    /// The latest stop on this session's device that a restore must cover: every stopped session's ``LiveSessionAccessibilityHandback/stopBound(of:)``, this one's included; `nil` — a wait from now — when any is unknown.
    private func latestStopOnDevice() -> Date? {
        let others = store.all().compactMap(\.record).filter { $0.udid == record.udid && $0.id != record.id && !processes.isRunning($0) }
        return LiveSessionAccessibilityHandback.latest(([record] + others).map { LiveSessionAccessibilityHandback.stopBound(of: store.layout(id: $0.id)) })
    }

    /// The accessibility restore `session list` recorded for this session, when it is one that held as far as anyone saw; `nil` when there is none, or it failed, could not be confirmed, or never saw the teardown, and is worth making again — a restore made without seeing the teardown is exactly what restoring again would clear (SimWalk#92).
    private func listsHandback() -> LiveSessionAccessibilityHandback.Record? {
        guard let recorded = LiveSessionAccessibilityHandback.Record.read(from: layout.accessibilityHandback) else { return nil }
        return switch recorded.restoration.state {
        case .restored, .alreadyOn:
            recorded
        case .failed, .unconfirmed, .restoredWithoutTeardown, .leftToAnotherHolder:
            nil
        }
    }

    private func askToEnd(_ channel: LiveSessionChannel, pause: (TimeInterval) -> Void, now: () -> Date) -> String {
        do {
            let number = try channel.send(.end)
            _ = try channel.awaitResponse(to: number, timeout: Self.grace, isRunnerAlive: { processes.isRunning(record) }, pause: pause, now: now)
            return "sent end (request \(number)); the runner answered"
        } catch {
            return "sent end: \(error)"
        }
    }
}

public extension LiveSessionStop {
    /// Whose the device is when the busy question answers busy (SimWalk#128).
    enum Holder: Equatable, Sendable {
        /// Another holder — a walk, another session's runner, a `session start`, another lease — named for the step saying the handback is deferred until it is done.
        case another(String)
        /// Nothing but the session's own lease, no longer held: lapsed on a clone, or being released, either way a device awaiting `simctl delete` that no `end` will ever hand back.
        case ownLeaseNotHeld

        /// The name of the other holder, `nil` for the session's own lapsed lease; every decision about whether the device is another's goes through it, so a third case makes the compiler ask.
        var anotherHolder: String? {
            switch self {
            case let .another(name):
                name
            case .ownLeaseNotHeld:
                nil
            }
        }

        /// Whether this is the session's own lapsed lease, decided by the same exhaustive switch as ``anotherHolder``.
        var isOwnLeaseNotHeld: Bool {
            switch self {
            case .ownLeaseNotHeld:
                true
            case .another:
                false
            }
        }
    }
}

public extension LiveSessionStop.Holder {
    /// The holder on `udid` for session `session`, asked only once ``LiveSessionAccessibilityHandback/isHeldByAnother(udid:session:store:processes:leases:now:)`` has answered busy, by `session end` and a never-ready `session start` alike (SimWalk#128): a lease is what is left when no walk, other session or start is found.
    ///
    /// That lease carrying the session's own token is checked for liveness here, not inferred from the busy answer, which was given earlier: a walk under that lease may have released its claim since. Not live (lapsed, or being released), the device is a clone awaiting deletion, not another holder's: ``ownLeaseNotHeld``. Still live, it is a holder that has just finished, and the next `end` completes the handback.
    static func on(udid: String, session: (id: String, leaseToken: String?), store: LiveSessionStore, processes: any LiveSessionProcesses, leases: LeaseStore, now: Date) -> Self {
        if WalkClaim.walkedDevices(in: leases, isAlive: processes.isAlive).contains(udid) {
            return .another("a walk")
        }
        if store.all().compactMap(\.record).contains(where: { $0.id != session.id && $0.udid == udid && processes.isRunning($0) }) {
            return .another("another session's runner")
        }
        if LiveSessionClaim.heldDevices(in: store, isAlive: processes.isAlive).contains(udid) {
            return .another("a `session start`")
        }
        if let token = session.leaseToken, case let lease?? = leases.held(now: now)[udid], lease.token == token,
           !LiveSessionAccessibilityHandback.isLive(lease, on: udid, leases: leases, now: now)
        {
            return .ownLeaseNotHeld
        }
        return .another("another holder of its lease")
    }
}

extension LiveSessionStop {
    /// The mark `end` leaves in a session it kept because another holder had the device (SimWalk#128): the holder it found, so the `end` that completes the handback can say what it completes.
    struct Deferral: Codable, Equatable {
        let holder: String

        static func read(from url: URL) -> Deferral? {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Deferral.self, from: $0) }
        }

        func write(to url: URL) throws {
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }
}

public extension LiveSessionStop {
    /// What the end procedure did, step by step.
    struct Report {
        public let steps: [String]
        /// Why the runner stopped, in its own words; `nil` when it left no record.
        public let exit: LiveSessionExit?
        /// What was put back on the device; `nil` when it was left alone because something else was using it.
        public let handback: DeviceHandback?
        public let stillRunning: Bool
        public let removalFailure: String?
        /// What switched accessibility back on, as the handback's note names it: `this session`, or `` `session list` `` when its recorded restore is reported.
        let accessibilityBy: String
        /// Whether the handback was skipped for a busy device.
        let skippedHandback: Bool
        /// What finishes a handback another holder interrupted: the `session end` a kept deferral names; `nil` when no deferral was written.
        let completedBy: String?
        /// Whether the session's own lease stopped being held during the handback: the parts the re-ask left undone were left to no holder, so they are neither noted as left to one nor qualify the answer.
        let ownLeaseLapsedDuring: Bool

        /// What qualifies an end: a runner left running, a directory left behind, a device not handed back as found.
        public var qualifications: [String] {
            (stillRunning ? ["the runner is still running"] : []) + (removalFailure.map { [$0] } ?? []) + (skippedHandback ? ["the device was not handed back: something else is using it"] : []) + (handback?.qualifications(omittingUndone: ownLeaseLapsedDuring) ?? [])
        }

        /// Every line the procedure has to say: its steps, the runner's exit, and the handback.
        public var lines: [String] {
            steps + (exit.map { ["runner: \($0.summary)"] } ?? []) + (handback?.notes(by: accessibilityBy, appearanceBy: "this session", completedBy: completedBy, omittingUndone: ownLeaseLapsedDuring) ?? [])
        }
    }
}
