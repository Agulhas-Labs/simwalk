//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The installer writes into somebody else's configuration directory, so the claims worth pinning are the ones nobody can check by watching it work: that a re-run changes nothing, that the uninstall takes back exactly what the install wrote and nothing beside it, and that what `claude` is asked to do is what it was meant to be asked.
struct HookInstallTests {
    /// `HookInstallError` is about Claude Code's own CLI refusing a registration — not about a walkbook, a route, the walk runner, a device, or the tool contradicting itself, which is every one of `UsageFailureKind`'s other five shapes.
    ///
    /// `setup-failed` is named for exactly this.
    @Test
    func hookInstallErrorIsSetupFailed() {
        let refused = HookInstallError.claudeRefused(failures: ["mcp: not registered — `claude mcp add` failed: exit 1"], written: [])

        #expect(UsageFailureKind.of(refused) == .setupFailed)
    }

    /// An error install-hook's own internals do not classify — a raw write failure from the status-line segment or the settings merge, say — still lands on `setup-failed`, never `unclassified`: those are this tool's own registration files or Claude Code's own configuration, never a caller's argument.
    @Test
    func aninstallFailureWithNoMappedKindDefaultsToSetupFailed() throws {
        struct Unmapped: Error, CustomStringConvertible {
            var description: String {
                "something this codebase has never classified"
            }
        }
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let command = try InstallHookCommand.parse([])

        #expect(throws: ExitCode.self) {
            try command.run(log: log, emit: recorder.emit, emitError: recorder.emitError) { throw Unmapped() }
        }

