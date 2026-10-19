//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import Testing

/// `simwalk install` composes the shared library's detection, selection and Cursor installer with `install-hook`'s own Claude Code answer, so the claims worth pinning are the seams: that Cursor's entries sit beside another tool's, that a re-run changes nothing, that the Claude step is `install-hook`'s, and that no terminal and no flag installs nothing.
struct InstallCommandTests {
    /// SimWalk lands in a Cursor directory that already serves another tool, both tools stay, and a second run leaves the bytes alone.
    @Test
    func cursorIsInstalledBesideAnotherToolAndASecondRunChangesNothing() throws {
        let scratch = try HookInstallTests.Scratch()
        let cursor = scratch.directory.url.appendingPathComponent("cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        let mcp = cursor.appendingPathComponent("mcp.json")
        let hooks = cursor.appendingPathComponent("hooks.json")
        try Data(#"{"mcpServers":{"sift":{"command":"/opt/sift/bin/sift","args":["mcp"]}}}"#.utf8).write(to: mcp)
        try Data(#"{"version":1,"hooks":{"preToolUse":[{"command":"\"/opt/sift/bin/sift\" pre-tool-use --agent cursor"}]}}"#.utf8).write(to: hooks)
        let first = Output()

        try Self.command(["--agent", "cursor", "--cursor-dir", cursor.path], scratch: scratch, output: first).run()

        let servers = try Self.object(mcp)["mcpServers"] as? [String: Any]
        #expect(servers?["sift"] != nil)
        #expect(servers?["simwalk"] != nil)
        let commands = try Self.preToolUseCommands(hooks)
        #expect(commands.contains { $0.contains("/opt/sift/bin/sift") })
        #expect(commands.contains("/opt/simwalk/bin/simwalk hook pre-tool-use --agent cursor"))
        let written = try (Data(contentsOf: mcp), Data(contentsOf: hooks))

        let second = Output()
        try Self.command(["--agent", "cursor", "--cursor-dir", cursor.path], scratch: scratch, output: second).run()

        #expect(try (Data(contentsOf: mcp), Data(contentsOf: hooks)) == written)
        #expect(second.text.contains("mcp: already registered"))
        #expect(second.text.contains("hooks: already registered"))
    }

    /// The Claude step is `install-hook`'s answer: the same settings entry and the same calls to `claude`.
    @Test
    func claudeRegistersWhatInstallHookRegisters() throws {
        let scratch = try HookInstallTests.Scratch()
        let recorder = scratch.claude()
        let output = Output()

        try Self.command(["--agent", "claude"], scratch: scratch, output: output, claude: recorder).run()

        let settings = try String(contentsOf: scratch.settings, encoding: .utf8)

        #expect(settings.contains("hook pre-tool-use"))
        #expect(recorder.adds.count == 1)
        #expect(recorder.adds.first?.contains("simwalk") == true)
        #expect(output.text.contains("mcp: registered simwalk"))
    }

    /// The Claude step runs `install-hook` as the machine would, handed only its `--guide`: the guide installed is the one named, and the settings hook is registered.
    @Test
    func claudeStepInstallsTheGuideItWasGivenAndRegistersTheHook() throws {
        let scratch = try HookInstallTests.Scratch()
        let output = Output()
        try Data("---\npaths:\n  - \"**/project.yml\"\n---\n\n# The guide named with --guide\n".utf8).write(to: scratch.guideSource)

        try Self.command(["--agent", "claude"], scratch: scratch, output: output).run()

        let rule = try String(contentsOf: scratch.guide, encoding: .utf8)
        let settings = try String(contentsOf: scratch.settings, encoding: .utf8)

        #expect(rule.contains("# The guide named with --guide"))
        #expect(settings.contains("hook pre-tool-use"))
    }

    /// A first install says what it did and what to do next.
    @Test
    func aFirstClaudeInstallIsSaidToBeInstalled() throws {
        let scratch = try HookInstallTests.Scratch()
        let output = Output()

        try Self.command(["--agent", "claude"], scratch: scratch, output: output).run()

        let line = try #require(output.lines.first { $0.hasPrefix("  Claude Code:") })

        #expect(line.contains("installed — wrote"), "\(line)")
        #expect(line.contains("registered the MCP server"))
        #expect(line.contains("Next: start a new Claude Code session"))
    }

    /// A second run that changes nothing says so, whatever the verdict.
    @Test
    func aSecondClaudeInstallIsSaidToBeAlreadyInstalled() throws {
        let scratch = try HookInstallTests.Scratch()
        try Self.command(["--agent", "claude"], scratch: scratch, output: Output()).run()
        let output = Output()

        try Self.command(["--agent", "claude"], scratch: scratch, output: output).run()

        let line = try #require(output.lines.first { $0.hasPrefix("  Claude Code:") })

        #expect(line == "  Claude Code: already installed, nothing to do", "\(output.text)")
    }

    /// A first install whose verdict is qualified (the guide could not be found) is still an install.
    @Test
    func aQualifiedFirstClaudeInstallIsStillSaidToBeInstalled() throws {
        let scratch = try HookInstallTests.Scratch()
        let output = Output()
        try FileManager.default.removeItem(at: scratch.guideSource)

        try Self.command(["--agent", "claude"], scratch: scratch, output: output).run()

        let line = try #require(output.lines.first { $0.hasPrefix("  Claude Code:") })

        #expect(line.contains("installed — wrote"), "\(output.text)")
    }

    /// With no `claude` on PATH nothing of Claude Code's is registered, and the summary says that, with the reason, rather than "already installed".
    @Test
    func noClaudeOnPathIsSaidToBeNotInstalledWithItsReason() throws {
        let scratch = try HookInstallTests.Scratch()
        let output = Output()
        var command = try Self.command(["--agent", "claude"], scratch: scratch, output: output)
        command.claudeSurroundings = InstallHookCommand.Surroundings(locations: scratch.locations(), claude: nil, runnerSource: scratch.runnerSource)

        #expect(throws: ExitCode.self) { try command.run() }

        let line = try #require(output.lines.first { $0.hasPrefix("  Claude Code:") })

        #expect(line.contains("failed — 'claude' is not on PATH"), "\(output.text)")
        #expect(!output.text.contains("already installed"))
        #expect(!FileManager.default.fileExists(atPath: scratch.settings.path))
    }

    /// Codex is not supported: said in one line, never a failure.
    @Test
    func codexIsSkippedWithoutFailing() throws {
        let scratch = try HookInstallTests.Scratch()
        let output = Output()

        try Self.command(["--agent", "codex"], scratch: scratch, output: output).run()

        #expect(output.lines.contains("codex: not supported by simwalk yet — skipped"))
    }

    /// With no terminal to ask on and no flag, nothing is installed and the text names `simwalk install --yes`.
    @Test
    func noTerminalAndNoFlagsInstallsNothing() throws {
        let scratch = try HookInstallTests.Scratch()
        let home = scratch.directory.url.appendingPathComponent("home", isDirectory: true)
        let cursor = home.appendingPathComponent(".cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        let output = Output()

        try Self.command([], scratch: scratch, output: output, environment: ["HOME": home.path, "PATH": ""]).run()

        #expect(output.text.contains("simwalk install --yes"))
        #expect(!FileManager.default.fileExists(atPath: cursor.appendingPathComponent("mcp.json").path))
        #expect(!FileManager.default.fileExists(atPath: scratch.settings.path))
    }

    // MARK: - Fixtures

    private static var binary: String {
        "/opt/simwalk/bin/simwalk"
    }

    /// The command as parsed from `arguments`, with the machine, the terminal's absence, the binary and `install-hook`'s answer all stood in for.
    private static func command(
        _ arguments: [String],
        scratch: HookInstallTests.Scratch,
        output: Output,
        claude: RecordingClaude? = nil,
        environment: [String: String]? = nil
    ) throws -> InstallCommand {
        var command = try InstallCommand.parse(arguments + ["--guide", scratch.guideSource.path])
        command.emit = output.emit
        command.machine = AgentDetection.Machine(environment: environment ?? ["HOME": scratch.directory.url.path, "PATH": ""])
        command.terminal = InstallTerminal(isInteractive: false, ask: { _ in nil })
        command.executable = binary
        command.familyLaunch = { _, _, _ in 0 }
        command.claudeSurroundings = InstallHookCommand.Surroundings(locations: scratch.locations(), claude: claude ?? scratch.claude(), runnerSource: scratch.runnerSource)
        return command
    }

    private static func object(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], sourceLocation: sourceLocation)
    }

    private static func preToolUseCommands(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String] {
        let hooks = try #require(object(url, sourceLocation: sourceLocation)["hooks"] as? [String: Any], sourceLocation: sourceLocation)
        let entries = try #require(hooks["preToolUse"] as? [[String: Any]], sourceLocation: sourceLocation)
        return entries.compactMap { $0["command"] as? String }
    }
}

extension InstallCommandTests {
    /// What the command printed, in order.
    final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var printed: [String] = []

        var emit: @Sendable (String) -> Void {
            { [self] line in lock.withLock { printed.append(line) } }
        }

        var lines: [String] {
            lock.withLock { printed.flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) } }
        }

        var text: String {
            lines.joined(separator: "\n")
        }
    }
}
