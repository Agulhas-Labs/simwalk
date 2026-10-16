//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver
import SimWalkMCP

/// `simwalk install-hook` — snapshots the walk runner for this binary, and, where Claude Code is installed, registers the MCP server, the status line, the `PreToolUse` hook and the agent guide with it.
///
/// Without `claude` on PATH the runner is still installed and the registrations are skipped, with a qualified answer saying so.
///
/// **The runner is snapshotted here, and only here (SimWalk#16).** The runner and the CLI are two halves of one versioned contract, so the install copies the runner's sources out of the checkout this binary was compiled from and pairs the copy with the binary's SHA-256. A walk builds that copy, whatever the checkout does afterwards — which is why an install is what makes a new binary walkable, and a binary copied in without one refuses to walk rather than borrowing another commit's runner.
///
/// Safe to re-run, and re-running is the upgrade path for the registrations: the MCP entry is replaced rather than duplicated, a status line already pointing at this binary is left alone, and a moved binary is repointed everywhere it is named. **Not for the runner**: a binary keeps the runner it was first installed with, and a re-run from a checkout that has moved says so rather than re-pairing it (`--repoint-runner` does, explicitly).
///
/// **The writes into files come before the one call out of the process.** Registering the server reaches `claude`, which owns its own configuration and can refuse; the runner snapshot, the status line, the hook entry and the guide are this tool's own files and can be redone. Doing the reversible ones first means a refusal from the last step leaves a machine with no server registered and only this tool's own files — two the uninstall takes back, and a runner snapshot under `~/.simwalk` — where the other order leaves a registered server and a throw partway through the files.
struct InstallHookCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "install-hook",
            abstract: "Install the walk runner, and register the MCP server, status line, PreToolUse hook and agent guide with Claude Code where it is installed (idempotent; re-run to upgrade)."
        )
    }

    @Option(name: .customLong("settings"), help: "Settings file to edit (defaults to ~/.claude/settings.json). Takes the PreToolUse hook always, and the status line only where sift is not installed to own that slot.")
    var settings: String?

    @Option(name: .customLong("guide"), help: "The agent guide to install (defaults to SimWalk.md beside this binary, then in the share/simwalk tree a packaged release ships beside it, then in the working directory).")
    var guide: String?

    @Option(name: .customLong("rule"), help: "Where to install it (defaults to ~/.claude/rules/simwalk.md).")
    var rule: String?

    @Flag(name: .customLong("repoint-runner"), help: "Re-pair this binary with the runner in its checkout now, replacing the one it was installed with. Without it a binary keeps its first runner, so a moved checkout cannot pair it with another commit's.")
    var repointRunner = false

    func run() throws {
        LaunchedBinary.capture()
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) { try answer() }
    }

    /// The same run with its three effects and the answer itself injectable, so the fallback kind an unmapped failure records can be checked without a `claude` on the machine or a real home directory.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        // An unmapped failure here is Claude Code's own configuration or this tool's own registration
        // files (the status-line segment, the settings merge, the guide) — never a caller's argument.
        try TimedCall.run(tool: "install-hook", target: nil, log: log, emit: emit, emitError: emitError, defaultFailureKind: .setupFailed, isStdoutPiped: isStdoutPiped, body: body)
    }

    /// What the install did, in the contract's shape: every step named, and every step it could not take carried on the verdict.
    func answer() throws -> Answer {
        let executable = ExecutablePath.current
        return try Self.answer(
            locations: HookLocations.standard(settings: settings, rule: rule),
            executable: executable,
            claude: ClaudeCommandLine.resolve(),
            guide: Self.locateGuide(explicit: guide, beside: executable),
            runnerSource: RunnerSnapshotSource(
                checkout: RunnerProject.compiledCheckout,
                binaryHash: LaunchedBinary.hash,
                run: { try Shell().run($0, $1) },
                repoint: repointRunner,
                executable: LaunchedBinary.url
            )
        )
    }

    /// The same install against stated locations and a stated `claude` — the whole of it, minus the machine.
    static func answer(
        locations: HookLocations,
        executable: String,
        claude: ClaudeCommandLine?,
        guide: GuideSource,
        runnerSource: RunnerSnapshotSource,
        now: Date = Date()
    ) throws -> Answer {
        let serverCommand = [executable, "mcp"]
        var qualifications: [String] = []
        var residue = [installRunner(locations.runner, from: runnerSource, qualifications: &qualifications)]
        residue += pruneRunners(locations: locations, source: runnerSource, now: now, qualifications: &qualifications)
        // The runner is this tool's own and needs no Claude Code, so it is installed either way. The four Claude Code
        // pieces — status line, hook, guide, server — are all done or all skipped: a half-done install would show a
        // status line, or tell an agent to call tools that are not there, with nothing saying which step had not happened.
        guard let claude else {
            qualifications.append("'claude' is not on PATH, so Claude Code's registrations were skipped. Walks work without them. To finish, install Claude Code and re-run `simwalk install-hook`, or register the server with another MCP client: \(ClaudeCommandLine.manualRegistration(command: serverCommand)) (the server is `\(executable.tildedPath) mcp`)")
            return Answer(
                header: "binary: \(executable.tildedPath)",
                verdict: .reporting(qualifications: qualifications, detail: "runner installed — Claude Code not found, its registrations skipped"),
                residue: residue
            )
        }
        var settingsBackedUp = false
        residue += try statusline(locations: locations, executable: executable, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp)
        residue += registerPreToolUseHook(settings: locations.settings, executable: executable, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp)
        residue += installGuide(locations.guide, from: guide, qualifications: &qualifications)
        do {
            try claude.registerServer(command: serverCommand)
        } catch let HookInstallError.claudeRefused(command, reason, _) {
            // The refusal carries what was already written. This is the last step precisely so a failure
            // here leaves only files, but a refusal that did not name them would leave somebody with a
            // status line and a user rule pointing at tools nothing registered — and no sign either exists.
            throw HookInstallError.claudeRefused(command: command, reason: reason, written: residue)
        }
        residue.append("mcp: registered at user scope — \"\(executable.tildedPath)\" mcp")

        return Answer(
            header: "binary: \(executable.tildedPath)",
            verdict: .reporting(qualifications: qualifications, detail: "registered for Claude Code — start a new session to pick it up"),
            residue: residue
        )
    }

    /// The guide to install, or why there is none.
    ///
    /// **A named `--guide` is the only candidate.** Falling through to another file when the one the caller pointed at cannot be read would install a *different* guide from the one they asked for and report success over it — and on an upgrade that means silently reinstalling last release's copy sitting beside the binary.
    static func locateGuide(explicit: String?, beside executable: String) -> GuideSource {
        let manager = FileManager.default
        if let explicit {
            let named = URL(fileURLWithPath: explicit)
            guard manager.isReadableFile(atPath: named.path) else {
                return .missing(reason: "--guide names \(explicit.tildedPath), which cannot be read")
            }
            return .found(named)
        }
        let candidates = [
            URL(fileURLWithPath: executable).deletingLastPathComponent().appendingPathComponent(guideName),
            ShippedRunner.directory(besideExecutable: URL(fileURLWithPath: executable)).appendingPathComponent(guideName),
            URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent(guideName),
        ]
        guard let found = candidates.first(where: { manager.isReadableFile(atPath: $0.path) }) else {
            return .missing(reason: "no readable \(guideName) at \(candidates.map(\.path.tildedPath).joined(separator: ", "))")
        }
        return .found(found)
    }

    /// The guide's filename in the repository and in a distribution bundle — one spelling, since the installer looks for it and the repository has to hold it under that name.
    static var guideName: String {
        "SimWalk.md"
    }

    /// `pruneRunners`'s whole report — the one place that decides it, so a test exercising this function pins `pruneRunners`'s wiring too (SimWalk#33 review) — separated out so a manufactured plan and outcome can pin its wording without racing a real removal.
    ///
    /// Distinguishes "nothing to prune" (no candidates at all) from every candidate surviving to be spared at removal time — a walk or install resolved between the plan and the removal (`RunnerPrune/execute(_:)`) — and lists each spared entry with why, rather than folding it into the same "nothing to prune" a plan with no candidates at all sees.
    static func describe(pruning plan: RunnerPrune.Plan, outcome: RunnerPrune.Outcome, qualifications: inout [String]) -> [String] {
        guard !plan.removals.isEmpty else {
            return ["runners: nothing to prune"]
        }
        if let failed = AnswerVerdict.qualification(outcome.failed.count, "old runner path", "could not be removed") {
            qualifications.append(failed)
        }
        let failures = outcome.failed.isEmpty ? "" : "; \(outcome.failed.count) could not be removed — `simwalk prune` names them"
        guard !outcome.spared.isEmpty else {
            return outcome.removed.isEmpty
                ? ["runners: pruned 0 paths\(failures)"]
                : ["runners: pruned \(outcome.removed.count) paths, freed \(ByteSize.short(outcome.freed))\(failures)"]
        }
        qualifications.append("\(outcome.spared.count) old runner \(outcome.spared.count == 1 ? "path was" : "paths were") spared, not pruned")
        let headline = outcome.removed.isEmpty
            ? "runners: \(plan.removals.count) candidate\(plan.removals.count == 1 ? "" : "s"), \(outcome.spared.count) spared\(failures)"
            : "runners: pruned \(outcome.removed.count) of \(plan.removals.count) paths, freed \(ByteSize.short(outcome.freed)), \(outcome.spared.count) spared\(failures)"
        var lines = [headline]
        lines += outcome.spared.map { "           spared \($0.url.path.tildedPath) — \($0.reason)" }
        return lines
    }
}

