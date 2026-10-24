//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk lease release <token>` — gives a lease back, shutting down and deleting the device when the lease created it, shutting it down when the lease found it shut down, and otherwise leaving it as it is.
struct LeaseReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Release a lease; a device the lease cloned is deleted, one it found shut down is shut down again."
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
        let device = switch released.device {
        case .deleted: " and deleted the device it cloned (simctl shutdown, simctl delete)"
        case .shutDown: " and shut the device down, as the lease found it (simctl shutdown)"
        case .alreadyShutDown: "; the device was already shut down, as the lease found it"
        case .gone: "; the device the lease found shut down no longer exists"
        case .leftAsItIs: "; the device was not the lease's to shut down and is left as it is"
        }
        return Answer(
            header: "leases: \(leasing.store.directory.path.tildedPath)",
            verdict: .unqualified("released \(released.entry.udid)\(device)")
        )
    }
}
