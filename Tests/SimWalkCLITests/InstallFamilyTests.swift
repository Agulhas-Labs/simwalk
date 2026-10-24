//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import Testing

/// `simwalk install` ends by running the other Fieldwork tools' installs once, into the agents it ran a step for, so the claims worth pinning are what is launched and with which arguments, what is printed about it, and when nothing is launched.
struct InstallFamilyTests {
    /// With no other tool found there is no `family:` line and the exit is simwalk's own.
    @Test
    func noMemberFoundPrintsNothingAboutTheFamily() throws {
        let fixture = try Fixture()
        let run = try fixture.run(["--agent", "cursor", "--cursor-dir", fixture.cursor.path], path: "")

        #expect(!run.output.text.contains("family:"), "\(run.output.text)")
        #expect(run.launches.isEmpty)
        #expect(run.exit == nil)
    }

    /// A `sift` found on PATH is launched once with the agents simwalk installed into, after a header line saying what runs.
    @Test
    func aFoundMemberIsLaunchedIntoTheSameAgents() throws {
        let fixture = try Fixture()
        let sift = try fixture.fakeSift()
        let run = try fixture.run(["--agent", "cursor", "--cursor-dir", fixture.cursor.path], path: fixture.bin.path)

        #expect(run.launches == [Fixture.Launch(executable: sift, arguments: ["install", "--agent", "cursor", "--yes"])])
        #expect(run.output.lines.contains("family: running sift install --agent cursor --yes"), "\(run.output.text)")
        #expect(run.exit == nil)
    }

    /// A member that exits non-zero is said, and makes `simwalk install` exit 1.
    @Test
    func aFailingMemberIsSaidAndFailsTheInstall() throws {
        let fixture = try Fixture()
        _ = try fixture.fakeSift()
        let run = try fixture.run(["--agent", "cursor", "--cursor-dir", fixture.cursor.path], path: fixture.bin.path, status: 3)

        #expect(run.output.lines.contains("family: sift install exited 3"), "\(run.output.text)")
        #expect(run.exit == 1)
    }

    /// A step started by another tool's family step never starts one of its own.
    @Test
    func theFamilyEnvironmentVariableStopsTheStep() throws {
        let fixture = try Fixture()
        _ = try fixture.fakeSift()
        let run = try fixture.run(
            ["--agent", "cursor", "--cursor-dir", fixture.cursor.path],
            path: fixture.bin.path,
            extra: [Family.environmentVariable: "1"]
        )

        #expect(run.launches.isEmpty)
        #expect(!run.output.text.contains("family:"), "\(run.output.text)")
    }

    /// `--dry-run` writes nothing, says what would change, and hands `--dry-run` to the member.
    @Test
    func dryRunWritesNothingAndPassesItOn() throws {
        let fixture = try Fixture()
        let sift = try fixture.fakeSift()
        let run = try fixture.run(["--agent", "cursor", "--cursor-dir", fixture.cursor.path, "--dry-run"], path: fixture.bin.path)

        #expect(!FileManager.default.fileExists(atPath: fixture.cursor.appendingPathComponent("mcp.json").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.cursor.appendingPathComponent("hooks.json").path))
        #expect(run.output.lines.contains { $0.hasPrefix("cursor: would register the simwalk MCP server in ") && $0.hasSuffix("mcp.json") }, "\(run.output.text)")
        #expect(run.output.lines.contains { $0.hasPrefix("cursor: would register the preToolUse hook in ") && $0.hasSuffix("hooks.json") }, "\(run.output.text)")
        #expect(run.launches == [Fixture.Launch(executable: sift, arguments: ["install", "--agent", "cursor", "--yes", "--dry-run"])])
    }

    /// SimWalk's own step failing does not stop the family step; the exit is still 1.
    @Test
    func anOwnFailureStillRunsTheFamilyStep() throws {
        let fixture = try Fixture()
        let sift = try fixture.fakeSift()
        let scratch = try HookInstallTests.Scratch()
        let surroundings = InstallHookCommand.Surroundings(locations: scratch.locations(), claude: nil, runnerSource: scratch.runnerSource)
        let run = try fixture.run(["--agent", "claude", "--guide", scratch.guideSource.path], path: fixture.bin.path, surroundings: surroundings)

        #expect(run.launches == [Fixture.Launch(executable: sift, arguments: ["install", "--agent", "claude", "--yes"])])
        #expect(run.exit == 1)
    }