private extension InstallHookCommand {
    /// The walk runner, snapshotted and paired with the binary — from the tree a packaged release ships beside it when that tree is stamped for this binary, else from the checkout this binary was compiled from, else nothing, and the line says where it looked and why each place was unusable.
    ///
    /// Not fatal when it cannot be taken, like the guide: the rest of the install still stands, and a walk from this binary then refuses naming the fix rather than building some other commit's runner. Said on the verdict, because that refusal is the next thing the person will meet.
    static func installRunner(_ store: RunnerStore, from source: RunnerSnapshotSource, qualifications: inout [String]) -> String {
        guard let binaryHash = source.binaryHash else {
            qualifications.append("the walk runner was not installed")
            return "runner: not installed — this binary could not be read to pair a runner with it; walks from it refuse until it is"
        }
        do {
            var looked: [String] = []
            let installed: RunnerStore.Installation
            var fromShippedTree = false
            if let shipped = Self.shippedTree(for: source, binaryHash: binaryHash, looked: &looked) {
                fromShippedTree = true
                installed = try store.install(shipped: shipped, binaryHash: binaryHash, repoint: source.repoint)
            } else if let checkout = source.checkout {
                installed = try store.install(checkout: checkout, binaryHash: binaryHash, repoint: source.repoint, run: source.run)
            } else {
                looked.append("this build has no checkout (packaged)")
                qualifications.append("the walk runner was not installed")
                return "runner: not installed — \(looked.joined(separator: "; ")); walks from this binary refuse until it is"
            }
            let commit = describe(installed.binding.commit)
            let binary = "this binary (sha256 \(ShortHash.of(binaryHash)))"
            switch installed.outcome {
            case .snapshotted:
                return "runner: \(commit) snapshotted at \(installed.binding.snapshot.tildedPath), paired with \(binary)"
            case .reusedSnapshot:
                return "runner: \(commit) already snapshotted at \(installed.binding.snapshot.tildedPath), paired with \(binary)"
            case .unchanged:
                return "runner: unchanged — \(binary) goes with \(commit)"
            case let .kept(checkoutCommit):
                // Kept, and said on the verdict: the checkout has moved since this binary was built from it, and
                // pairing the two would put a runner from one commit beside a CLI from another (SimWalk#16).
                qualifications.append("the runner this binary was installed with was kept, not repointed")
                return "runner: kept — \(binary) is already paired with runner \(commit), and \(fromShippedTree ? "the shipped runner beside it is" : "the checkout now holds") \(describe(checkoutCommit)); a binary keeps the runner it was installed with. Rebuild and install to pair a new binary, or pass --repoint-runner to replace this one's"
            case let .repointed(previous):
                return "runner: repointed — \(binary) now goes with \(commit), snapshotted at \(installed.binding.snapshot.tildedPath) (was \(describe(previous.commit))), as --repoint-runner asked"
            }
        } catch {
            qualifications.append("the walk runner was not installed")
            return "runner: not installed — \(error); walks from this binary refuse until it is"
        }
    }

