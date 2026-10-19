//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk lease renew <token> [--ttl 30m]` — extends a lease that still holds its device, never shortening it; a lease that has expired or whose holder has exited is refused, since any session may already reclaim it.
struct LeaseRenewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "renew",
        abstract: "Extend a lease to now + --ttl; never shortens one, and refuses a lease that has lapsed."
    )

    @Argument(help: "The token `simwalk lease acquire` printed.")
    var token: String

    @Option(name: .long, help: "How long from now the lease lasts: 90s, 30m, 2h.")
    var ttl = "30m"

    func validate() throws {
        guard LeaseAcquireCommand.seconds(ttl) != nil else {
            throw ValidationError("--ttl takes a positive whole number of seconds, minutes or hours — 90s, 30m, 2h — not '\(ttl)'")
        }
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) {
            try answer(store: .standard(), now: Date())
        }
    }

    /// The same run with its three effects and the answer injectable.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        try TimedCall.run(tool: "lease renew", target: nil, log: log, emit: emit, emitError: emitError, defaultFailureKind: .runnerFailed, isStdoutPiped: isStdoutPiped, body: body)
    }

    func answer(store: LeaseStore, now: Date) throws -> Answer {
        let renewed = try LeaseError.mapping { try store.renew(token: token, ttl: LeaseAcquireCommand.seconds(ttl) ?? 0, now: now) }
        let udid = store.entry(token: token)?.udid ?? "the device"
        return Answer(
            header: "leases: \(store.directory.path.tildedPath)",
            verdict: .unqualified("renewed the lease on \(udid) until \(LeaseError.time(renewed.expiresAt)), or until pid \(renewed.holderPID) exits")
        )
    }
}
