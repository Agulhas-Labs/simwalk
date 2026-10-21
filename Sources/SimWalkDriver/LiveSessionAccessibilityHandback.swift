//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore

/// The accessibility half of the handback, for a session whose runner stopped without `end` — the idle timeout, a crash — run host-side by `session list`.
///
/// **A session that ends itself hands back only what its runner can.** The runner puts the appearance back on its own way out, but the XCUITest teardown switches accessibility off after the runner's last line, and no host process is running then to switch it back: `start` returned long before, and `end`, which runs the whole ``DeviceHandback``, was never called. So `list` — what a person or an agent runs to see what is left on the machine — switches it back on the first time it finds such a session, records how that went in the session's ``LiveSessionLayout/accessibilityHandback``, and says so; a later `list` reports the record rather than touching the device again, and `end` still runs the whole handback.
///
/// **The teardown wait runs from the runner's exit record, from its heartbeat's bound when it left none, and from now when it left neither.** A runner that crashed or was killed writes no `exit.json`, and its session directory's last write bounds its stop only from below — an idle runner writes nothing for up to its idle timeout, which `SIMWALK_SESSION_IDLE_SECONDS` can lengthen at `start` and no record keeps, and one busy in a step or a launch writes nothing until XCUITest returns. A stop placed too early takes a teardown still to come as long past, records `.alreadyOn`, and leaves the device off under a record that says on (SimWalk#76). The runner's ``LiveSessionHeartbeat``, rewritten every few seconds from a background queue until `exit.json`, bounds the stop from above instead (SimWalk#91 item 10): passed where `exit.json`'s stop time goes, it gives a session dead for longer than the teardown's budget no wait and no qualification. A session with neither file — a runner from before the heartbeat, one that never reached serving (a build or launch that failed), or one whose last beat could not be written and was removed — still gets the whole wait from now, qualified, however long ago it died.
///
/// **Only a runner whose process has gone is handed back.** `exit.json` is written before the teardown, so a restore made on its strength could be undone a moment later. **A device something else is using is left alone**: a running session's runner holds accessibility on, and a restore would spend its whole wait on a teardown that has not happened; a `session start` still holding its claim — before its `session.json` exists — may be rebooting the device, and so may a walk, which holds a lease on it and a ``WalkClaim`` for as long as it runs — the claim is what no lease token exempts, so a walk under the ended session's own lease is still seen (SimWalk#128); a restore against a rebooting device fails and would record `.failed` for good. The session's own `end`, the walk's own handback, or the `list` after they are done hands the device back. One restore per device, however many stopped sessions name it, **dated from the latest stop among the sessions it is recorded for** — from now when any of their stops is unknown — and each record says which stop that was (SimWalk#92): a restore dated from an older session's stop could read the key on before a later one's teardown lands, and record `.alreadyOn` into the later session too, over a device about to go off. The covered stop is also what lets `end` tell whether a record still vouches for the device once another session on it has stopped.
public struct LiveSessionAccessibilityHandback {
    /// Each stopped session's handback by id: restored by this call, or as an earlier `list` recorded it.
    ///
    /// A session still running, or one whose device something else is using and no record, has none. One whose device another holder took during the restore reads `.leftToAnotherHolder` and is left unrecorded, for a later `list` or `end` to hand back.
    public static func perform(
        store: LiveSessionStore,
        processes: any LiveSessionProcesses,
        leases: LeaseStore,
        run: (String, [String]) throws -> Shell.Result,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) -> [String: AccessibilityPreference.Restoration] {
        // A device has no accessibility to hand back (Brief, "Live sessions on a physical device", ruling 6): its records are not this restore's.
        let records = store.all().compactMap(\.record).filter { $0.device == nil }
        let stopped = records.filter { !processes.isRunning($0) }
        // A dead session's own caller still holds the lease it started under; that is not another holder of the device.
        // Asked afresh each time — before each device, and inside its restore after the teardown wait, before each write
        // (SimWalk#128): the restores before it, and its own wait, can each run the whole teardown budget.
        let own = ownLeases(of: stopped)
        let isBusy = { (udid: String, date: Date) -> Bool in
            let current = store.all().compactMap(\.record).filter { $0.device == nil }
            return busyDevices(of: current, store: store, processes: processes, leases: leases, now: date, ownLeases: own).contains(udid)
        }
        let recorded = Dictionary(uniqueKeysWithValues: stopped.compactMap { record in
            Record.read(from: store.layout(id: record.id).accessibilityHandback).map { (record.id, $0) }
        })
        var byDevice: [String: Record] = [:]
        var bySession: [String: AccessibilityPreference.Restoration] = [:]
        for record in stopped {
            if let earlier = recorded[record.id] {
                bySession[record.id] = earlier.restoration
                continue
            }
            let handback: Record
            if let made = byDevice[record.udid] {
                handback = made
            } else {
                guard !isBusy(record.udid, now()) else { continue }
                let unrecorded = stopped.filter { $0.udid == record.udid && recorded[$0.id] == nil }
                handback = restore(
                    udid: record.udid,
                    stoppedAt: latest(unrecorded.map { LiveSessionChannel(layout: store.layout(id: $0.id)).latestStop() }),
                    isDeviceBusy: { isBusy(record.udid, $0) },
                    run: run,
                    pause: pause,
                    now: now
                )
                byDevice[record.udid] = handback
            }
            // A device another holder took during the restore was not handed back: no record, so a later `list` or `end`
            // tries again. A session `end` removed meanwhile has nowhere to record it, and needs no record.
            if handback.restoration.state != .leftToAnotherHolder {
                try? handback.write(to: store.layout(id: record.id).accessibilityHandback)
            }
            bySession[record.id] = handback.restoration
        }
        return bySession
    }

