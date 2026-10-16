//
// Copyright © Agulhas Labs
//

import ArgumentParser

/// `simwalk lease …` — exclusive device leases, so a simulator one session walks cannot be picked up or rebooted by another's (Brief §2.4).
struct LeaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lease",
        abstract: "Take, renew, release and list exclusive simulator leases.",
        subcommands: [LeaseAcquireCommand.self, LeaseRenewCommand.self, LeaseReleaseCommand.self, LeaseListCommand.self]
    )
}
