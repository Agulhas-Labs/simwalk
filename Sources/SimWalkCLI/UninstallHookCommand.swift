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

    @Option(name: .customLong("settings"), help: "Settings file to edit (defaults to ~/.claude/settings.json, or settings.json in CLAUDE_CONFIG_DIR when set).")
    var settings: String?

    @Option(name: .customLong("rule"), help: "The installed agent guide to remove (defaults to ~/.claude/rules/simwalk.md, or rules/simwalk.md in CLAUDE_CONFIG_DIR when set).")
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
        let environment = ProcessInfo.processInfo.environment
        return try Self.answer(
            locations: HookLocations.standard(settings: settings, rule: rule, environment: environment),
            executable: ExecutablePath.current,
            claude: ClaudeCLI(environment: environment)
        )
    }

    /// The same uninstall against stated locations and a stated `claude`.
    ///
    /// The files go first and the call out of the process last, mirroring the install for the same reason: the step that reaches another tool is the one that can fail in a way this cannot put back.
    static func answer(locations: HookLocations, executable: String, claude: any ClaudeMcpRunner) throws -> Answer {
        try uninstall(locations: locations, executable: executable, claude: claude).answer
    }

    /// ``answer(locations:executable:claude:)`` and whether the run took anything out, decided from what each step did rather than from the words of its report (SimWalk#167).
    ///
    /// A file counts when the step rewrote or deleted it; the server counts when it was registered before the call and is not after. After the server's removal the config is read again: a `claude` that is not on PATH reports its manual command as an ordinary line, not a failure, so the registration still standing is only visible there, and it qualifies the answer instead of letting "nothing registered" stand.
    static func uninstall(locations: HookLocations, executable: String, claude: any ClaudeMcpRunner) throws -> (answer: Answer, removedAnything: Bool) {
        var qualifications: [String] = []
        var settingsBackedUp = false
        var removedAnything = false
        var residue = try removeStatusline(locations: locations, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp, removedAnything: &removedAnything)
        try residue.append(removePreToolUseHook(settings: locations.settings, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp, removedAnything: &removedAnything))
        let rule = SimWalkClaudeSetup.rule.uninstall(destination: locations.rule)
        let backup = SimWalkClaudeSetup.rule.uninstall(destination: SettingsBackupFile.url(beside: locations.rule, tool: .simwalk))
        let registeredBefore = serverRegistered(in: locations.config)
        let server = SimWalkClaudeSetup.mcp.uninstall(config: locations.config, runner: claude)
        let registeredAfter = serverRegistered(in: locations.config)
        residue += rule.lines + rule.notes + backup.lines + backup.notes
        let failures = rule.failures + backup.failures + server.failures
        // A refusal keeps Fieldwork's own server line, which carries the removal command for a `claude` that is not on PATH: the qualification below, which would otherwise state it, is never reached (SimWalk#197).
        guard failures.isEmpty else {
            throw HookInstallError.claudeRefused(failures: failures, written: residue + server.lines + server.notes)
        }
        // Past the refusal the qualification states that command for a registration still standing; left in the line, it would say it twice (SimWalk#197).
        let command = SimWalkClaudeSetup.server.removalCommand
        let serverLines = registeredAfter
            ? server.lines.map { $0.contains(command) ? "mcp: `claude` is not on PATH — the registration was left as it was" : $0 }
            : server.lines
        residue += serverLines + server.notes
        if registeredAfter {
            qualifications.append("the simwalk server is still registered in \(locations.config.path.tildedPath) — remove it with: \(SimWalkClaudeSetup.server.removalCommand)")
        }
        removedAnything = removedAnything || rule.changed || backup.changed || (registeredBefore && !registeredAfter)
        residue.append("      \(SimWalkPaths.home.path.tildedPath) is left as it is — delete that directory to remove the usage log, the status line's cache, and the walk runner's snapshots and builds too")
        let answer = Answer(
            header: "binary: \(executable.tildedPath)",
            verdict: .reporting(qualifications: qualifications, detail: "removed from Claude Code"),
            residue: residue
        )
        return (answer, removedAnything)
    }
}

private extension UninstallHookCommand {
    /// Whether Claude Code's config at `config` registers this tool's server at user scope, or at local scope in any project: both places its removal reaches.
    ///
    /// The local half mirrors Fieldwork's `ClaudeMcpServer.hasLocalEntry(in:)`, which it does not export.
    static func serverRegistered(in config: URL) -> Bool {
        if SimWalkClaudeSetup.server.userEntry(in: config) != nil {
            return true
        }
        guard let data = try? Data(contentsOf: config),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let projects = object["projects"] as? [String: Any]
        else { return false }
        return projects.values.contains { project in
            ((project as? [String: Any])?["mcpServers"] as? [String: Any])?[SimWalkClaudeSetup.server.name] != nil
        }
    }

    /// The status line, from whichever of its two homes it went into.
    ///
    /// Both are checked rather than only the one this machine would install into today, because a machine that gained or lost sift between the install and the uninstall would otherwise keep whichever half no longer matches.
    static func removeStatusline(locations: HookLocations, qualifications: inout [String], settingsBackedUp: inout Bool, removedAnything: inout Bool) throws -> [String] {
        var lines: [String] = []
        if let segments = locations.segments {
            switch try segments.remove() {
            case .removed:
                removedAnything = true
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
            removedAnything = true
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
    static func removePreToolUseHook(settings settingsURL: URL, qualifications: inout [String], settingsBackedUp: inout Bool, removedAnything: inout Bool) throws -> String {
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
        removedAnything = true
        return "hook: PreToolUse removed from \(path) — \(command.tildedPath)"
    }
}