    /// The devices something else is using: a running session's runner, a `session start` still holding its claim, a walk's lease, or a walk's claim — each reason a handback must leave the device alone.
    ///
    /// `session end` asks the same question before it touches a device, so the two cannot disagree about whose device it is.
    ///
    /// `ownLeases` maps a device to the lease tokens of the sessions being handed back: the caller who started a session with `--lease` still holds that lease, and it is not another holder. Only a held lease carrying exactly one of those tokens is exempt; a lease with another token, or one that cannot be read, still counts, and so does one under such a token that is no longer held — a release deleting the device, or a clone whose lease has lapsed and awaits deletion — since `simctl` against a device on its way out is no handback. A walk's ``WalkClaim`` is exempt under no token, and a `session start`'s claims are read from the store's `.claims` directory rather than for `records`' devices, so a start on a device no record names is seen too (SimWalk#128).
    public static func busyDevices(of records: [LiveSessionRecord], store: LiveSessionStore, processes: any LiveSessionProcesses, leases: LeaseStore, now: Date, ownLeases: [String: Set<String>] = [:]) -> Set<String> {
        let leased = Set(leases.held(now: now).filter { udid, lease in
            guard let lease, ownLeases[udid]?.contains(lease.token) == true else { return true }
            return !isLive(lease, on: udid, leases: leases, now: now)
        }.keys)
        let claimed = LiveSessionClaim.heldDevices(in: store, isAlive: processes.isAlive)
        let walked = WalkClaim.walkedDevices(in: leases, isAlive: processes.isAlive)
        return Set(records.filter { processes.isRunning($0) }.map(\.udid)).union(claimed).union(leased).union(walked)
    }

    /// Whether a holder other than session `id` is on `udid`: any other simulator session's runner, a start's claim, a lease not carrying `leaseToken`, or a walk's claim.
    ///
    /// `session end` and a never-ready `session start` both ask this, so the two cannot disagree about whose device it is (SimWalk#128). The session's own record is not another holder.
    public static func isHeldByAnother(udid: String, session: (id: String, leaseToken: String?), store: LiveSessionStore, processes: any LiveSessionProcesses, leases: LeaseStore, now: Date) -> Bool {
        busyDevices(
            of: store.all().compactMap(\.record).filter { $0.device == nil && $0.id != session.id },
            store: store,
            processes: processes,
            leases: leases,
            now: now,
            ownLeases: session.leaseToken.map { [udid: [$0]] } ?? [:]
        ).contains(udid)
    }

    /// Whether `lease` is the lease `udid` is held under now: the device's lease file carries its token, and it has neither expired nor lost its holder.
    ///
    /// A release in progress has renamed the file to a tombstone, and a lapsed clone's lease is not held; both are on their way to `simctl delete`.
    static func isLive(_ lease: DeviceLease, on udid: String, leases: LeaseStore, now: Date) -> Bool {
        leases.isHeld(lease, now: now) && (try? leases.lease(onDevice: udid))??.token == lease.token
    }

    /// The lease tokens `records` were started under, by device — every one, since two stopped sessions on a device may hold different leases and either may be the one still held; a record with none exempts nothing, so an older record stays conservative.
    public static func ownLeases(of records: [LiveSessionRecord]) -> [String: Set<String>] {
        Dictionary(records.compactMap { record in record.leaseToken.map { (record.udid, [$0]) } }, uniquingKeysWith: { $0.union($1) })
    }

