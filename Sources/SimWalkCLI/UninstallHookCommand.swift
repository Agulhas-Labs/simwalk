//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkMCP

/// `simwalk uninstall-hook` — the inverse of `install-hook`, taking this tool's registrations back out of Claude Code.
///
/// It undoes exactly what the install wrote — the status line in whichever of its two places it went, its own `PreToolUse` hook entry, the user rule, and the MCP entry — and nothing else. Everything the install refused to touch on the way in is refused on the way out too: a status line somebody built themselves, a rule this tool did not write, and a rule that is a symlink into a checkout.
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
            claude: ClaudeCommandLine.resolve()
        )
    }

    /// The same uninstall against stated locations and a stated `claude`.
    ///
    /// The files go first and the call out of the process last, mirroring the install for the same reason: the step that reaches another tool is the one that can fail in a way this cannot put back.
    static func answer(locations: HookLocations, executable: String, claude: ClaudeCommandLine?) throws -> Answer {
        var qualifications: [String] = []
        var settingsBackedUp = false
        var residue = try removeStatusline(locations: locations, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp)
        try residue.append(removePreToolUseHook(settings: locations.settings, settingsBackedUp: &settingsBackedUp))
        residue.append(removeGuide(locations.guide, qualifications: &qualifications))
        residue.append(removeServer(claude))
        residue.append("      \(SimWalkPaths.home.path.tildedPath) is left as it is — delete that directory to remove the usage log, the status line's cache, and the walk runner's snapshots and builds too")
        return Answer(
            header: "binary: \(executable.tildedPath)",
            verdict: .reporting(qualifications: qualifications, detail: "removed from Claude Code"),
            residue: residue
        )
    }
}

private extension UninstallHookCommand {
    /// The MCP registration, when there is a `claude` to take it out with.
    ///
    /// Without `claude` the server entry is left alone, since nothing can remove it, and the rest of the uninstall goes ahead.
    static func removeServer(_ claude: ClaudeCommandLine?) -> String {
        guard let claude else {
            return "mcp: 'claude' is not on PATH — nothing could be removed, and nothing it registered can run"
        }
        return claude.removeServer() ? "mcp: removed from user scope" : "mcp: nothing registered"
    }

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
            backUpSettingsOnce(original, to: settingsURL, backedUp: &settingsBackedUp)
            try updated.write(to: settingsURL, options: .atomic)
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
    static func removePreToolUseHook(settings settingsURL: URL, settingsBackedUp: inout Bool) throws -> String {
        let path = settingsURL.path.tildedPath
        let original = try? Data(contentsOf: settingsURL)
        switch try PreToolUseRegistration.remove(from: original, path: path) {
        case let .removed(updated, command):
            backUpSettingsOnce(original, to: settingsURL, backedUp: &settingsBackedUp)
            try updated.write(to: settingsURL, options: .atomic)
            return "hook: PreToolUse removed from \(path) — \(command.tildedPath)"
        case .absent:
            return "hook: nothing registered"
        }
    }

    /// Backs up `settingsURL` from `original` bytes before this run's first rewrite of it, and never again — a second step editing the same file in the same run would otherwise back up what the first step already edited, overwriting the pristine copy.
    static func backUpSettingsOnce(_ original: Data?, to settingsURL: URL, backedUp: inout Bool) {
        guard !backedUp, let original, !original.isEmpty else { return }
        try? original.write(to: settingsURL.appendingPathExtension("bak-simwalk"))
        backedUp = true
    }

    /// The user rule, when it is the file the install wrote.
    ///
    /// A rule left behind would go on telling an agent to call tools that are no longer registered, which is the one kind of stale configuration worth removing — but `~/.claude/rules/simwalk.md` is also the obvious name for somebody's own notes about this tool, so only a copy carrying the install's own marker is taken. A symlink is neither: it points into a checkout the install deliberately did not write through, and deleting it would take the link with it.
    static func removeGuide(_ guide: AgentGuide, qualifications: inout [String]) -> String {
        let path = guide.fileURL.path.tildedPath
        do {
            switch try guide.remove() {
            case .removed:
                return "rule: removed — \(path)"
            case .absent:
                return "rule: nothing installed"
            case .notOurs:
                qualifications.append("the agent guide was not written by this tool")
                return "rule: left in place — \(path) carries no `install-hook` marker, so it is not ours to delete"
            case let .symlink(target):
                qualifications.append("the agent guide is a symlink and was left in place")
                return "rule: \(path) is a symlink to \(target.tildedPath) — left as is"
            }
        } catch {
            qualifications.append("the agent guide could not be removed")
            return "rule: left behind — \(path): \(error)"
        }
    }
}