    /// A member that cannot be started is said, and makes the exit 1.
    @Test
    func aLaunchFailureIsSaidAndFailsTheInstall() throws {
        let fixture = try Fixture()
        _ = try fixture.fakeSift()
        let run = try fixture.run(["--agent", "cursor", "--cursor-dir", fixture.cursor.path], path: fixture.bin.path, launchThrows: true)

        #expect(run.output.lines.contains { $0.hasPrefix("family: sift install could not be started: ") }, "\(run.output.text)")
        #expect(run.exit == 1)
    }

    /// Every agent named is handed on, in order.
    @Test
    func everyAgentNamedIsPassedOn() throws {
        let fixture = try Fixture()
        let sift = try fixture.fakeSift()
        let run = try fixture.run(["--agent", "cursor", "--agent", "codex", "--cursor-dir", fixture.cursor.path], path: fixture.bin.path)

        #expect(run.launches == [Fixture.Launch(executable: sift, arguments: ["install", "--agent", "cursor", "--agent", "codex", "--yes"])])
    }

    /// With `claude` on PATH the dry run names each Claude Code change where the step makes it, the status line in sift's segment file, and writes and runs nothing.
    @Test
    func claudeDryRunWithClaudeNamesTheRealDestinations() throws {
        let fixture = try Fixture()
        let scratch = try HookInstallTests.Scratch()
        let claude = scratch.claude()
        let locations = scratch.locations()
        let surroundings = InstallHookCommand.Surroundings(locations: locations, claude: claude, runnerSource: scratch.runnerSource)
        let run = try fixture.run(["--agent", "claude", "--dry-run"], path: "", surroundings: surroundings)
        let binary = fixture.root.appendingPathComponent("elsewhere/simwalk").path

        #expect(Self.afterNote(run.output.lines) == [
            "dry run: nothing is written and no `claude` runs",
            "claude: would snapshot the walk runner for this binary and prune old runner paths no install uses",
            "claude: would install or update the PreToolUse hook `\(binary) hook pre-tool-use` in \(scratch.settings.path)",
            "claude: would install or update the status line segment \(locations.segments?.fileURL.path ?? "") — sift runs it",
            "claude: would install or update the agent guide at \(scratch.guide.path)",
            "claude: would run `claude mcp add` to register the simwalk MCP server (`\(binary) mcp`) unless it is already registered",
        ], "\(run.output.text)")
        Self.expectNothingWritten(scratch, claude: claude)
    }

    /// The Claude step takes its paths from the command's injected environment: with `CLAUDE_CONFIG_DIR` there and no explicit surroundings, the dry run names the settings file under that directory (SimWalk#157).
    @Test
    func claudeDryRunTakesItsPathsFromTheInjectedClaudeConfigDir() throws {
        let fixture = try Fixture()
        let moved = fixture.root.appendingPathComponent("moved-claude", isDirectory: true)
        let run = try fixture.run(["--agent", "claude", "--dry-run"], path: "", extra: ["CLAUDE_CONFIG_DIR": moved.path], surroundings: nil)

        #expect(run.output.lines.contains { $0.contains("PreToolUse hook") && $0.hasSuffix(" in \(moved.appendingPathComponent("settings.json").path)") }, "\(run.output.text)")
    }

    /// Where sift is not installed the status line goes into `settings.json`, and the dry run says so.
    @Test
    func claudeDryRunWithoutSiftNamesSettingsForTheStatusLine() throws {
        let fixture = try Fixture()
        let scratch = try HookInstallTests.Scratch()
        let claude = scratch.claude()
        let surroundings = InstallHookCommand.Surroundings(locations: scratch.locations(sift: false), claude: claude, runnerSource: scratch.runnerSource)
        let run = try fixture.run(["--agent", "claude", "--dry-run"], path: "", surroundings: surroundings)

        #expect(run.output.lines.contains("claude: would set the status line in \(scratch.settings.path) unless another is already there"), "\(run.output.text)")
        Self.expectNothingWritten(scratch, claude: claude)
    }

    /// Without `claude` on PATH the real step skips all four Claude Code registrations and installs the runner, and the dry run says exactly that.
    @Test
    func claudeDryRunWithoutClaudeSaysTheRegistrationsAreSkipped() throws {
        let fixture = try Fixture()
        let scratch = try HookInstallTests.Scratch()
        let claude = scratch.claude()
        let surroundings = InstallHookCommand.Surroundings(locations: scratch.locations(), claude: nil, runnerSource: scratch.runnerSource)
        let run = try fixture.run(["--agent", "claude", "--dry-run"], path: "", surroundings: surroundings)

        #expect(Self.afterNote(run.output.lines) == [
            "dry run: nothing is written and no `claude` runs",
            "claude: would snapshot the walk runner for this binary and prune old runner paths no install uses",
            "claude: `claude` is not on PATH, so the hook, status line, guide and `claude mcp add` would be skipped (the step would fail)",
        ], "\(run.output.text)")
        Self.expectNothingWritten(scratch, claude: claude)
    }

    /// An install that went into nothing launches nothing.
    @Test
    func installingIntoNothingLaunchesNothing() throws {
        let fixture = try Fixture()
        _ = try fixture.fakeSift()
        let run = try fixture.run([], path: fixture.bin.path)

        #expect(run.output.text.contains("simwalk install --yes"), "\(run.output.text)")
        #expect(run.launches.isEmpty)
        #expect(!run.output.text.contains("family:"), "\(run.output.text)")
    }
}

