//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkDriver
import SimWalkMCP
import Testing

/// `simwalk doctor` composes Fieldwork's doctor over what `simwalk install` writes, so the claims worth pinning are the seams: that a whole install passes with the built binary registered, that a missing hook fails and fails the run, that agents not found are said and skipped, and that Codex is not an agent it takes.
struct DoctorCommandTests {
    /// After `install --agent cursor` into a scratch directory, every check passes (the registered binary is this build, so its version matches too).
    @Test
    func aWholeCursorInstallPasses() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try scratch.install()

        let result = try scratch.doctor(["--agent", "cursor", "--cursor-dir", scratch.cursor.path, "--json"])

        let object = try #require(JSONSerialization.jsonObject(with: Data(result.lines.joined().utf8)) as? [String: Any])
        let checks = try #require(object["checks"] as? [[String: Any]])

        #expect(object["verdict"] as? String == "passed")
        #expect(checks.count == 6, "\(result.lines)")
        #expect(checks.allSatisfy { $0["status"] as? String == "pass" }, "\(result.lines)")
        #expect(result.status == 0)
    }

    /// Without the `preToolUse` entry, the hook's line fails, naming the hook, and the run exits 1.
    @Test
    func aMissingPreToolUseHookFailsTheRun() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try scratch.install()
        try Data(#"{"version":1,"hooks":{}}"#.utf8).write(to: scratch.cursor.appendingPathComponent("hooks.json"))

        let result = try scratch.doctor(["--agent", "cursor", "--cursor-dir", scratch.cursor.path])

        #expect(result.lines.first == "doctor: failed — 1 of 5 checks failed")
        #expect(result.lines.contains { $0.hasPrefix("cursor hooks: fail — not registered for preToolUse") }, "\(result.lines)")
        #expect(result.status == 1)
    }

    /// With no agent found and none named, each is said and skipped, and nothing fails.
    @Test
    func agentsNotFoundAreSkippedAndNamed() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        let result = try scratch.doctor([])

        #expect(result.lines.first == "doctor: passed — 0 of 0 checks failed; not detected: Claude Code, Cursor", "\(result.lines)")
        #expect(result.lines.count == 3)
        #expect(result.lines.dropFirst().allSatisfy { $0.contains("not detected, skipped") })
        #expect(result.status == 0)
    }

    /// An agent found with nothing of simwalk's in it is said, not counted, and the run fails for want of anything installed.
    @Test
    func anAgentFoundWithoutSimWalkFailsTheRunByName() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.home.appendingPathComponent(".cursor", isDirectory: true), withIntermediateDirectories: true)

        let result = try scratch.doctor([])

        #expect(result.lines.first == "doctor: failed — no agent has simwalk installed; `simwalk install` adds it", "\(result.lines)")
        #expect(result.lines.contains { $0.hasPrefix("cursor: found, simwalk not installed") })
        #expect(result.status == 1)
    }

    /// Codex is not an agent simwalk supports, so naming it is a usage error, as is `--cursor-dir` without Cursor.
    @Test
    func codexAndAStrayCursorDirectoryAreUsageErrors() {
        #expect(throws: (any Error).self) { try DoctorCommand.parse(["--agent", "codex"]) }
        #expect(throws: (any Error).self) { try DoctorCommand.parse(["--agent", "claude", "--cursor-dir", "/nowhere"]) }
    }

    /// After a Claude Code install into a scratch home, the hook, the server and the rule are all checked and pass; with the hook taken out, the hook's line fails by name.
    @Test
    func aClaudeInstallPassesAndAMissingHookFailsByName() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        try scratch.installClaude()

        let passing = try scratch.doctor(["--agent", "claude", "--json"])

        let object = try #require(JSONSerialization.jsonObject(with: Data(passing.lines.joined().utf8)) as? [String: Any])
        let checks = try #require(object["checks"] as? [[String: Any]])
        let names = checks.compactMap { $0["name"] as? String ?? $0["check"] as? String }
        #expect(object["verdict"] as? String == "passed", "\(passing.lines)")
        #expect(checks.allSatisfy { $0["status"] as? String == "pass" }, "\(passing.lines)")
        #expect(names.contains { $0.contains("hook") } && names.contains { $0.contains("server") } && names.contains { $0.contains("rule") }, "\(names)")

        try Data("{}".utf8).write(to: scratch.home.appendingPathComponent(".claude/settings.json"))
        let failing = try scratch.doctor(["--agent", "claude"])

        #expect(failing.lines.contains { $0.contains("hook") && $0.contains("fail") }, "\(failing.lines)")
        #expect(failing.status == 1)
    }
}