    /// The tree shipped beside the binary, when it is stamped for this binary; otherwise `nil`, with why appended to `looked`.
    static func shippedTree(for source: RunnerSnapshotSource, binaryHash: String, looked: inout [String]) -> ShippedRunner? {
        guard let executable = source.executable else {
            looked.append("the binary's own path is unknown, so no shipped runner tree could be looked for")
            return nil
        }
        do {
            return try ShippedRunner.find(besideExecutable: executable, binaryHash: binaryHash)
        } catch {
            looked.append("\(error)")
            return nil
        }
    }

    /// The runners no kept install or live checkout uses, removed once the new one is paired (SimWalk#22) — `simwalk prune --dry-run` lists what was kept and why.
    ///
    /// Taken only once this binary is paired with a runner, since that is the one runner a prune must never touch, and never from a development build, whose pairing is gone at its next build — `simwalk prune` from the installed binary does it then. Not fatal when a removal fails, like the other steps, but said on the verdict.
    static func pruneRunners(locations: HookLocations, source: RunnerSnapshotSource, now: Date, qualifications: inout [String]) -> [String] {
        guard let binaryHash = source.binaryHash, locations.runner.binding(forBinary: binaryHash) != nil else {
            qualifications.append("old walk runners were not pruned")
            return ["runners: not pruned — this binary has no runner paired with it to keep"]
        }
        if let executable = source.executable, let checkout = source.checkout, RunnerProject.isDevelopmentBuild(executable, of: checkout) {
            qualifications.append("old walk runners were not pruned")
            return ["runners: not pruned — this is a development build, whose runner pairing is gone at its next build; `simwalk prune` from the installed binary prunes"]
        }
        let prune = RunnerPrune(store: locations.runner, builds: locations.runnerBuilds)
        let installed = RunnerProject.hash(ofExecutableAt: locations.installedBinary)
        let plan = prune.plan(keepingBinary: binaryHash, installedBinary: installed, now: now)
        return describe(pruning: plan, outcome: prune.execute(plan), qualifications: &qualifications)
    }

