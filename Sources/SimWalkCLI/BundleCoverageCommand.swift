//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// `simwalk bundle coverage <path>` — the controls a bundle's captured trees expose that no route step follows (SimWalk#35).
struct BundleCoverageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coverage",
        abstract: "List the controls a bundle's screens show that no route step reaches, each as the step that would reach it."
    )

    @Argument(help: "Path to a capture bundle directory.")
    var bundle: String

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its effects injectable, for `BundleAuditCommand`'s reason: the contract is an exit code, checkable only against the command itself.
    ///
    /// Uncovered controls are a qualified answer, and `TimedCall` exits on the verdict.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }) throws {
        try TimedCall.run(tool: "bundle coverage", target: bundle, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped) {
            try answer()
        }
    }

    /// The answer, without the printing.
    func answer() throws -> Answer {
        let opened = try CaptureBundle.read(at: URL(fileURLWithPath: bundle))
        return try ControlCoverageSummary(ControlCoverage(opened).findings(), of: opened).answer()
    }
}
