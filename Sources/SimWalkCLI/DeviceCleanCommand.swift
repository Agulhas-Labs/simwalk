//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk device clean (--udid <udid> | --lease <token>)` — uninstalls the runner app from a physical iPhone or iPad, for a user who wants it gone (SimWalk#116).
///
/// A device walk keeps the runner installed and empties its container; this is the way to remove the app itself. Only the runner is ever named, never a walkbook's app.
struct DeviceCleanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Uninstall the runner app from a physical iPhone or iPad."
    )

    @Option(name: .customLong("udid"), help: "The iPhone's or iPad's UDID. The command leases it for its length; pass this or --lease.")
    var requestedUDID: String?

    @Option(help: "The token of a lease on the phone (`simwalk lease acquire --physical <udid>`); the lease names the device. It is renewed and left to its holder.")
    var lease: String?

    @Option(help: "The runner's bundle identifier, when it is not the default.")
    var runnerBundleId: String?

    func validate() throws {
        if requestedUDID != nil, lease != nil {
            throw ValidationError("pass --udid or --lease, not both — a lease names its device")
        }
        if requestedUDID == nil, lease == nil {
            throw ValidationError("pass --udid <udid> (the command leases the phone itself) or --lease <token> (a lease from `simwalk lease acquire --physical <udid>`)")
        }
    }

    func run() throws {
        try TimedCall.run(tool: "device clean", target: requestedUDID ?? "lease", log: .standard(), defaultFailureKind: .setupFailed) {
            try answer(shell: Shell(), leases: .standard(), holderPID: getpid(), now: Date())
        }
    }

    /// The lease comes before any `devicectl` call, as in `device walk`.
    func answer(shell: Shell, leases: LeaseStore, holderPID: Int32, now: Date = Date()) throws -> Answer {
        let held: WalkLease
        if let lease {
            held = try WalkLease.presentedPhysical(token: lease, store: leases)
            try held.requireRenewed(now: now)
        } else {
            held = try WalkLease.takePhysical(udid: requestedUDID ?? "", store: leases, holderPID: holderPID, now: now)
        }
        defer { held.release() }
        let outcome = try RunnerAppUninstall(udid: held.udid, runnerBundleID: runnerBundleId, shell: shell).run()
        return Answer(header: "device: \(held.udid) · runner app", verdict: .unqualified(outcome.line))
    }
}
