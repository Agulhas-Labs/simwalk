//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkMCP

/// `simwalk uninstall-hook` — the inverse of `install-hook`, taking this tool's registrations back out of Claude Code.
///
/// It undoes exactly what the install wrote — the status line in whichever of its two places it went, its own `PreToolUse` hook entry, the user rule, and the MCP entry — and nothing else. Everything the install refused to touch on the way in is refused on the way out too: a status line somebody built themselves and a rule that is a symlink into a checkout.
struct UninstallHookCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "uninstall-hook",
            abstract: "Remove this tool's MCP server, status line, PreToolUse hook and agent guide from Claude Code (idempotent; leaves anything it did not write alone)."
        )
    }

    @Option(name: .customLong("settings"), help: "Settings file to edit (defaults to ~/.claude/settings.json).")
    var settings: String?

    @Option(name: .customLong("rule"), help: "The installed agent guide to remove (defaults to ~/.claude/rules/simwalk.md).")
    var rule: String?

    func run() throws {
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) { try answer() }
    }

    /// The same run with its three effects and the answer itself injectable, so the fallback kind an unmapped failure records can be checked without a `claude` on the machine or a real home directory.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        // An unmapped failure here is Claude Code's own configuration or this tool's own registration
        // files — never a caller's argument.
        try TimedCall.run(tool: "uninstall-hook", target: nil, log: log, emit: emit, emitError: emitError, defaultFailureKind: .setupFailed, isStdoutPiped: isStdoutPiped, body: body)
    }

    func answer() throws -> Answer {
        try Self.answer(
            locations: HookLocations.standard(settings: settings, rule: rule),
            executable: ExecutablePath.current,
            claude: ClaudeCLI(environment: ProcessInfo.processInfo.environment)
        )
    }

    /// The same uninstall against stated locations and a stated `claude`.
    ///
    /// The files go first and the call out of the process last, mirroring the install for the same reason: the step that reaches another tool is the one that can fail in a way this cannot put back.
    static func answer(locations: HookLocations, executable: String, claude: any ClaudeMcpRunner) throws -> Answer {
        var qualifications: [String] = []
        var settingsBackedUp = false
        var residue = try removeStatusline(locations: locations, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp)
        try residue.append(removePreToolUseHook(settings: locations.settings, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp))
        let rule = SimWalkClaudeSetup.rule.uninstall(destination: locations.rule)
        let backup = SimWalkClaudeSetup.rule.uninstall(destination: SettingsBackupFile.url(beside: locations.rule, tool: .simwalk))
        let server = SimWalkClaudeSetup.mcp.uninstall(config: locations.config, runner: claude)
        residue += rule.lines + rule.notes + backup.lines + backup.notes + server.lines + server.notes
        let failures = rule.failures + backup.failures + server.failures
        guard failures.isEmpty else {
            throw HookInstallError.claudeRefused(failures: failures, written: residue)
        }
        residue.append("      \(SimWalkPaths.home.path.tildedPath) is left as it is — delete that directory to remove the usage log, the status line's cache, and the walk runner's snapshots and builds too")
        return Answer(
            header: "binary: \(executable.tildedPath)",
            verdict: .reporting(qualifications: qualifications, detail: "removed from Claude Code"),
            residue: residue
        )
    }
}

private extension UninstallHookCommand {
    /// The status line, from whichever of its two homes it went into.
    ///
    /// Both are checked rather than only the one this machine would install into today, because a machine that gained or lost sift between the install and the uninstall would otherwise keep whichever half no longer matches.
    static func removeStatusline(locations: HookLocations, qualifications: inout [String], settingsBackedUp: inout Bool) throws -> [String] {
        var lines: [String] = []
        if let segments = locations.segments {
            switch try segments.remove() {
            case .removed:
                lines.append("statusline: removed — \(segments.fileURL.path.tildedPath)")
            case .absent:
                break
            case .notOurs:
                qualifications.append("a file this tool did not write sits where its status-line segment goes")
                lines.append("statusline: left alone — \(segments.fileURL.path.tildedPath) was not written by this tool")
            }
        }

        let settingsURL = locations.settings
        let path = settingsURL.path.tildedPath
        let original = try? Data(contentsOf: settingsURL)
        switch try StatuslineRegistration.remove(from: original, path: path) {
        case let .removed(updated, command):
            try SettingsRewrite.write(updated, to: settingsURL, original: original, backedUp: &settingsBackedUp, qualifications: &qualifications)
            lines.append("statusline: removed from \(path) — \(command.tildedPath)")
        case .absent:
            break
        case let .notOurs(existing):
            qualifications.append("the status line slot holds something this tool did not register")
            lines.append("statusline: left alone — \(path) holds \(existing)")
        }

        return lines.isEmpty ? ["statusline: nothing registered"] : lines
    }

    /// This tool's `PreToolUse` entry, and no other hook beside it (SimWalk#14).
    static func removePreToolUseHook(settings settingsURL: URL, qualifications: inout [String], settingsBackedUp: inout Bool) throws -> String {
        let path = settingsURL.path.tildedPath
        let original = try? Data(contentsOf: settingsURL)
        let removal: HookRegistration.Removal
        do {
            removal = try SimWalkClaudeSetup.hooks.remove(from: original, event: SimWalkClaudeSetup.preToolUse)
        } catch HookRegistrationError.hooksNotMergeable {
            // A shape this tool never wrote holds nothing of its own to take back.
            return "hook: nothing registered"
        }
        guard let command = removal.removed.first else {
            return "hook: nothing registered"
        }
        try SettingsRewrite.write(removal.data, to: settingsURL, original: original, backedUp: &settingsBackedUp, qualifications: &qualifications)
        return "hook: PreToolUse removed from \(path) — \(command.tildedPath)"
    }
}
