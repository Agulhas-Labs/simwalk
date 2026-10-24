//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `simwalk uninstall` takes SimWalk out of every agent `install` writes to (SimWalk#167), against scratch locations and a fake `claude`, never the machine's own.
struct UninstallCommandTests {
    private static var binary: String {
        "/opt/simwalk/bin/simwalk"
    }

    /// Both agents lose SimWalk's entries and the foreign server and hook stay (SimWalk#167).
    @Test
    func uninstallRemovesSimWalkFromClaudeCodeAndCursorAndKeepsForeignEntries() throws {
        let machine = try Machine()
        #expect(try machine.serverNames() == ["sift", "simwalk"])

        let answer = try machine.uninstall().answer()

        #expect(answer.verdict.exitCode == 0)
        #expect(try machine.serverNames() == ["sift"])
        let hooks = try String(contentsOf: machine.hooks, encoding: .utf8)
        #expect(hooks.contains("/opt/sift/bin/sift"))
        #expect(!hooks.contains("simwalk"))
        #expect(!FileManager.default.fileExists(atPath: machine.scratch.guide.path))
        #expect(answer.text.contains("hook: PreToolUse removed"))
        #expect(answer.text.contains("mcp: removed simwalk"))
    }

    /// A second run changes nothing, says so for each agent and does not rewrite Cursor's files (SimWalk#167).
    @Test
    func aSecondUninstallChangesNothingAndSaysSoForEachAgent() throws {
        let machine = try Machine()
        _ = try machine.uninstall().answer()
        let written = try (Data(contentsOf: machine.mcp), Data(contentsOf: machine.hooks))

        let answer = try machine.uninstall().answer()

        #expect(answer.verdict.exitCode == 0)
        #expect(try (Data(contentsOf: machine.mcp), Data(contentsOf: machine.hooks)) == written)
        #expect(answer.text.contains("mcp: nothing registered"))
        #expect(answer.text.contains("cursor: nothing registered"))
        #expect(answer.text.contains("nothing of simwalk's was registered"))
    }

    /// A `hooks.json` that cannot be read refuses Cursor, and the refusal throws with the whole per-agent report while Claude Code's half is still removed (SimWalk#167).
    @Test
    func anUnreadableCursorFileThrowsTheReportAndStillRemovesClaudeCode() throws {
        let machine = try Machine()
        try Data("{ not json".utf8).write(to: machine.hooks)

        let thrown = #expect(throws: UninstallCommand.UninstallRefusal.self) { try machine.uninstall().answer() }

        let report = try #require(thrown?.description)

        #expect(!FileManager.default.fileExists(atPath: machine.scratch.guide.path))
        #expect(try machine.claudeHasServer() == false)
        #expect(report.contains("Claude Code:"))
        #expect(report.hasSuffix("not removed from Cursor"))
        #expect(try UsageFailureKind.of(#require(thrown)) == .setupFailed)
    }

    /// A refusal goes to stderr, not stdout, exits 1 and is logged as a failure rather than a success (SimWalk#167).
    @Test
    func aRefusalGoesToStandardErrorAndIsLoggedAsAFailure() throws {
        let machine = try Machine()
        try Data("{ not json".utf8).write(to: machine.hooks)
        let streams = Capture()
        var command = try machine.uninstall()
        command.emit = { streams.out($0) }
        command.emitError = { streams.err($0) }
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        #expect(throws: ExitCode.self) { try command.run(log: log) }

        #expect(streams.stdout.isEmpty)
        #expect(streams.stderr.joined().contains("refused — "))
        #expect(streams.stderr.joined().contains("not removed from Cursor"))
        let entry = try #require(UsageReport.entries(at: log.fileURL).entries.first)
        #expect(entry.tool == "uninstall")
        #expect(entry.succeeded == false)
        #expect(entry.kind == .setupFailed)
    }

    /// Claude Code refusing does not stop Cursor, which is still cleared (SimWalk#167).
    @Test
    func claudeCodeRefusedWhileCursorIsStillRemoved() throws {
        let machine = try Machine()
        var command = try machine.uninstall()
        command.claude = RefusingClaude()

        let thrown = #expect(throws: UninstallCommand.UninstallRefusal.self) { try command.answer() }

        #expect(try #require(thrown?.description).hasSuffix("not removed from Claude Code"))
        #expect(try machine.serverNames() == ["sift"])
    }

