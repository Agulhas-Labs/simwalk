//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk lease acquire [--device <udid|name>] [--clone-from <udid>] [--physical <udid>] [--ttl 30m]` — takes a device for the caller alone and prints its UDID and the lease's token, one line each.
///
/// The lease lives as long as the session asking (``HolderProcess/sessionHolder()``) or `--ttl`, whichever ends first; the token is printed here and nowhere else.
struct LeaseAcquireCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "acquire",
        abstract: "Lease a simulator: prints `udid: <UDID>` and `token: <token>`, one line each."
    )

    @Option(name: .long, help: "Simulator name or UDID. Defaults to an unleased device on the newest iOS runtime, a shut-down one first.")
    var device: String?

    @Option(name: .long, help: "Clone this shut-down device (by UDID) and lease the clone; releasing the lease deletes the clone.")
    var cloneFrom: String?

    @Option(name: .long, help: "Lease this paired physical iPhone or iPad (a UDID `xcrun devicectl list devices` shows) instead of a simulator; releasing the lease deletes nothing.")
    var physical: String?

    @Option(name: .long, help: "How long the lease lasts: 90s, 30m, 2h.")
    var ttl = "30m"

    @Option(name: .long, help: "The process the lease lives as long as. Defaults to the nearest ancestor that is not a shell — the session asking.")
    var holderPid: Int32?

    func validate() throws {
        if device != nil, cloneFrom != nil {
            throw ValidationError("pass --device or --clone-from, not both — a clone is a device of its own")
        }
        if physical != nil, device != nil || cloneFrom != nil {
            throw ValidationError("--physical leases a phone by its UDID; pass it without --device or --clone-from")
        }
        guard Self.seconds(ttl) != nil else {
            throw ValidationError("--ttl takes a positive whole number of seconds, minutes or hours — 90s, 30m, 2h — not '\(ttl)'")
        }
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) {
            let holder = holderPid ?? HolderProcess.sessionHolder()
            let warning = holderPid == nil ? HolderProcess.unverifiedHolderWarning(holder: holder) : nil
            return try answer(leasing: DeviceLeasing(store: .standard()), holderPID: holder, now: Date(), holderWarning: warning)
        }
    }

    /// What a holder warning tells the caller to do: the store's warning says what may happen, and this command's flag is the remedy.
    static var holderPIDHint: String {
        " — pass --holder-pid <pid> naming the session's long-lived process"
    }

    /// The same run with its three effects and the answer injectable.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        try TimedCall.run(tool: "lease acquire", target: physical ?? cloneFrom ?? device, log: log, emit: emit, emitError: emitError, defaultFailureKind: .runnerFailed, isStdoutPiped: isStdoutPiped, body: body)
    }

    /// `holderWarning` qualifies the answer when the holder chosen may not outlive this command (``HolderProcess/unverifiedHolderWarning(holder:parent:name:)``), with ``holderPIDHint`` after it.
    func answer(leasing: DeviceLeasing, holderPID: Int32, now: Date, holderWarning: String? = nil) throws -> Answer {
        let holderWarning = holderWarning.map { $0 + Self.holderPIDHint }
        let ttlSeconds = Self.seconds(ttl) ?? 0
        if let physical {
            let grant = try leasing.acquirePhysical(udid: physical, ttl: ttlSeconds, holderPID: holderPID, now: now)
            let summary = "leased \(grant.device.name) (\(grant.device.marketingName), iOS \(grant.device.osVersion)), a physical device — releasing it deletes nothing"
            return Answer(
                header: "leases: \(leasing.store.directory.path.tildedPath)",
                verdict: holderWarning.map { .reporting(qualifications: [$0], detail: summary) } ?? .unqualified(summary),
                residue: [
                    "udid: \(physical)",
                    "token: \(grant.lease.token)",
                    "until \(LeaseError.time(grant.lease.expiresAt)), or until pid \(holderPID) exits — walk it with `simwalk device walk --lease <token>`, release it with `simwalk lease release <token>`",
                ]
            )
        }
        let grant = try leasing.acquire(device: device, cloneFrom: cloneFrom, ttl: ttlSeconds, holderPID: holderPID, now: now)
        let made = grant.lease.clonedFrom.map { ", cloned from \($0) — releasing it deletes the clone" } ?? ""
        let summary = "leased \(grant.simulator.name) (iOS \(grant.simulator.osVersion))\(made)"
        let verdict: AnswerVerdict = holderWarning.map { .reporting(qualifications: [$0], detail: summary) } ?? .unqualified(summary)
        return Answer(
            header: "leases: \(leasing.store.directory.path.tildedPath)",
            verdict: verdict,
            residue: [
                "udid: \(grant.simulator.udid)",
                "token: \(grant.lease.token)",
                "until \(LeaseError.time(grant.lease.expiresAt)), or until pid \(holderPID) exits — walk it with --lease <token>, release it with `simwalk lease release <token>`",
            ]
        )
    }

    /// `90s`, `30m`, `2h` as seconds; `nil` for anything else, zero included.
    static func seconds(_ text: String) -> TimeInterval? {
        let units: [Character: TimeInterval] = ["s": 1, "m": 60, "h": 3600]
        guard let unit = text.last.flatMap({ units[$0] }), let count = Int(text.dropLast()), count > 0 else { return nil }
        return TimeInterval(count) * unit
    }
}