    /// A runner commit as a line prints it: eight digits, and whether it was a working tree with changes.
    static func describe(_ commit: String) -> String {
        ShortHash.of(commit) + (commit.contains("-dirty") ? " (a working tree with changes)" : "")
    }

    /// The status line, wherever this machine keeps one.
    ///
    /// Claude Code has a single `statusLine` slot. Where sift is installed it owns that slot and runs every executable in its segment directory, so a segment file is the whole registration and neither tool has to give way. Where sift is absent the slot is taken directly — but only when it is free or already ours.
    static func statusline(locations: HookLocations, executable: String, qualifications: inout [String], settingsBackedUp: inout Bool) throws -> [String] {
        var lines: [String] = []
        if let segments = locations.segments {
            let path = segments.fileURL.path.tildedPath
            let outcome = try segments.install(executable: executable)
            let line = switch outcome {
            case .written: "statusline: \(path) — sift runs it and appends its line to its own"
            case .unchanged: "statusline: unchanged — \(path)"
            }
            lines.append(line)
        } else {
            // Not fatal, as the hook step's own failure is not (SimWalk#14 review): a settings file this cannot
            // read stops this registration, not the guide and MCP registrations that come after it.
            do {
                lines += try registerStatuslineInSettings(locations: locations, executable: executable, qualifications: &qualifications, settingsBackedUp: &settingsBackedUp)
            } catch {
                qualifications.append("the status line was not registered")
                lines.append("statusline: not registered — \(locations.settings.path.tildedPath): \(error)")
            }
        }
        // A hidden line looks exactly like a broken one, so an install that leaves it hidden says so.
        if locations.visibility.isHidden {
            lines.append("           hidden on this machine — `simwalk statusline --show` brings it back")
        }
        return lines
    }