    /// A status line somebody else built is left alone and qualifies the verdict, exit 2 (SimWalk#167).
    @Test
    func aForeignStatusLineExitsTwo() throws {
        let machine = try Machine()
        var settings = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: machine.scratch.settings)) as? [String: Any])
        settings["statusLine"] = ["type": "command", "command": "/usr/bin/somebody-elses-statusline"]
        try JSONSerialization.data(withJSONObject: settings).write(to: machine.scratch.settings)

        let answer = try machine.uninstall().answer()

        #expect(answer.verdict.exitCode == 2)
        #expect(answer.text.contains("statusline: left alone"))
    }

    /// With no `claude` on PATH the registration stays, and the answer says so with the command that removes it instead of "nothing registered", for `uninstall` (SimWalk#167).
    @Test
    func uninstallWithNoClaudeOnPathQualifiesAStillRegisteredServer() throws {
        let machine = try Machine()
        var command = try machine.uninstall()
        command.claude = AbsentClaude()

        let answer = try command.answer()

        #expect(answer.verdict.exitCode == 2)
        #expect(try machine.claudeHasServer())
        #expect(answer.text.contains("still registered"))
        #expect(answer.text.contains("claude mcp remove"))
    }

    /// A server registered only at local scope, in a project, counts as removed when `claude` takes it out: the summary reads `removed from Claude Code`, not that nothing was registered (SimWalk#167).
    @Test
    func aLocalScopeServerTakenOutCountsAsRemoved() throws {
        let machine = try Machine()
        _ = try machine.uninstall().answer()
        try machine.registerLocalServer()

        let answer = try machine.uninstall().answer()

        #expect(answer.verdict.exitCode == 0)
        #expect(try !machine.claudeHasLocalServer())
        #expect(answer.text.contains("removed from Claude Code"))
    }

    /// With no `claude` on PATH a local-scope server stays, and the answer qualifies it and says nothing was removed, never that nothing was registered (SimWalk#167).
    @Test
    func aLocalScopeServerLeftByAMissingClaudeQualifies() throws {
        let machine = try Machine()
        _ = try machine.uninstall().answer()
        try machine.registerLocalServer()
        var command = try machine.uninstall()
        command.claude = AbsentClaude()

        let answer = try command.answer()

        #expect(answer.verdict.exitCode == 2)
        #expect(try machine.claudeHasLocalServer())
        #expect(answer.text.contains("still registered"))
        #expect(answer.text.contains("nothing removed"))
        #expect(!answer.text.contains("nothing of simwalk's was registered"))
    }

    /// Both agents cleared reads `removed from Claude Code, Cursor` (SimWalk#167).
    @Test
    func theSummaryNamesEveryAgentThatWasCleared() throws {
        let machine = try Machine()

        let answer = try machine.uninstall().answer()

        #expect(answer.text.contains("removed from Claude Code, Cursor"))
    }

    /// A `simwalk` server in Cursor that this tool did not register is kept and qualifies the verdict, exit 2 (SimWalk#167).
    @Test
    func aForeignCursorSimwalkServerExitsTwo() throws {
        let machine = try Machine()
        try Data(#"{"mcpServers":{"simwalk":{"command":"/usr/bin/somebody-elses-server","args":["serve"]}}}"#.utf8).write(to: machine.mcp)

        let answer = try machine.uninstall().answer()

        #expect(try machine.serverNames() == ["simwalk"])
        #expect(answer.verdict.exitCode == 2)
    }

    /// Cursor's left-alone note is said once, in the verdict's qualification, not again in Cursor's own lines (SimWalk#197).
    @Test
    func aForeignCursorServersNoteIsSaidOnce() throws {
        let machine = try Machine()
        try Data(#"{"mcpServers":{"simwalk":{"command":"/usr/bin/somebody-elses-server","args":["serve"]}}}"#.utf8).write(to: machine.mcp)

        let text = try machine.uninstall().answer().text

        #expect(text.components(separatedBy: "not ours, left alone").count - 1 == 1)
    }

    /// With no `claude` on PATH the removal command is said once, in the qualification (SimWalk#197).
    @Test
    func theRemovalCommandForAMissingClaudeIsSaidOnce() throws {
        let machine = try Machine()
        var command = try machine.uninstall()
        command.claude = AbsentClaude()

        let text = try command.answer().text

        // The command itself may hold several `claude mcp remove` invocations; it is the whole command that must appear once.
        #expect(text.components(separatedBy: SimWalkClaudeSetup.server.removalCommand).count - 1 == 1)
    }

    /// A refusal with no `claude` on PATH still names the removal command, once: the line that carries it is rewritten only for an answer, never for a refusal, whose text is that line (SimWalk#197).
    @Test
    func aRefusalWithNoClaudeOnPathKeepsTheRemovalCommand() throws {
        let machine = try Machine()
        var command = try machine.uninstall()
        command.claude = AbsentClaude()
        let ruleDirectory = machine.scratch.guide.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ruleDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ruleDirectory.path) }

        let thrown = #expect(throws: UninstallCommand.UninstallRefusal.self) { try command.answer() }

        let report = try #require(thrown?.description)
        #expect(report.components(separatedBy: SimWalkClaudeSetup.server.removalCommand).count - 1 == 1)
    }

    /// A refusal under `uninstall` names `simwalk uninstall` to run again, not `uninstall-hook` (SimWalk#197).
    @Test
    func anUninstallRefusalNamesUninstallNotUninstallHook() throws {
        let machine = try Machine()
        var command = try machine.uninstall()
        command.claude = RefusingClaude()

        let thrown = #expect(throws: UninstallCommand.UninstallRefusal.self) { try command.answer() }

        let report = try #require(thrown?.description)
        #expect(report.contains("`simwalk uninstall`"))
        #expect(!report.contains("uninstall-hook"))
    }

    /// The answer says simwalk does not install into Codex, after the other two sections (SimWalk#167).
    @Test
    func theAnswerSaysThereIsNothingToRemoveFromCodex() throws {
        let machine = try Machine()

        let text = try machine.uninstall().answer().text

        #expect(text.contains("codex: simwalk does not install into Codex — nothing to remove"))
        let order = ["Claude Code:", "Cursor:", "Codex:"].compactMap { text.range(of: $0)?.lowerBound }
        #expect(order.count == 3)
        #expect(order == order.sorted())
    }
}

