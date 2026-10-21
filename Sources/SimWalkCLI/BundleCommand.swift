//
// Copyright © Agulhas Labs
//

import ArgumentParser

/// `simwalk bundle …` — the capture-bundle group.
///
/// It carries no work of its own; the runner's other bundle verbs land here as they arrive.
struct BundleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bundle",
        abstract: "Work with capture bundles written by a walk.",
        subcommands: [BundleInspectCommand.self, BundleAuditCommand.self, BundleDiffCommand.self, BundleOracleCommand.self, BundleCoverageCommand.self, BundleScreenCommand.self, BundleLabelsCommand.self]
    )
}
