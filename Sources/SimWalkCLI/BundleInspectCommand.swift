//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore

/// `simwalk bundle inspect <path>` — summarises what a walk did, refusals and their evidence included.
///
/// **It exits 2 over a qualified bundle**, as `walk` and `bundle audit` do. It used to print a bundle's shortfall and its unsettled captures and exit 0 over them, which made an incomplete bundle indistinguishable from a clean one to anything not parsing stdout — the same defect the audit's exit code was added to fix, on the one verb most likely to be run against a bundle nobody watched being written.
struct BundleInspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Summarise a capture bundle's manifest: screens, outcomes, refusals."
    )

    @Argument(help: "Path to a capture bundle directory.")
    var bundle: String

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped)
    }

    /// The same run with its three effects injectable, for the reason `TimedCall` takes them: the contract this command holds is an exit code, and an exit code is only checkable against the command itself.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }) throws {
        try run(log: log, emit: emit, emitError: emitError, isStdoutPiped: isStdoutPiped) { try answer() }
    }

    /// The same run with the answer itself injectable too, so the kind an unmapped failure records can be checked without a bundle that could produce one.
    ///
    /// Every failure of the bundle argument is a `CaptureBundleError`, classified on its own account — a tree the runner wrote that does not decode is `runner-failed` there, not here. What is left is this command's own code over a bundle it has already read, so an unmapped failure is `tool-error`, never a caller's mistake.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        try TimedCall.run(tool: "bundle inspect", target: bundle, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped, body: body)
    }

    /// The answer, without the printing — what the MCP face serves, so one verb cannot come to answer differently depending on which face asked.
    func answer() throws -> Answer {
        let opened = try CaptureBundle.read(at: URL(fileURLWithPath: bundle))
        // The walk summary answers "what happened"; the contents answer "what is here now". They are the
        // same answer only while someone is watching the walk that wrote it — which is exactly when
        // nobody runs `inspect`.
        let contents = CaptureBundleContents(opened)
        return CaptureBundleSummary(opened).answer(appending: Self.contentsReport(contents))
    }

    /// The on-disk half: what each screen holds, how big the bundle is, and any artefact that exists while holding nothing.
    private static func contentsReport(_ contents: CaptureBundleContents) -> [String] {
        let screens = contents.screens()
        var lines = ["on disk — \(ByteSize.short(contents.totalBytes())) across \(screens.count) screen\(screens.count == 1 ? "" : "s")"]
        for screen in screens where screen.captureCount > 0 {
            let unmeasurable = screen.unmeasurableCount == 0
                ? ""
                : " (+ \(screen.unmeasurableCount) artefact\(screen.unmeasurableCount == 1 ? "" : "s") that could not be measured)"
            lines.append("  \(screen.id) — \(screen.captureCount) capture\(screen.captureCount == 1 ? "" : "s"), \(ByteSize.short(screen.bytes))\(unmeasurable)")
        }
        for screen in screens where screen.captureCount == 0 {
            lines.append("  \(screen.id) — no captures")
        }
        // Presence is already guaranteed by `CaptureBundle.read`; size is the thing it cannot speak to, and
        // a zero-byte screenshot passes every structural check while depicting nothing.
        let empty = contents.emptyArtefacts()
        if !empty.isEmpty {
            lines.append("")
            lines.append("⚠ \(empty.count) artefact\(empty.count == 1 ? " is" : "s are") empty — present, and holding nothing:")
            lines += empty.map { "    \($0.path)" }
        }
        // Separate from empty, because "I looked and it holds nothing" and "I could not look" are
        // different facts and only one of them is about the walk. Reporting a failed `stat` as zero bytes
        // asserted the first while knowing neither.
        let unmeasurable = contents.unmeasurableArtefacts()
        if !unmeasurable.isEmpty {
            lines.append("")
            lines.append("⚠ \(unmeasurable.count) artefact\(unmeasurable.count == 1 ? "'s size" : "s' sizes") could not be read — the size above is short by whatever they hold:")
            lines += unmeasurable.map { "    \($0.path)" }
        }
        return lines
    }
}