extension UninstallCommandTests {
    /// A scratch Claude Code with SimWalk installed, and a scratch Cursor directory holding SimWalk beside a foreign server and a foreign hook.
    private struct Machine {
        let scratch: HookInstallTests.Scratch
        let recorder: RecordingClaude
        let cursor: URL

        var mcp: URL {
            cursor.appendingPathComponent("mcp.json")
        }

        var hooks: URL {
            cursor.appendingPathComponent("hooks.json")
        }

        init() throws {
            scratch = try HookInstallTests.Scratch()
            recorder = scratch.claude()
            cursor = scratch.directory.url.appendingPathComponent("cursor", isDirectory: true)
            try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
            try Data(#"{"mcpServers":{"sift":{"command":"/opt/sift/bin/sift","args":["mcp"]}}}"#.utf8).write(to: mcp)
            try Data(#"{"version":1,"hooks":{"preToolUse":[{"command":"\"/opt/sift/bin/sift\" pre-tool-use --agent cursor"}]}}"#.utf8).write(to: hooks)
            _ = try InstallHookCommand.answer(
                locations: scratch.locations(),
                executable: UninstallCommandTests.binary,
                claude: recorder,
                guide: .found(scratch.guideSource),
                runnerSource: scratch.runnerSource
            )
            _ = try SimWalkCursorSetup.step.run(binary: UninstallCommandTests.binary, environment: [:], directory: cursor.path)
        }

        func uninstall() throws -> UninstallCommand {
            var command = try UninstallCommand.parse(["--cursor-dir", cursor.path])
            command.locations = scratch.locations()
            command.claude = recorder
            command.environment = ["HOME": scratch.directory.url.path, "PATH": ""]
            command.executable = UninstallCommandTests.binary
            return command
        }

        /// Whether Claude Code's config still holds the simwalk server.
        func claudeHasServer() throws -> Bool {
            SimWalkClaudeSetup.server.userEntry(in: scratch.config) != nil
        }

        /// Registers the simwalk server at local scope in one project of Claude Code's config, as `claude mcp add` run inside that project does.
        func registerLocalServer() throws {
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.config)) as? [String: Any] ?? [:]
            let server: [String: Any] = ["type": "stdio", "command": UninstallCommandTests.binary, "args": ["mcp"]]
            object["projects"] = ["/work/app": ["mcpServers": ["simwalk": server]]]
            try JSONSerialization.data(withJSONObject: object).write(to: scratch.config)
        }

        /// Whether any project in Claude Code's config still holds a local-scope simwalk server.
        func claudeHasLocalServer() throws -> Bool {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.config)) as? [String: Any]
            let projects = object?["projects"] as? [String: Any] ?? [:]
            return projects.values.contains { (($0 as? [String: Any])?["mcpServers"] as? [String: Any])?["simwalk"] != nil }
        }

        func serverNames() throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: mcp)) as? [String: Any]
            return Set((object?["mcpServers"] as? [String: Any])?.keys.map(\.self) ?? [])
        }
    }
}
