//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk device check <udid> | --udid <udid> [--team <TEAM>]` — whether a physical iPhone or iPad can be walked, refused by name before any build.
struct DeviceCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check a physical iPhone or iPad's walk prerequisites: team, pairing, connection, Developer Mode, lock."
    )

    @Argument(help: ArgumentHelp("The iPhone's or iPad's UDID, as `xcrun devicectl list devices` shows it. Or pass it as --udid.", valueName: "udid"))
    var positionalUDID: String?

    @Option(name: .customLong("udid"), help: "The iPhone's or iPad's UDID, the form `device walk` and `device clean` take; pass this or the positional UDID.")
    var udidOption: String?

    @Option(help: "The Apple signing team ID the runner is built under.")
    var team: String?

    /// The UDID, from whichever form carried it; ``validate()`` guarantees exactly one did.
    var udid: String {
        positionalUDID ?? udidOption ?? ""
    }

    func validate() throws {
        if positionalUDID != nil, udidOption != nil {
            throw ValidationError("pass the UDID once, positionally or with --udid, not both")
        }
        if positionalUDID == nil, udidOption == nil {
            throw ValidationError("pass the UDID, positionally (`device check <udid>`) or with --udid <udid>")
        }
    }

    func run() throws {
        try TimedCall.run(tool: "device check", target: udid, log: .standard(), defaultFailureKind: .setupFailed) {
            try answer(shell: Shell())
        }
    }

    func answer(shell: Shell) throws -> Answer {
        let device = try PhysicalDevicePrerequisites.check(udid: udid, team: team, shell: shell)
        return Answer(
            header: "device: \(device.name) · \(device.marketingName) · iOS \(device.osVersion) · \(udid)",
            verdict: .unqualified("walkable"),
            residue: [
                "\(device.pairingState) · \(device.connectionState) (\(device.transportType)) · Developer Mode enabled · unlocked · team \(team ?? "")",
                "a walk may stop on a prompt on the device asking for its passcode to allow UI automation: keep it unlocked and answer the prompt when the walk starts (SimWalk#124)",
            ]
        )
    }
}