    /// The latest the runner of a session seen not running can have stopped: ``LiveSessionChannel/latestStop()``, else the stop its recorded restore covers — that restore began after the runner was seen stopped — else `nil`, unknown.
    static func stopBound(of layout: LiveSessionLayout) -> Date? {
        LiveSessionChannel(layout: layout).latestStop() ?? Record.read(from: layout.accessibilityHandback)?.coveredStop
    }

    /// The latest of `stops`, or `nil` — a wait from now — when any of them is unknown.
    static func latest(_ stops: [Date?]) -> Date? {
        let known = stops.compactMap(\.self)
        return known.count == stops.count ? known.max() : nil
    }

    /// Restores `udid` dated from `stoppedAt`, recording the stop the wait actually ran from: `stoppedAt`, or when the restore began when that is unknown or later — an upper bound on every runner already seen stopped.
    private static func restore(
        udid: String,
        stoppedAt: Date?,
        isDeviceBusy: @escaping (Date) -> Bool,
        run: (String, [String]) throws -> Shell.Result,
        pause: (TimeInterval) -> Void,
        now: () -> Date
    ) -> Record {
        let began = now()
        let restoration = AccessibilityPreference.restore(udid: udid, stoppedAt: stoppedAt, isDeviceBusy: isDeviceBusy, run: run, pause: pause, now: now)
        return Record(restoration: restoration, coveredStop: min(stoppedAt ?? began, began))
    }

    /// The line `list` prints for a session's handback.
    public static func line(_ restoration: AccessibilityPreference.Restoration) -> String {
        let subject = "\(AccessibilityPreference.domain) \(AccessibilityPreference.key)"
        let stopped = "accessibility: the runner stopped without `end`"
        let command = AccessibilityPreference.command(udid: restoration.udid)
        return switch restoration.state {
        case .restored:
            "\(stopped), its teardown switched \(subject) off, and `session list` switched it back on for \(restoration.udid) and saw it hold"
        case .alreadyOn:
            "\(stopped); `session list` found \(subject) already back on for \(restoration.udid), long after its teardown — nothing to hand back"
        case .restoredWithoutTeardown:
            "\(stopped); `session list` switched \(subject) back on for \(restoration.udid) and saw it hold, without seeing the teardown switch it off"
        case let .failed(reason):
            "\(stopped), and `session list` could not switch \(subject) back on for \(restoration.udid) (\(reason)) — an in-process accessibility suite on this device reads empty trees until you run: \(command)"
        case let .unconfirmed(reason):
            "\(stopped), and `session list` could not confirm \(subject) back on for \(restoration.udid) (\(reason)) — if an in-process accessibility suite on this device reads empty trees, run: \(command)"
        case .leftToAnotherHolder:
            "\(stopped); another holder took \(restoration.udid) during the handback, so \(subject) was left as that holder has it — the next `session list` or `session end` switches it back on once that holder is done"
        }
    }
}

extension LiveSessionAccessibilityHandback {
    /// What a session's ``LiveSessionLayout/accessibilityHandback`` holds: a restore, and the stop it was dated from (SimWalk#92).
    ///
    /// A wrapper rather than a field on ``AccessibilityPreference/Restoration``, which a walk's and an `end`'s ``DeviceHandback`` carry too and which has no stop to name there. A file from before SimWalk#92 holds a bare restore: it is read with no covered stop, so `list` still reports it and `end` makes the restore again rather than trusting it.
    struct Record: Codable, Equatable {
        let restoration: AccessibilityPreference.Restoration
        /// The stop the restore's teardown wait ran from, so it covers every runner on the device that stopped no later; `nil` for a file from before SimWalk#92, which said nothing of it.
        let coveredStop: Date?

        /// The record at `url`, in either shape; `nil` when there is none or it cannot be read.
        static func read(from url: URL) -> Record? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let record = try? JSONDecoder().decode(Record.self, from: data) {
                return record
            }
            return (try? JSONDecoder().decode(AccessibilityPreference.Restoration.self, from: data)).map { Record(restoration: $0, coveredStop: nil) }
        }

        /// Whether this restore vouches for a device whose latest stop is `stop`: dated from no earlier, and `stop` known.
        func covers(_ stop: Date?) -> Bool {
            guard let coveredStop, let stop else { return false }
            return coveredStop >= stop
        }

        func write(to url: URL) throws {
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }
}
