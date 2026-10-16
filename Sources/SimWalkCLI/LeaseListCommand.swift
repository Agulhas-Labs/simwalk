//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk lease list` — every lease on the machine: its device, its holder, its expiry and whether it is reclaimable.
///
/// Tokens are never listed: a token is what lets a walk use and reboot the device.
struct LeaseListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the machine's simulator leases."
    )

    func run() throws {
        try TimedCall.run(tool: "lease list", target: nil, log: .standard(), defaultFailureKind: .toolError) {
            Self.answer(store: .standard(), now: Date())
        }
    }

    static func answer(store: LeaseStore, now: Date) -> Answer {
        let entries = store.all()
        let lines = entries.map { entry in
            let lease = entry.lease
            let holder = HolderProcess.name(of: lease.holderPID).map { "pid \(lease.holderPID) (\($0))" } ?? "pid \(lease.holderPID)"
            let made = lease.clonedFrom.map { " · clone of \($0), deleted on release" } ?? ""
            let physical = lease.physicalDevice == true ? " · physical device" : ""
            let state = store.isHeld(lease, now: now) ? "held" : "reclaimable"
            return "\(entry.udid) · \(state) · \(holder) · until \(LeaseError.time(lease.expiresAt))\(made)\(physical)"
        }
        let held = entries.filter { store.isHeld($0.lease, now: now) }.count
        return Answer(
            header: "leases: \(store.directory.path.tildedPath)",
            verdict: .unqualified(entries.isEmpty ? "no leases" : "\(entries.count) lease\(entries.count == 1 ? "" : "s"), \(held) held"),
            residue: lines
        )
    }
}