    static func registerStatuslineInSettings(locations: HookLocations, executable: String, qualifications: inout [String], settingsBackedUp: inout Bool) throws -> [String] {
        let settingsURL = locations.settings
        let path = settingsURL.path.tildedPath
        // Quoted for the reason the segment shim quotes it: Claude Code runs this through a shell, and an
        // unquoted path with a space in it becomes a command and an argument.
        let command = "\"\(executable)\" statusline"
        let original = try? Data(contentsOf: settingsURL)
        switch try StatuslineRegistration.apply(to: original, command: command, path: path) {
        case let .installed(updated):
            // Backed up before this run's first rewrite: this is somebody's whole Claude Code configuration
            // and this tool did not author it, so a copy is cheap insurance against a merge bug on a machine
            // where nobody is watching. Once per run — a later step's own backup would otherwise overwrite
            // this pristine copy with the settings this step already edited.
            backUpSettingsOnce(original, to: settingsURL, backedUp: &settingsBackedUp)
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: settingsURL, options: .atomic)
            return ["statusline: registered in \(path) — \"\(executable.tildedPath)\" statusline"]
        case .unchanged:
            return ["statusline: already registered in \(path)"]
        case let .refused(existing):
            // Never clobbered: composing two status lines is the user's call, and guessing at how would
            // mangle output they built.
            qualifications.append("the status line slot is already taken")
            return [
                "statusline: left alone — \(path) already has one (\(existing))",
                "           add this to it: \"\(executable.tildedPath)\" statusline",
            ]
        }
    }

    /// The `PreToolUse` hook that tags a command-line call's usage line with its session, so the status line can price a walk made from the shell (SimWalk#14).
    ///
    /// Merged into the hook list beside whatever else is there — never over it — and refused, with the reason on the verdict, where the list is in a shape this cannot read. **Not fatal, including a `settings.json` this cannot even parse**: every other registration still stands, and a call made without the hook is only logged untagged — so a thrown `settingsNotAnObject` is caught here rather than left to abort the guide and the MCP registration behind it.
    static func registerPreToolUseHook(settings settingsURL: URL, executable: String, qualifications: inout [String], settingsBackedUp: inout Bool) -> [String] {
        let path = settingsURL.path.tildedPath
        // Quoted for the status line's reason: Claude Code runs it through a shell.
        let command = "\"\(executable)\" \(PreToolUseRegistration.subcommand)"
        let original = try? Data(contentsOf: settingsURL)
        do {
            switch try PreToolUseRegistration.apply(to: original, command: command, path: path) {
            case let .installed(updated):
                backUpSettingsOnce(original, to: settingsURL, backedUp: &settingsBackedUp)
                try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try updated.write(to: settingsURL, options: .atomic)
                return ["hook: PreToolUse registered in \(path) — \"\(executable.tildedPath)\" \(PreToolUseRegistration.subcommand)"]
            case .unchanged:
                return ["hook: PreToolUse already registered in \(path)"]
            case let .refused(existing):
                qualifications.append("the PreToolUse hook was not registered")
                return ["hook: not registered — \(path) has \(existing); shell calls are logged without their session until it is"]
            }
        } catch {
            qualifications.append("the PreToolUse hook was not registered")
            return ["hook: not registered — \(path): \(error)"]
        }
    }

    /// Backs up `settingsURL` from `original` bytes before this run's first rewrite of it, and never again — a second step editing the same file in the same run would otherwise back up what the first step already edited, overwriting the pristine copy.
    static func backUpSettingsOnce(_ original: Data?, to settingsURL: URL, backedUp: inout Bool) {
        guard !backedUp, let original, !original.isEmpty else { return }
        try? original.write(to: settingsURL.appendingPathExtension("bak-simwalk"))
        backedUp = true
    }

    /// The agent guide, installed as a path-scoped user rule so it costs nothing in a session that never touches a walkbook, a capture bundle or a UI-test target.
    ///
    /// Not fatal when it cannot be found or written: the status line is in place by then and the server registration follows, and a missing guide is a thing to say rather than a thing to unwind an install over.
    static func installGuide(_ guide: AgentGuide, from source: GuideSource, qualifications: inout [String]) -> [String] {
        let path = guide.fileURL.path.tildedPath
        switch source {
        case let .missing(reason):
            qualifications.append("the agent guide was not installed")
            return ["rule: not installed — \(reason); copy it to \(path) by hand"]
        case let .found(url):
            do {
                switch try guide.install(from: url) {
                case .installed:
                    return ["rule: \(path) (loads when a walkbook, capture bundle or UI-test file is open)"]
                case .unchanged:
                    return ["rule: unchanged — \(path)"]
                case let .symlink(target):
                    // A symlink means this machine has the checkout and the rule *is* the repo file.
                    // Copying would follow the link and write through it, silently reverting a newer
                    // working tree to whatever this binary was built beside.
                    return ["rule: \(path) is a symlink to \(target.tildedPath) — left as is"]
                }
            } catch {
                qualifications.append("the agent guide was not installed")
                return ["rule: not installed — \(path): \(error)"]
            }
        }
    }
}

extension InstallHookCommand {
    /// The guide this install has to work with: a file, or the sentence saying why there is none.
    ///
    /// A named `--guide` that cannot be read lands here as `missing` carrying its own reason rather than falling through to the next candidate — the difference between "no guide was found" and "the guide you named is not readable" is the whole of what the caller needs told.
    enum GuideSource: Equatable {
        case found(URL)
        case missing(reason: String)
    }
}
