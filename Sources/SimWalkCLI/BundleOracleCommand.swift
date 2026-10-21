//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk bundle oracle <bundle.simwalk> --walkbook <walkbook.json>` — checks the figures a walkbook names against the value oracle it names, in every state the bundle captured (Brief §2.3).
struct BundleOracleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "oracle",
        abstract: "Check the figures a walkbook names against its value oracle: each figure read off a captured screen, asked of the oracle command under every window, one line per figure per state. Exits 2 on any figure that matches no window, is not on screen, has no readable number, or the oracle failed on, and on a screen or a state not captured."
    )

    @Argument(help: "Path to a capture bundle directory.")
    var bundle: String

    @Option(name: .long, help: ArgumentHelp("Path to the walkbook carrying `oracle` and each screen's `figures`.", valueName: "walkbook.json"))
    var walkbook: String

    @Option(name: .long, help: JUnitOutput.help)
    var junit: String?

    func validate() throws {
        try JUnitOutput.validate(junit)
    }

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its effects injectable, for the reason `TimedCall` takes them.
    ///
    /// A failure nothing classified is this command's own code over a bundle and a walkbook it has already read, so it is `tool-error`.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }) throws {
        let output = JUnitOutput.make(junit, command: "bundle oracle")
        try TimedCall.run(tool: "bundle oracle", target: bundle, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped, junit: output) { try answer(junit: output) }
    }

    /// The answer, without the printing — what the MCP face serves, so one verb cannot come to answer differently depending on which face asked.
    ///
    /// `junit` is handed the same checks as test cases, for the CLI's `--junit`; the MCP face passes none.
    func answer(junit: JUnitOutput? = nil) throws -> Answer {
        let opened = try CaptureBundle.read(at: URL(fileURLWithPath: bundle))
        let walkbookURL = URL(fileURLWithPath: walkbook)
        let book = try WalkbookLoader.load(contentsOf: walkbookURL)
        guard let oracle = book.oracle else {
            throw OracleCheckError.noOracle
        }
        let checks = try OracleCheck.checks(of: opened, against: book, oracle: CommandOracle(oracle, walkbookDirectory: walkbookURL.deletingLastPathComponent()))
        let summary = try OracleSummary(checks, of: opened, against: book)
        junit?.report = JUnitOracleCases.report(summary)
        return summary.answer()
    }
}
