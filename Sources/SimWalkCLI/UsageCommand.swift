//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// `simwalk usage` — what this machine has actually asked of the tool, and what those answers stood in for.
///
/// The log has been written since the first verb shipped (Brief §3) and nothing read it, so adoption and failure triage were still anecdote — the thing the log exists to replace. This is the reader.
///
/// **It is not logged itself.** Every other verb appends a line before returning, and a report over the log that appends to the log measures the reading of the measurements: a machine whose usage is checked daily would show `usage` as its most-used verb, which is true and useless. So this one verb answers without recording, and says nothing about a saving either — it stands in for a file the reader already has.
struct UsageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "usage",
        abstract: "Report what has been called, how long it took, what failed and why, and what the answers saved."
    )

    @Option(name: .long, help: "The usage log to read. Defaults to $SIMWALK_USAGE_LOG, else ~/.simwalk/usage.jsonl.")
    var log: String?

    @Option(
        name: .long,
        parsing: .unconditional,
        help: "Only calls made in the last n days (nd) or n hours (nh), such as 3d or 12h. The header states the window.",
        transform: UsageCommand.window
    )
    var since: UsageWindow?

    @Flag(name: .long, help: "Print failure reasons as recorded, and the log's own path in full. Redaction — the default — covers only those two; tool names and an unrecognised failure kind's raw value are never pseudonymised.")
    var unredact = false

    func run() throws {
        try run(emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its two effects and the redaction salt's location injectable, so the report and its exit code are checkable against a log a test wrote — without a test creating a salt in the machine's own `~/.simwalk`.
    ///
    /// It goes through `TimedCall` with **no log**, which is the whole of what "does not record itself" costs: the stream discipline, the refusal wording and the verdict's exit code are the same here as for every other verb, and only the append is skipped. Reading it around `TimedCall` was how a report that declares its own malformed lines came to exit 0 over them.
    ///
    /// `saltFile` is `nil` by default and resolved from `--log` when it is: the salt lives *beside the log actually being read*, not beside the standard one, so `--log` alone — the variable is not the only way to move it — never reaches into the real `~/.simwalk` for it either.
    func run(emit: (String) -> Void, emitError: (String) -> Void, saltFile: URL? = nil, isStdoutPiped: () -> Bool = { false }) throws {
        let fileURL = log.map { URL(fileURLWithPath: $0) } ?? UsageLog.standard().fileURL
        let resolvedSaltFile = saltFile ?? fileURL.deletingLastPathComponent().appendingPathComponent("redaction-salt")
        // Nothing is recorded — there is no log — but the default is stated like every other verb's: an
        // unmapped failure here would be this report's own code, never a caller's argument.
        try TimedCall.run(tool: "usage", target: log, log: nil, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped) {
            // `Redactor.standard(saltFile:)` is built here but not called here — `render`'s `redactor`
            // parameter is an autoclosure, so this expression, salt file included, only runs if a reason
            // is actually about to be printed redacted.
            try UsageReport.render(fileURL: fileURL, window: since, redacting: !unredact, redactor: unredact ? nil : Redactor.standard(saltFile: resolvedSaltFile))
        }
    }

    /// Reads `--since`, resolving it against the clock here at the face — the core takes its time as a parameter and never reads it.
    ///
    /// A spelling that names no window is refused while the arguments are parsed, before anything is read, in words that say what would be accepted. `parsing: .unconditional` is what gets a spelling starting with `-` — `--since -3d` — as far as this validator at all: without it, ArgumentParser reads `-3d` as an unrecognised option and reports its own "Missing value" before this ever runs, over an argument that is a caller's mistake, not the parser's.
    static func window(_ spelling: String) throws -> UsageWindow {
        guard let window = UsageWindow(spelling: spelling, now: Date()) else {
            // "is neither" fit a wrong-unit spelling like `3w`; it overclaimed for `0d`, which is
            // shaped exactly like an accepted one and refused only for being zero. Worded so both are true.
            throw ValidationError("--since takes a whole number of days or hours greater than zero, back from now, such as 3d or 12h; \(spelling) does not")
        }
        return window
    }
}