        let entries = try UsageReport.entries(at: log.fileURL).entries
        #expect(entries.first?.kind == .setupFailed)
    }

    /// The same default, for `uninstall-hook`.
    @Test
    func anuninstallFailureWithNoMappedKindDefaultsToSetupFailed() throws {
        struct Unmapped: Error, CustomStringConvertible {
            var description: String {
                "something this codebase has never classified"
            }
        }
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let command = try UninstallHookCommand.parse([])

        #expect(throws: ExitCode.self) {
            try command.run(log: log, emit: recorder.emit, emitError: recorder.emitError) { throw Unmapped() }
        }

        let entries = try UsageReport.entries(at: log.fileURL).entries
        #expect(entries.first?.kind == .setupFailed)
    }

    @Test
    func afullInstallWritesTheSegmentTheGuideAndTheRegistration() throws {
        let scratch = try Scratch()
        let recorder = scratch.claude()

        let answer = try InstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: recorder,
            guide: .found(scratch.guideSource),
            runnerSource: scratch.runnerSource
        )
        let shim = try String(contentsOf: scratch.segments.fileURL, encoding: .utf8)
        let rule = try String(contentsOf: scratch.guide, encoding: .utf8)
        let source = try String(contentsOf: scratch.guideSource, encoding: .utf8)

        #expect(answer.verdict.exitCode == 0)
        #expect(shim.contains("exec \"\(Self.executable)\" statusline"))
        #expect(FileManager.default.isExecutableFile(atPath: scratch.segments.fileURL.path))
        #expect(rule == source)
        #expect(rule.hasPrefix("---\npaths:"))
        #expect(answer.text.contains("mcp: registered simwalk"))
    }

    /// **The removal has to come first and `--scope` has to precede the `--`.** `claude mcp add` fails outright on a name already present, so without the removals an upgrade leaves the *old* binary registered while reporting success; and `--scope` after the `--` is passed through to the binary as an argument, registering at the default scope under a command line that reads as though it asked for user scope.
    @Test
    func theRegistrationRemovesFirstAndKeepsScopeAheadOfTheSeparator() throws {
        let scratch = try Scratch()
        let recorder = scratch.claude()

        _ = try InstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: recorder,
            guide: .found(scratch.guideSource),
            runnerSource: scratch.runnerSource
        )
        let vectors = recorder.vectors
        let add = try #require(vectors.last)
        let separator = try #require(add.firstIndex(of: "--"))
        let scope = try #require(add.firstIndex(of: "--scope"))

        #expect(vectors.count == 3)
        #expect(vectors[0] == ["mcp", "remove", "simwalk", "--scope", "user"])
        #expect(vectors[1] == ["mcp", "remove", "simwalk"])
        #expect(add == ["mcp", "add", "--transport", "stdio", "--scope", "user", "simwalk", "--", Self.executable, "mcp"])
        #expect(scope < separator)
    }

    /// The second run reads `.claude.json` back and finds this binary registered, so it runs no `mcp add` (and no removal) and says so.
    @Test
    func aSecondInstallRunsNoAddAndSaysTheServerIsAlreadyRegistered() throws {
        let scratch = try Scratch()
        let claude = scratch.claude()
        let first = try InstallHookCommand.answer(locations: scratch.locations(), executable: Self.executable, claude: claude, guide: .found(scratch.guideSource), runnerSource: scratch.runnerSource)
        let runsAfterFirst = claude.vectors.count

        let second = try InstallHookCommand.answer(locations: scratch.locations(), executable: Self.executable, claude: claude, guide: .found(scratch.guideSource), runnerSource: scratch.runnerSource)

        #expect(first.text.contains("mcp: registered simwalk"))
        #expect(claude.adds.count == 1)
        #expect(claude.vectors.count == runsAfterFirst)
        #expect(second.text.contains("mcp: already registered"))
    }

    @Test
    func areRunSaysWhatItLeftAloneRatherThanRewritingIt() throws {
        let scratch = try Scratch()

        _ = try Self.install(scratch)
        let again = try Self.install(scratch)

        #expect(again.verdict.exitCode == 0)
        #expect(again.text.contains("statusline: unchanged"))
        #expect(again.text.contains("rule: already installed"))
    }

    @Test
    func theUninstallTakesBackExactlyWhatTheInstallWrote() throws {
        let scratch = try Scratch()
        let recorder = scratch.claude()
        _ = try Self.install(scratch)

        let answer = try UninstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: recorder
        )

        #expect(answer.verdict.exitCode == 0)
        #expect(!FileManager.default.fileExists(atPath: scratch.segments.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.guide.path))
        #expect(recorder.vectors == [["mcp", "remove", "simwalk", "--scope", "user"], ["mcp", "remove", "simwalk"]])
        #expect(answer.text.contains("statusline: removed"))
        #expect(answer.text.contains("hook: PreToolUse removed from"))
        #expect(answer.text.contains("rule: removed"))
    }

    /// Everything the install refused to touch on the way in is refused on the way out too — and both files here carry somebody else's writing at the paths this tool would have used.
    @Test
    func theUninstallLeavesFilesThisToolDidNotWrite() throws {
        let scratch = try Scratch()
        try FileManager.default.createDirectory(at: scratch.segments.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch.guide.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho mine\n".utf8).write(to: scratch.segments.fileURL)
        let notes = scratch.directory.url.appendingPathComponent("notes.md")
        try Data("# my own notes on simwalk\n".utf8).write(to: notes)
        try FileManager.default.createSymbolicLink(at: scratch.guide, withDestinationURL: notes)

        let answer = try UninstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: scratch.claude()
        )

        #expect(answer.verdict.isQualified)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: scratch.guide.path) == notes.path)
        #expect(try String(contentsOf: notes, encoding: .utf8) == "# my own notes on simwalk\n")
        #expect(FileManager.default.fileExists(atPath: scratch.segments.fileURL.path))
        #expect(answer.text.contains("is a symlink to"))
        #expect(answer.text.contains("statusline: left alone"))
    }

    /// A named `--guide` is the only candidate: falling through to another file would install a different guide than the one asked for and report success over it.
    @Test
    func anUnreadableNamedGuideIsAQualificationNamingIt() throws {
        let scratch = try Scratch()

        let answer = try InstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: scratch.claude(),
            guide: InstallHookCommand.locateGuide(explicit: "/nowhere/SimWalk.md", beside: Self.executable),
            runnerSource: scratch.runnerSource
        )

        #expect(answer.verdict.isQualified)
        #expect(answer.text.contains("/nowhere/SimWalk.md"))
        #expect(answer.text.contains("rule: skipped"))
        #expect(!FileManager.default.fileExists(atPath: scratch.guide.path))
    }

    /// Claude Code runs the status-line command through a shell, so an unquoted path with a space in it becomes a command and an argument.
    @Test
    func theSettingsFallbackQuotesABinaryPathWithASpaceInIt() throws {
        let scratch = try Scratch()
        let spaced = "/Users/x/My Tools/simwalk"

        _ = try InstallHookCommand.answer(
            locations: scratch.locations(sift: false),
            executable: spaced,
            claude: scratch.claude(),
            guide: .found(scratch.guideSource),
            runnerSource: scratch.runnerSource
        )
        let written = try Data(contentsOf: scratch.settings)
        let settings = try #require(try JSONSerialization.jsonObject(with: written) as? [String: Any])
        let slot = try #require(settings["statusLine"] as? [String: Any])

        #expect(slot["command"] as? String == "\"\(spaced)\" statusline")
        #expect(StatuslineRegistration.isOurs(slot["command"] as? String))
    }

    /// Where sift owns the status-line slot the settings file still takes the `PreToolUse` hook (SimWalk#14) — so `--settings` is honoured, and the status line stays out of it.
    @Test
    func thesettingsFileTakesTheHookWhereSiftOwnsTheStatusLine() throws {
        let scratch = try Scratch()

        let answer = try Self.install(scratch)
        let settings = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.settings)) as? [String: Any])

        #expect(answer.verdict.exitCode == 0)
        #expect(settings["statusLine"] == nil)
        #expect(Self.preToolUseCommands(in: settings) == ["\"\(Self.executable)\" hook pre-tool-use"])
    }

    /// SimWalk#14: the install adds its `PreToolUse` entry beside somebody else's hooks without touching them, a re-run leaves it alone, and the uninstall takes out that entry and nothing else.
    @Test
    func thehookIsMergedBesideOthersAndTheUninstallRemovesOnlyIt() throws {
        let scratch = try Scratch()
        let theirs: [String: Any] = [
            "model": "opus",
            "hooks": [
                "PreToolUse": [["matcher": "Bash|Read", "hooks": [["type": "command", "command": "/usr/local/bin/sift pre-tool-use", "timeout": 5]]]],
                "Stop": [["hooks": [["type": "command", "command": "say done"]]]],
            ],
        ]
        try FileManager.default.createDirectory(at: scratch.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: theirs).write(to: scratch.settings)

        let installed = try Self.install(scratch)
        let again = try Self.install(scratch)
        let merged = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.settings)) as? [String: Any])
        let uninstalled = try UninstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: scratch.claude()
        )
        let restored = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.settings)) as? [String: Any])

        #expect(installed.text.contains("hook: PreToolUse registered in"))
        #expect(again.text.contains("hook: PreToolUse already registered in"))
        #expect(Self.preToolUseCommands(in: merged) == ["/usr/local/bin/sift pre-tool-use", "\"\(Self.executable)\" hook pre-tool-use"])
        #expect(uninstalled.text.contains("hook: PreToolUse removed from"))
        #expect(NSDictionary(dictionary: restored).isEqual(to: theirs))
    }

    /// A `settings.json` this cannot even parse refuses only the `PreToolUse` registration — the guide and the MCP server still register, contrary to a `settingsNotAnObject` thrown up through the whole install.
    @Test
    func amalformedSettingsFileQualifiesOnlyTheHookStep() throws {
        let scratch = try Scratch()
        try FileManager.default.createDirectory(at: scratch.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json at all {".utf8).write(to: scratch.settings)

        let answer = try Self.install(scratch)

        #expect(answer.verdict.isQualified)
        #expect(answer.text.contains("hook: not registered"))
        #expect(answer.text.contains("rule:"))
        #expect(!answer.text.contains("rule: skipped"))
        #expect(answer.text.contains("mcp: registered simwalk"))
        #expect(FileManager.default.fileExists(atPath: scratch.guide.path))
    }

    /// Where sift is absent the status line goes into `settings.json` too, and a file that cannot be read stops that step alone — the guide and the MCP server are still registered.
    @Test
    func amalformedSettingsFileWithoutSiftQualifiesOnlyTheSettingsSteps() throws {
        let scratch = try Scratch()
        try FileManager.default.createDirectory(at: scratch.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json at all {".utf8).write(to: scratch.settings)

        let answer = try InstallHookCommand.answer(
            locations: scratch.locations(sift: false),
            executable: Self.executable,
            claude: scratch.claude(),
            guide: .found(scratch.guideSource),
            runnerSource: scratch.runnerSource
        )

        #expect(answer.verdict.isQualified)
        #expect(answer.text.contains("statusline: not registered"))
        #expect(answer.text.contains("hook: not registered"))
        #expect(answer.text.contains("mcp: registered simwalk"))
        #expect(FileManager.default.fileExists(atPath: scratch.guide.path))
    }

    /// The backup of somebody's `settings.json` is made once per run, from the file as it stood before this run touched it — not from what an earlier step in the same run already edited, which would overwrite the pristine copy with a half-edited one.
    @Test
    func thesettingsBackupIsThePristineFileNotAStepsOwnEdit() throws {
        let scratch = try Scratch()
        let theirs: [String: Any] = ["model": "opus"]
        try FileManager.default.createDirectory(at: scratch.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: theirs).write(to: scratch.settings)

        // `sift: false` so the statusline registration writes into settings.json ahead of the PreToolUse
        // hook registration — the two steps that raced over the backup.
        _ = try InstallHookCommand.answer(
            locations: scratch.locations(sift: false),
            executable: Self.executable,
            claude: scratch.claude(),
            guide: .found(scratch.guideSource),
            runnerSource: scratch.runnerSource
        )
        let backup = try Data(contentsOf: scratch.settings.appendingPathExtension("bak-simwalk"))
        let restored = try #require(try JSONSerialization.jsonObject(with: backup) as? [String: Any])

        #expect(NSDictionary(dictionary: restored).isEqual(to: theirs))
    }

    /// A third party's tool that merely names ours in its filename and shares our subcommand — `simwalk-guard`, say — is not ours: the install leaves it standing beside its own entry, and the uninstall does not touch it.
    @Test
    func athirdPartyEntryNamingOursByFilenameSurvivesInstallAndUninstall() throws {
        let scratch = try Scratch()
        let theirs: [String: Any] = [
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "/opt/bin/simwalk-guard hook pre-tool-use", "timeout": 5]]]],
            ],
        ]
        try FileManager.default.createDirectory(at: scratch.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: theirs).write(to: scratch.settings)

        let installed = try Self.install(scratch)
        let merged = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.settings)) as? [String: Any])
        let uninstalled = try UninstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: scratch.claude()
        )
        let restored = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.settings)) as? [String: Any])

        #expect(installed.text.contains("hook: PreToolUse registered in"))
        #expect(Self.preToolUseCommands(in: merged).contains("/opt/bin/simwalk-guard hook pre-tool-use"))
        #expect(uninstalled.text.contains("hook: PreToolUse removed from"))
        #expect(Self.preToolUseCommands(in: restored) == ["/opt/bin/simwalk-guard hook pre-tool-use"])
    }

    /// The runner is installed; none of the four Claude Code pieces is written.
    @Test
    func amissingClaudeInstallsTheRunnerAndSkipsEveryRegistration() throws {
        let scratch = try Scratch()

        let answer = try InstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: nil,
            guide: .found(scratch.guideSource),
            runnerSource: scratch.runnerSource
        )

        #expect(scratch.runner.binding(forBinary: Self.binaryHash) != nil)
        #expect(!FileManager.default.fileExists(atPath: scratch.segments.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.guide.path))
        #expect(!FileManager.default.fileExists(atPath: scratch.settings.path))
        guard case let .qualified(qualifications, detail: detail) = answer.verdict else {
            Issue.record("expected a qualified verdict, got \(answer.verdict)")
            return
        }
        #expect(detail.contains("runner installed"))
        #expect(qualifications.contains { $0.contains("'claude' is not on PATH") && $0.contains("claude mcp add --transport stdio --scope user simwalk -- \(Self.executable) mcp") })
    }

    /// SimWalk#16: the install snapshots the runner and pairs it with the binary being installed — what a walk from that binary builds, and nothing a walk from any other binary can find.
    @Test
    func theinstallPairsARunnerSnapshotWithTheBinary() throws {
        let scratch = try Scratch()

        let answer = try Self.install(scratch)
        let binding = try #require(scratch.runner.binding(forBinary: Self.binaryHash))

        #expect(binding.commit == Self.commit)
        #expect(binding.projectPath.hasPrefix(scratch.runner.snapshotsDirectory.path))
        #expect(FileManager.default.fileExists(atPath: binding.projectPath))
        #expect(answer.verdict.exitCode == 0)
        #expect(answer.text.contains("runner: \(ShortHash.of(Self.commit)) snapshotted"))
        #expect(answer.text.contains("runners: nothing to prune"))
        #expect(scratch.runner.binding(forBinary: String(repeating: "cd", count: 32)) == nil)
    }

    /// SimWalk#22: once the new runner is paired, the install prunes the runners older installs left behind, keeps its own and the three most recent besides, and says what it freed.
    @Test
    func theinstallPrunesOlderRunnersAndKeepsItsOwn() throws {
        let scratch = try Scratch()
        let bindings = scratch.runner.directory.appendingPathComponent("binaries", isDirectory: true)
        try FileManager.default.createDirectory(at: bindings, withIntermediateDirectories: true)
        var snapshots: [URL] = []
        for days in 2 ... 5 {
            let snapshot = scratch.runner.snapshotsDirectory.appendingPathComponent("old\(days)", isDirectory: true)
            try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: snapshot.appendingPathComponent("file"))
            let binding = bindings.appendingPathComponent("old\(days).json")
            try JSONEncoder().encode(RunnerStore.Binding(commit: "old\(days)", contentHash: "", snapshot: snapshot.path, checkout: "/checkout")).write(to: binding)
            let date = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            for url in [binding, snapshot] {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
            snapshots.append(snapshot)
        }

        let answer = try Self.install(scratch)
        let binding = try #require(scratch.runner.binding(forBinary: Self.binaryHash))

        #expect(FileManager.default.fileExists(atPath: binding.projectPath))
        #expect(snapshots.map { FileManager.default.fileExists(atPath: $0.path) } == [true, true, true, false])
        #expect(answer.text.contains("runners: pruned 2 paths, freed"))
        #expect(answer.verdict.exitCode == 0)
    }

    /// The SimWalk#22 review's finding 1, at the install: the installed binary's runner survives an install by another binary, however old it is and however many installs are newer.
    @Test
    func aninstallKeepsTheInstalledBinarysRunner() throws {
        let scratch = try Scratch()
        try FileManager.default.createDirectory(at: scratch.installedBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("the installed binary".utf8).write(to: scratch.installedBinary)
        let installedHash = try #require(RunnerProject.hash(ofExecutableAt: scratch.installedBinary))
        let installed = try scratch.oldInstall(binary: installedHash, days: 6)
        let others = try (2 ... 5).map { try scratch.oldInstall(binary: "old\($0)", days: Double($0)) }

        _ = try Self.install(scratch)

        #expect(FileManager.default.fileExists(atPath: installed.binding.path))
        #expect(FileManager.default.fileExists(atPath: installed.snapshot.path))
        #expect(others.map { FileManager.default.fileExists(atPath: $0.snapshot.path) } == [true, true, true, false])
    }

    /// An install from a development build, or one whose runner could not be paired, leaves old runners alone and says so: the first's pairing is gone at its next build, and the second has no runner of its own for a prune to keep.
    @Test
    func aninstallThatIsADevelopmentBuildOrUnpairedDoesNotPrune() throws {
        let scratch = try Scratch()
        // Four, so a prune that ran would remove the oldest: the three most recent other installs are kept regardless.
        let olds = try (9 ... 12).map { try scratch.oldInstall(binary: "old\($0)", days: Double($0)) }
        let fromDevelopmentBuild = scratch.checkout.appendingPathComponent(".build/debug/simwalk")
        try FileManager.default.createDirectory(at: fromDevelopmentBuild.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: fromDevelopmentBuild)
        var developmentBuild = scratch.runnerSource
        developmentBuild.executable = fromDevelopmentBuild
        let unpaired = RunnerSnapshotSource(checkout: scratch.checkout, binaryHash: Self.binaryHash) { _, _ in
            Shell.Result(status: 128, standardOutput: "", standardError: "fatal: not a git repository")
        }

        let answers = try [unpaired, developmentBuild].map { try Self.install(scratch, runnerSource: $0) }

        #expect(answers.allSatisfy { $0.text.contains("old walk runners were not pruned") })
        #expect(answers[1].text.contains("development build"))
        #expect(olds.allSatisfy { FileManager.default.fileExists(atPath: $0.snapshot.path) })
    }

    /// SimWalk#33 item 3: a candidate walked after the plan was made survives to removal (`RunnerPrune/execute(_:)`'s re-check), and every candidate doing that must not read as "nothing to prune" — it lists what was spared and why.
    @Test
    func apruneWhereEveryCandidateIsSparedNamesThemRatherThanSayingNothingToPrune() throws {
        let scratch = try Scratch()
        let locations = scratch.locations()
        let prune = RunnerPrune(store: locations.runner, builds: locations.runnerBuilds)
        let old = try scratch.oldInstall(binary: "spared", days: 9)
        // Three more recent installs fill the "most recent besides this one" window, so "spared" (the
        // oldest) is a removal candidate rather than kept by falling inside it.
        _ = try (1 ... 3).map { try scratch.oldInstall(binary: "filler\($0)", days: Double($0)) }
        let plan = prune.plan(keepingBinary: HookInstallTests.binaryHash, installedBinary: nil, now: Date())

        // Walked after the plan was made, before the removal — spared rather than removed.
        let project = old.snapshot.appendingPathComponent(HookInstallTests.runnerFile).deletingLastPathComponent().path
        let source = RunnerSource(projectPath: project, commit: "old-spared", origin: .installed)
        try prune.builds.recordUse(of: source)
        let outcome = prune.execute(plan)

        var qualifications: [String] = []
        let lines = InstallHookCommand.describe(pruning: plan, outcome: outcome, qualifications: &qualifications)

        #expect(!plan.removals.isEmpty)
        #expect(outcome.removed.isEmpty)
        #expect(!outcome.spared.isEmpty)
        #expect(lines.first?.contains("spared") == true)
        #expect(!(lines.first ?? "").contains("nothing to prune"))
        #expect(lines.contains { $0.contains(old.snapshot.path.tildedPath) })
        #expect(qualifications.contains { $0.contains("spared") })
    }

    /// SimWalk#33 review, item 2: a partial spare — some candidates removed, one walked before its own removal — must still name what was spared and qualify it, not fold silently into what was pruned.
    @Test
    func apartialSpareIsNamedAlongsideWhatWasPruned() throws {
        let scratch = try Scratch()
        let locations = scratch.locations()
        let prune = RunnerPrune(store: locations.runner, builds: locations.runnerBuilds)
        let spared = try scratch.oldInstall(binary: "spared", days: 9)
        let removed = try scratch.oldInstall(binary: "removed", days: 8)
        // Three more recent installs fill the "most recent besides this one" window, so both older
        // installs above are removal candidates rather than kept by falling inside it.
        _ = try (1 ... 3).map { try scratch.oldInstall(binary: "filler\($0)", days: Double($0)) }
        let plan = prune.plan(keepingBinary: HookInstallTests.binaryHash, installedBinary: nil, now: Date())

        // Walked after the plan was made, before its removal — spared rather than removed, while the
        // other candidate is removed as planned.
        let project = spared.snapshot.appendingPathComponent(HookInstallTests.runnerFile).deletingLastPathComponent().path
        let source = RunnerSource(projectPath: project, commit: "old-spared", origin: .installed)
        try prune.builds.recordUse(of: source)
        let outcome = prune.execute(plan)

        var qualifications: [String] = []
        let lines = InstallHookCommand.describe(pruning: plan, outcome: outcome, qualifications: &qualifications)

        // Each old install is a binding and a snapshot, so a fully removed or fully spared one is 2 entries.
        #expect(outcome.removed.count == 2)
        #expect(outcome.spared.count == 2)
        #expect(!FileManager.default.fileExists(atPath: removed.snapshot.path))
        #expect(FileManager.default.fileExists(atPath: spared.snapshot.path))
        #expect(lines.first?.contains("pruned") == true)
        #expect(lines.contains { $0.contains(spared.snapshot.path.tildedPath) })
        #expect(qualifications.contains { $0.contains("spared") })
    }

    /// Re-running the install from a checkout that has moved keeps the runner the binary was installed with, and says so on the verdict.
    ///
    /// Re-running is the upgrade path, and it must not be the way a binary gets paired with another commit's runner (SimWalk#16 review). `--repoint-runner` is the explicit way through.
    @Test
    func areRunFromAMovedCheckoutKeepsTheRunnerUnlessToldToRepoint() throws {
        let scratch = try Scratch()
        let moved = "d00d0123456789d00d0123456789d00d01234567"
        _ = try Self.install(scratch)

        let kept = try Self.install(scratch, runnerSource: scratch.runnerSource(at: moved))
        let repointed = try Self.install(scratch, runnerSource: scratch.runnerSource(at: moved, repoint: true))

        #expect(kept.verdict.isQualified)
        #expect(kept.text.contains("runner: kept"))
        #expect(kept.text.contains("--repoint-runner"))
        #expect(repointed.text.contains("runner: repointed"))
        #expect(scratch.runner.binding(forBinary: Self.binaryHash)?.commit == moved)
    }

    /// A runner that cannot be snapshotted leaves the rest of the install standing, and says on the verdict that walks from this binary will refuse.
    @Test
    func arunnerThatCannotBeSnapshottedQualifiesTheInstall() throws {
        let scratch = try Scratch()
        let notACheckout = RunnerSnapshotSource(checkout: scratch.checkout, binaryHash: Self.binaryHash) { _, _ in
            Shell.Result(status: 128, standardOutput: "", standardError: "fatal: not a git repository")
        }

        let answer = try InstallHookCommand.answer(
            locations: scratch.locations(),
            executable: Self.executable,
            claude: scratch.claude(),
            guide: .found(scratch.guideSource),
            runnerSource: notACheckout
        )

        #expect(answer.verdict.isQualified)
        #expect(answer.text.contains("the walk runner was not installed"))
        #expect(answer.text.contains("mcp: registered simwalk"))
    }

    /// A packaged binary installs the runner shipped beside it, with no checkout and no git.
    @Test
    func apackagedBinaryInstallsTheRunnerShippedBesideIt() throws {
        let scratch = try Scratch()
        let fixture = try ShippedTreeFixture(in: scratch.directory, commit: String(repeating: "c0", count: 20), stampedFor: Self.binaryHash)

        let answer = try Self.install(scratch, runnerSource: Self.packaged(executable: fixture.binary))

        #expect(answer.text.contains("runner: c0c0c0c0 snapshotted at"))
        #expect(scratch.runner.binding(forBinary: Self.binaryHash)?.commit == String(repeating: "c0", count: 20))
    }

    /// A packaged binary whose shipped tree was stamped for another binary refuses, naming the path and both hashes and that there is no checkout.
    @Test
    func apackagedBinaryWithATreeForAnotherBinaryRefusesNamingBothHashes() throws {
        let scratch = try Scratch()
        let other = String(repeating: "5e", count: 32)
        let fixture = try ShippedTreeFixture(in: scratch.directory, commit: String(repeating: "c0", count: 20), stampedFor: other)

        let answer = try Self.install(scratch, runnerSource: Self.packaged(executable: fixture.binary))

        #expect(answer.verdict.isQualified)
        #expect(answer.text.contains("runner: not installed"))
        #expect(answer.text.contains(ShippedRunner.directory(besideExecutable: fixture.binary).path))
        #expect(answer.text.contains("shipped with binary \(ShortHash.of(other)), this binary is \(ShortHash.of(Self.binaryHash))"))
        #expect(answer.text.contains("no checkout (packaged)"))
        #expect(scratch.runner.binding(forBinary: Self.binaryHash) == nil)
    }

    /// With neither a tree nor a checkout the refusal names both places.
    @Test
    func apackagedBinaryWithNoTreeNamesBothPlacesItLooked() throws {
        let scratch = try Scratch()
        let binary = scratch.installedBinary

        let answer = try Self.install(scratch, runnerSource: Self.packaged(executable: binary))

        #expect(answer.text.contains("runner: not installed — no \(ShippedRunner.directory(besideExecutable: binary).path) beside the binary; this build has no checkout (packaged)"))
    }

    /// The guide is found in the tree a release ships beside the binary, after the directory of the binary itself.
    @Test
    func theGuideIsFoundInTheShippedTree() throws {
        let scratch = try Scratch()
        let fixture = try ShippedTreeFixture(in: scratch.directory, commit: String(repeating: "c0", count: 20), stampedFor: Self.binaryHash)

        let located = InstallHookCommand.locateGuide(explicit: nil, beside: fixture.binary.path)

        guard case let .found(url) = located else {
            Issue.record("no guide found: \(located)")
            return
        }

        #expect(url.standardizedFileURL.path == fixture.tree.appendingPathComponent("SimWalk.md").standardizedFileURL.path)
    }

    private static func packaged(executable: URL) -> RunnerSnapshotSource {
        var source = RunnerSnapshotSource(checkout: nil, binaryHash: binaryHash, run: { _, _ in
            Shell.Result(status: 128, standardOutput: "", standardError: "no git here")
        })
        source.executable = executable
        return source
    }

    /// A registration has to name the binary that is running, not the one that was expected to be — so an invocation carrying a path is standardised, and one that came through PATH is found there.
    @Test
    func theRegisteredPathIsTheBinaryThatIsActuallyRunning() throws {
        let scratch = try TemporaryDirectory()
        let binary = try Self.executableFile(at: scratch.url.appendingPathComponent("prefix/bin/simwalk"))

        #expect(ExecutablePath.resolve(arguments: ["/opt/tools/../tools/simwalk"], environment: [:]) == "/opt/tools/simwalk")
        #expect(ExecutablePath.resolve(arguments: ["simwalk"], environment: ["PATH": "/usr/bin:\(binary.deletingLastPathComponent().path)"]) == binary.standardizedFileURL.path)
    }

    /// The first executable `simwalk` on PATH wins, and empty, relative and non-executable entries are not candidates.
    @Test
    func theFirstMatchOnPathWinsAndUnusableEntriesAreSkipped() throws {
        let scratch = try TemporaryDirectory()
        let first = try Self.executableFile(at: scratch.url.appendingPathComponent("first/simwalk"))
        let second = try Self.executableFile(at: scratch.url.appendingPathComponent("second/simwalk"))
        let plain = scratch.url.appendingPathComponent("plain/simwalk")
        try FileManager.default.createDirectory(at: plain.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not executable".utf8).write(to: plain)

        let both = [plain.deletingLastPathComponent().path, first.deletingLastPathComponent().path, second.deletingLastPathComponent().path]
        #expect(ExecutablePath.resolve(arguments: ["simwalk"], environment: ["PATH": both.joined(separator: ":")]) == first.standardizedFileURL.path)
        let unusable = ["", "first", "."] + [second.deletingLastPathComponent().path]
        #expect(ExecutablePath.resolve(arguments: ["simwalk"], environment: ["PATH": unusable.joined(separator: ":")]) == second.standardizedFileURL.path)
    }

    /// A package manager's bin directory holds a link into its versioned tree; the registration names the link, which survives an upgrade, not the tree it points at.
    @Test
    func aSymlinkOnPathIsRegisteredAsItselfNotItsTarget() throws {
        let scratch = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: scratch, commit: String(repeating: "c0", count: 20), stampedFor: Self.binaryHash)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.binary.path)
        let link = try fixture.link(in: scratch)

        let resolved = ExecutablePath.resolve(arguments: ["simwalk"], environment: ["PATH": link.deletingLastPathComponent().path])

        #expect(resolved == link.standardizedFileURL.path)
        #expect(resolved != fixture.binary.standardizedFileURL.path)
    }

    /// With nothing on PATH the answer is the running process's own executable — never a guess at `~/.local/bin`, which a packaged install does not use.
    @Test
    func noMatchOnPathFallsBackToTheProcessExecutableNotTheHomeDirectory() {
        let own = URL(fileURLWithPath: "/somewhere/else/simwalk")

        #expect(ExecutablePath.resolve(arguments: ["simwalk"], environment: ["PATH": "/nonexistent-dir"], processExecutable: own) == "/somewhere/else/simwalk")
        #expect(ExecutablePath.resolve(arguments: [], environment: [:], processExecutable: own) == "/somewhere/else/simwalk")
    }

    /// The guide is found from the link a package manager put on PATH, through to the tree its target ships beside it.
    @Test
    func theGuideIsFoundFromASymlinkedBinary() throws {
        let scratch = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: scratch, commit: String(repeating: "c0", count: 20), stampedFor: Self.binaryHash)
        let link = try fixture.link(in: scratch)

        let located = InstallHookCommand.locateGuide(explicit: nil, beside: link.path)

        guard case let .found(url) = located else {
            Issue.record("no guide found: \(located)")
            return
        }

        #expect(url.resolvingSymlinksInPath().path == fixture.tree.appendingPathComponent("SimWalk.md").resolvingSymlinksInPath().path)
    }

    private static func executableFile(at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// The registration is last precisely so a failure there leaves only files — but a refusal that did not name them would leave somebody with a status line and a user rule pointing at tools nothing registered, and no sign on screen that either exists.
    @Test
    func aregistrationFailureStillNamesTheFilesTheInstallHadWritten() throws {
        let scratch = try Scratch()
        let recorder = scratch.claude(addSucceeds: false)

        let thrown = #expect(throws: HookInstallError.self) {
            try InstallHookCommand.answer(
                locations: scratch.locations(),
                executable: Self.executable,
                claude: recorder,
                guide: .found(scratch.guideSource),
                runnerSource: scratch.runnerSource
            )
        }
        let reason = try #require(thrown?.description)

        #expect(reason.contains("already registered under that name"))
        #expect(reason.contains("uninstall-hook"))
        #expect(reason.contains(scratch.segments.fileURL.path.tildedPath))
        #expect(reason.contains(scratch.guide.path.tildedPath))
        #expect(FileManager.default.fileExists(atPath: scratch.segments.fileURL.path))
    }

    /// Every `PreToolUse` hook command in a settings object, in order.
    private static func preToolUseCommands(in settings: [String: Any]) -> [String] {
        let groups = (settings["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private static var executable: String {
        "/Users/x/.local/bin/simwalk"
    }

    /// The SHA-256 the binary being installed stands in with.
    fileprivate static var binaryHash: String {
        String(repeating: "ab", count: 32)
    }

    /// The commit the scratch checkout stands at.
    fileprivate static var commit: String {
        "c0ffee0123456789c0ffee0123456789c0ffee01"
    }

    fileprivate static var runnerFile: String {
        "Runner/SimWalkRunner.xcodeproj/project.pbxproj"
    }

    private static func install(_ scratch: Scratch, runnerSource: RunnerSnapshotSource? = nil) throws -> Answer {
        try InstallHookCommand.answer(
            locations: scratch.locations(),
            executable: executable,
            claude: scratch.claude(),
            guide: .found(scratch.guideSource),
            runnerSource: runnerSource ?? scratch.runnerSource
        )
    }
}

extension HookInstallTests {
    /// A throwaway stand-in for the four places an install writes.
    struct Scratch {
        let directory: TemporaryDirectory
        init() throws {
            directory = try TemporaryDirectory()
            let project = checkout.appendingPathComponent(HookInstallTests.runnerFile)
            try FileManager.default.createDirectory(at: project.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("// the runner\n".utf8).write(to: project)
            try Data("---\npaths:\n  - \"**/project.yml\"\n---\n\n# Using simwalk\n".utf8).write(to: guideSource)
        }

        /// The runner store the install snapshots into.
        var runner: RunnerStore {
            RunnerStore(directory: directory.url.appendingPathComponent("simwalk/runner"))
        }

        /// The checkout the runner is snapshotted from — files on disk, with `git`'s three answers about them scripted: what the install does with a checkout is the claim here, and `RunnerProjectTests` holds it against real `git`.
        var checkout: URL {
            directory.url.appendingPathComponent("checkout", isDirectory: true)
        }

        /// The scratch checkout, and a binary hash standing in for the one being installed.
        var runnerSource: RunnerSnapshotSource {
            runnerSource(at: HookInstallTests.commit)
        }

        /// The same checkout standing at `commit`, as a re-run from a checkout that has moved would find it.
        func runnerSource(at commit: String, repoint: Bool = false) -> RunnerSnapshotSource {
            RunnerSnapshotSource(checkout: checkout, binaryHash: HookInstallTests.binaryHash, run: { _, arguments in
                let output = switch Array(arguments.dropFirst(2)) {
                case ["rev-parse", "HEAD"]: "\(commit)\n"
                case ["ls-files", "-v"]: "H \(HookInstallTests.runnerFile)\n"
                case _ where arguments.contains("ls-files"): "\(HookInstallTests.runnerFile)\0"
                default: ""
                }
                return Shell.Result(status: 0, standardOutput: output, standardError: "")
            }, repoint: repoint)
        }

        /// The binary a deploy installed, which a test writes when it needs one.
        var installedBinary: URL {
            directory.url.appendingPathComponent("bin/simwalk")
        }

        /// A runner an older install left behind: its binding, `binary`'s, and its snapshot, both last touched `days` ago.
        func oldInstall(binary: String, days: Double) throws -> (binding: URL, snapshot: URL) {
            let bindings = runner.directory.appendingPathComponent("binaries", isDirectory: true)
            try FileManager.default.createDirectory(at: bindings, withIntermediateDirectories: true)
            let snapshot = runner.snapshotsDirectory.appendingPathComponent("old-\(binary)", isDirectory: true)
            try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4096).write(to: snapshot.appendingPathComponent("file"))
            let binding = bindings.appendingPathComponent("\(binary).json")
            try JSONEncoder().encode(RunnerStore.Binding(commit: "old-\(binary)", contentHash: "", snapshot: snapshot.path, checkout: "/checkout")).write(to: binding)
            for url in [binding, snapshot] {
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 24 * 60 * 60)], ofItemAtPath: url.path)
            }
            return (binding, snapshot)
        }

        /// The guide as it sits in a checkout or a distribution bundle, which the install copies from.
        var guideSource: URL {
            directory.url.appendingPathComponent("SimWalk.md")
        }

        var settings: URL {
            directory.url.appendingPathComponent("claude/settings.json")
        }

        /// Under a directory of its own, because `SimWalk.md` and `simwalk.md` are one file on a case-insensitive filesystem.
        var guide: URL {
            directory.url.appendingPathComponent("claude/rules/simwalk.md")
        }

        /// Claude Code's `.claude.json`, which the fake `claude` keeps and the install reads back.
        var config: URL {
            directory.url.appendingPathComponent("claude.json")
        }

        func claude(addSucceeds: Bool = true) -> RecordingClaude {
            RecordingClaude(config: config, addSucceeds: addSucceeds)
        }

        var segments: StatuslineSegments {
            StatuslineSegments(directory: directory.url.appendingPathComponent("sift/statusline.d"))
        }

        /// `sift: false` is the machine with no sift on it, where the status line takes Claude Code's own slot.
        func locations(sift: Bool = true) -> HookLocations {
            HookLocations(
                settings: settings,
                config: config,
                rule: guide,
                segments: sift ? segments : nil,
                visibility: StatuslineVisibility(cacheDirectory: directory.url.appendingPathComponent("simwalk/statusline")),
                runner: runner,
                runnerBuilds: RunnerBuilds(directory: directory.url.appendingPathComponent("simwalk/runner-builds")),
                installedBinary: installedBinary
            )
        }
    }
}
