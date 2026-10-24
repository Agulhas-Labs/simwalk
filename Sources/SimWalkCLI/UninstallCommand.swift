//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore

/// `simwalk uninstall` — the inverse of `simwalk install`, taking SimWalk's own registrations out of every agent the install writes to (SimWalk#167).
///
/// Claude Code's half is `uninstall-hook`'s own answer, called rather than copied; Cursor's is the shared installer's uninstall, which keeps another tool's server and hooks and leaves a file with nothing of ours in it unwritten. Every agent is attempted on every run, found or not, and one agent's refusal does not stop the others. The other Fieldwork tools' installs are not undone here: each has an uninstall of its own.
struct UninstallCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "uninstall",
            abstract: "Remove SimWalk from every agent it installs into — Claude Code, Cursor — leaving anything it did not write alone (idempotent).",
            discussion: """
            Claude Code: the MCP server, status line, PreToolUse hook and agent guide, exactly as `uninstall-hook` removes them. Cursor: the simwalk entry in mcp.json and the hook in hooks.json, beside whatever else they hold. Codex is not installed into, so there is nothing to remove there.
            The binary is left in place, as is ~/.simwalk. Other tools' registrations (sift's) are removed by their own uninstall.
            Exits 1 when any agent's removal was refused or failed; the others are still attempted. Nothing found to remove is not a failure.
            """
        )
    }

    @Option(name: .customLong("settings"), help: "Settings file to edit (defaults to ~/.claude/settings.json, or settings.json in CLAUDE_CONFIG_DIR when set).")
    var settings: String?

    @Option(name: .customLong("rule"), help: "The installed agent guide to remove (defaults to ~/.claude/rules/simwalk.md, or rules/simwalk.md in CLAUDE_CONFIG_DIR when set).")
    var rule: String?

    @Option(name: .customLong("cursor-dir"), help: "The directory holding Cursor's mcp.json and hooks.json to remove from (defaults to ~/.cursor).")
    var cursorDirectory: String?

    /// Where each line of the answer goes, injected so a test can read what the uninstall printed.
    var emit: @Sendable (String) -> Void = StandardStreams.emit

    /// Where a refusal goes, injected so a test can read it; the real one is stderr.
    var emitError: @Sendable (String) -> Void = StandardStreams.emitError

    /// What every path is resolved from, injected so a test stands in for the whole machine.
    var environment = ProcessInfo.processInfo.environment

    /// Where Claude Code's files are, injected so a test points the uninstall at a scratch home; `nil` is the machine itself.
    var locations: HookLocations?

    /// The `claude` the server is removed with, injected so a test needs none; `nil` is the one on this machine.
    var claude: (any ClaudeMcpRunner)?

    /// The binary the header names, injected so a test need not run as `simwalk`; `nil` is this process's own path.
    var executable: String?

    func run() throws {
        try run(log: .standard())
    }

    /// The same run against a stated usage log, so a test can read what a refusal recorded without touching the machine's own.
    func run(log: UsageLog?) throws {
        try TimedCall.run(tool: "uninstall", target: nil, log: log, emit: emit, emitError: emitError, defaultFailureKind: .setupFailed) { try answer() }
    }

    /// One section per agent, in `install`'s order, then the verdict that counts them.
    ///
    /// A removal that failed throws, with the whole report as its description, so it is printed on stderr and logged as a failure like every other refusal (SimWalk#167).
    func answer() throws -> Answer {
        let sections = [claudeSection(), cursorSection()]
        let failed = sections.filter { !$0.failures.isEmpty }.map(\.agent)
        var residue: [String] = []
        for section in sections {
            residue += ["\(section.agent):"] + section.lines.map { "  \($0)" }
        }
        residue += ["Codex:", "  codex: simwalk does not install into Codex — nothing to remove"]
        let header = "binary: \((executable ?? ExecutablePath.current).tildedPath)"
        guard failed.isEmpty else {
            throw UninstallRefusal(report: residue + ["not removed from \(failed.joined(separator: ", "))"])
        }
        let removed = sections.filter(\.removed).map(\.agent)
        let qualifications = sections.flatMap(\.qualifications)
        // Something left standing is not "nothing registered": the qualification names it, and the detail does not deny it.
        let unremoved = qualifications.isEmpty ? "nothing of simwalk's was registered" : "nothing removed"
        let detail = removed.isEmpty ? unremoved : "removed from \(removed.joined(separator: ", "))"
        return Answer(header: header, verdict: .reporting(qualifications: qualifications, detail: detail), residue: residue)
    }
}

extension UninstallCommand {
    /// Only the flags come off the command line; the injected parts keep their defaults on the parse path.
    enum CodingKeys: String, CodingKey {
        case settings
        case rule
        case cursorDirectory
    }

    /// An agent's removal failed: the per-agent report, then which agents were not cleared.
    ///
    /// The others were still attempted before it was thrown.
    struct UninstallRefusal: Error, CustomStringConvertible, UsageFailureClassifiable {
        let report: [String]

        var description: String {
            report.joined(separator: "\n")
        }

        var usageFailureKind: UsageFailureKind {
            .setupFailed
        }
    }

    /// What one agent's removal did: the lines it printed, whether anything was taken out, and what stopped it.
    struct Section {
        let agent: String
        var lines: [String] = []
        var removed = false
        var qualifications: [String] = []
        var failures: [String] = []
    }

    /// Claude Code's half: `uninstall-hook`'s answer, whose refusal throws and so becomes this agent's failure.
    private func claudeSection() -> Section {
        var section = Section(agent: "Claude Code")
        do {
            let (answer, removedAnything) = try UninstallHookCommand.uninstall(
                locations: locations ?? HookLocations.standard(settings: settings, rule: rule, environment: environment),
                executable: executable ?? ExecutablePath.current,
                claude: claude ?? ClaudeCLI(environment: environment)
            )
            section.lines = answer.residue
            if case let .qualified(qualifications, _) = answer.verdict {
                section.qualifications = qualifications
            }
            section.removed = removedAnything
        } catch {
            // The shared uninstall throws the `uninstall-hook` wording; under `uninstall` the refusal names this command (SimWalk#197).
            var reported: any Error = error
            if case let HookInstallError.claudeRefused(failures, written) = error {
                reported = HookInstallError.uninstallRefused(failures: failures, written: written)
            }
            section.lines = String(describing: reported).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            section.failures = [String(describing: reported)]
        }
        return section
    }

    /// Cursor's half, from the directory `install` would have written to.
    private func cursorSection() -> Section {
        var section = Section(agent: "Cursor")
        let directory = cursorDirectory.map { URL(fileURLWithPath: $0) } ?? AgentPaths.cursorDirectory(environment: environment)
        do {
            let result = try SimWalkCursorSetup.installer.uninstall(directory: directory)
            // The notes are the verdict's qualifications; printing them here too said each twice (SimWalk#197).
            section.lines = result.printed.filter { !result.outcome.notes.contains($0) }
            if !result.outcome.notes.isEmpty, section.lines.isEmpty {
                section.lines = ["cursor: left partly as it was — see the qualification below"]
            }
            section.removed = result.outcome.changed
            section.qualifications = result.outcome.notes
            section.failures = result.outcome.failures
        } catch {
            section.lines = String(describing: error).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            section.failures = [String(describing: error)]
        }
        return section
    }
}
