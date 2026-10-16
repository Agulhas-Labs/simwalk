//
// Copyright © Agulhas Labs
//

import ArgumentParser

/// `simwalk device …` — walks on a physical iPhone or iPad (SimWalk#116).
struct DeviceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "Check a physical iPhone or iPad can be walked, and walk on it.",
        subcommands: [DeviceCheckCommand.self, DeviceWalkCommand.self, DeviceCleanCommand.self]
    )
}