extension InstallFamilyTests {
    /// The lines after detection's note that `--agent claude` named an agent not found.
    static func afterNote(_ lines: [String]) -> [String] {
        lines.first?.hasPrefix("Claude Code was not found") == true ? Array(lines.dropFirst()) : lines
    }

    /// Neither the settings, the rule, the segment directory nor the runner was created, and the fake `claude` was never called.
    static func expectNothingWritten(_ scratch: HookInstallTests.Scratch, claude: RecordingClaude, sourceLocation: SourceLocation = #_sourceLocation) {
        let manager = FileManager.default
        var paths = [scratch.settings, scratch.guide, scratch.runner.directory]
        if let segments = scratch.locations().segments {
            paths.append(segments.fileURL.deletingLastPathComponent())
        }
        for path in paths {
            #expect(!manager.fileExists(atPath: path.path), "\(path.path) was written", sourceLocation: sourceLocation)
        }
        #expect(claude.vectors.isEmpty, sourceLocation: sourceLocation)
    }
}

extension InstallFamilyTests {
    /// A scratch home, a Cursor directory and a `bin` directory for a fake `sift`, removed with the fixture.
    final class Fixture: @unchecked Sendable {
        let root: URL
        let cursor: URL
        let bin: URL
        private let lock = NSLock()
        private var launched: [Launch] = []

        init() throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("InstallFamily-\(UUID().uuidString)", isDirectory: true)
            cursor = root.appendingPathComponent("cursor", isDirectory: true)
            bin = root.appendingPathComponent("bin", isDirectory: true)
            for directory in [cursor, bin] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        /// An executable `sift` in `bin`; returns the path a launch should name.
        func fakeSift() throws -> String {
            let file = bin.appendingPathComponent("sift")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            return file.path
        }

        /// Runs `simwalk install` with `arguments`; the launch records the call and answers `status` instead of running anything.
        func run(_ arguments: [String], path: String, status: Int32 = 0, extra: [String: String] = [:], launchThrows: Bool = false, surroundings: InstallHookCommand.Surroundings? = nil) throws -> Run {
            var command = try InstallCommand.parse(arguments)
            let output = InstallCommandTests.Output()
            command.emit = output.emit
            command.machine = AgentDetection.Machine(environment: ["HOME": root.path, "PATH": path].merging(extra) { $1 })
            command.terminal = InstallTerminal(isInteractive: false, ask: { _ in nil })
            command.executable = root.appendingPathComponent("elsewhere/simwalk").path
            command.claudeSurroundings = surroundings
            command.familyLaunch = { [self] executable, arguments, _ in
                lock.withLock { launched.append(Launch(executable: executable, arguments: arguments)) }
                if launchThrows {
                    throw LaunchError()
                }
                return status
            }
            var exit: Int32?
            do {
                try command.run()
            } catch let code as ExitCode {
                exit = code.rawValue
            }
            return Run(output: output, launches: lock.withLock { launched }, exit: exit)
        }
    }
}

extension InstallFamilyTests.Fixture {
    struct Launch: Equatable {
        let executable: String
        let arguments: [String]
    }

    struct LaunchError: Error, CustomStringConvertible {
        let description = "no such file"
    }

    struct Run {
        let output: InstallCommandTests.Output
        let launches: [Launch]
        let exit: Int32?
    }
}