extension DoctorCommandTests {
    /// A scratch home, a scratch Cursor directory and the built `simwalk` beside the test bundle, all removed by ``remove()``.
    struct Scratch {
        let root: URL
        let home: URL
        let cursor: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-doctor-tests-\(UUID().uuidString)", isDirectory: true)
            home = root.appendingPathComponent("home", isDirectory: true)
            cursor = root.appendingPathComponent("cursor", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        var environment: [String: String] {
            ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        }

        /// The scratch machine: its home and its applications folder are the scratch's, so the real Cursor in /Applications is not found.
        var machine: AgentDetection.Machine {
            AgentDetection.Machine(environment: environment, applications: root.appendingPathComponent("Applications", isDirectory: true))
        }

        /// The `simwalk` the package built, which sits beside the test bundle.
        var binary: String {
            let bundle = Bundle.allBundles.first { $0.bundleURL.pathExtension == "xctest" }
            return (bundle?.bundleURL.deletingLastPathComponent() ?? URL(fileURLWithPath: ".build/debug")).appendingPathComponent("simwalk").path
        }

        /// `simwalk install --agent cursor` into the scratch Cursor directory, naming the built binary.
        func install() throws {
            var command = try InstallCommand.parse(["--agent", "cursor", "--cursor-dir", cursor.path])
            command.emit = { _ in }
            command.machine = machine
            command.terminal = InstallTerminal(isInteractive: false, ask: { _ in nil })
            command.executable = binary
            command.familyLaunch = { _, _, _ in 0 }
            try command.run()
        }

        /// `simwalk install --agent claude` into the scratch home, through a fake `claude`, naming the built binary.
        func installClaude() throws {
            let paths = AgentPaths.self
            let locations = HookLocations(
                settings: paths.claudeSettings(environment: environment),
                config: paths.claudeConfig(environment: environment),
                rule: paths.claudeRule(named: FieldworkTool.simwalk.installedRuleName, environment: environment),
                segments: nil,
                visibility: StatuslineVisibility(cacheDirectory: root.appendingPathComponent("statusline")),
                runner: RunnerStore(directory: root.appendingPathComponent("runner")),
                runnerBuilds: RunnerBuilds(directory: root.appendingPathComponent("runner-builds")),
                installedBinary: URL(fileURLWithPath: binary)
            )
            let guide = root.appendingPathComponent("SimWalk.md")
            try Data("---\npaths:\n  - \"**/project.yml\"\n---\n\n# Using simwalk\n".utf8).write(to: guide)
            var command = try InstallCommand.parse(["--agent", "claude", "--guide", guide.path])
            command.emit = { _ in }
            command.machine = machine
            command.terminal = InstallTerminal(isInteractive: false, ask: { _ in nil })
            command.executable = binary
            command.familyLaunch = { _, _, _ in 0 }
            command.claudeSurroundings = InstallHookCommand.Surroundings(
                locations: locations,
                claude: RecordingClaude(config: locations.config),
                runnerSource: RunnerSnapshotSource(checkout: root.appendingPathComponent("no-checkout"), binaryHash: "hash", run: { _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "") }, repoint: false)
            )
            try command.run()
        }

        /// What `doctor` printed and the status it exits with, against the scratch machine.
        func doctor(_ arguments: [String]) throws -> (lines: [String], status: Int32) {
            let printed = Printed()
            var command = try DoctorCommand.parse(arguments)
            command.emit = printed.emit
            command.machine = machine
            do {
                try command.run()
                return (printed.lines, 0)
            } catch let code as ExitCode {
                return (printed.lines, code.rawValue)
            }
        }
    }

    final class Printed: @unchecked Sendable {
        private let lock = NSLock()
        private var printed: [String] = []

        var emit: @Sendable (String) -> Void {
            { [self] line in lock.withLock { printed.append(line) } }
        }

        var lines: [String] {
            lock.withLock { printed }
        }
    }
}
