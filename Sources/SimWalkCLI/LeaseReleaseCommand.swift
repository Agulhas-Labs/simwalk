//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk lease release <token>` — gives a lease back, shutting down and deleting the device when the lease created it, and only then.
struct LeaseReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Release a lease; a device the lease cloned is shut down and deleted."
    )

    @Argument(help: "The token `simwalk lease acquire` printed.")
    var token: String

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) {
            try answer(leasing: DeviceLeasing(store: .standard()))
        }
    }

    /// The same run with its three effects and the answer injectable.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        try TimedCall.run(tool: "lease release", target: nil, log: log, emit: emit, emitError: emitError, defaultFailureKind: .runnerFailed, isStdoutPiped: isStdoutPiped, body: body)
    }

    func answer(leasing: DeviceLeasing) throws -> Answer {
        let released = try leasing.release(token: token)
        let deleted = released.lease.createdDevice ? " and deleted the device it cloned (simctl shutdown, simctl delete)" : "; the device was not the lease's to delete and is left as it is"
        return Answer(
            header: "leases: \(leasing.store.directory.path.tildedPath)",
            verdict: .unqualified("released \(released.udid)\(deleted)")
        )
    }
}
