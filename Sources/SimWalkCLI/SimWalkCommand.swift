//
// Copyright © Agulhas Labs
//

import ArgumentParser
import SimWalkCore

/// The `simwalk` command-line face — thin by design; all behaviour lives in `SimWalkCore`.
///
/// An `AsyncParsableCommand` root because `mcp` is one: ArgumentParser calls a subcommand's async `run()` only from an async root, and a synchronous root would have to block a thread on the server's own event loop to start it.
@main
struct SimWalkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simwalk",
        abstract: "Deterministic UI walks of a running iOS app, served as resolved observations.",
        version: SimWalkVersion.current,
        subcommands: [
            ValidateCommand.self,
            WalkCommand.self,
            InspectCommand.self,
            BundleCommand.self,
            UsageCommand.self,
            MCPCommand.self,
            StatuslineCommand.self,
            InstallCommand.self,
            DoctorCommand.self,
            InstallHookCommand.self,
            UninstallHookCommand.self,
            UninstallCommand.self,
            PruneCommand.self,
            LeaseCommand.self,
            SessionCommand.self,
            DiscoverCommand.self,
            MirrorCommand.self,
            DeviceCommand.self,
            HookCommand.self,
        ]
    )
}
