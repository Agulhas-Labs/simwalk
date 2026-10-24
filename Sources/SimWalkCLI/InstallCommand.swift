//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore

/// `simwalk install` — finds Claude Code, Cursor and Codex on this machine and sets SimWalk up in each one chosen, ending with one summary.
///
/// Claude Code's step is `install-hook`'s own install, not a copy of it, and its report is what that install changed, so the two cannot drift; `install-hook` stays for Claude Code alone. Codex is not supported yet and is said so, never a failure.
///
/// One agent's failure is said and the others still run; the exit status is 1 when any failed. A second run changes nothing and says so.
struct InstallCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "install",
            abstract: "Set SimWalk up in every agent found on this machine — Claude Code, Cursor — asking once per agent (idempotent; re-run to upgrade).",
            discussion: """
            Without a terminal to ask on, nothing is installed unless --yes, --all or --agent says what to install into.
            Exits 1 when any agent's install failed; the others are still installed. Codex is not supported yet and is skipped.
            """
        )
    }

    @Option(name: .customLong("agent"), help: "Install into this agent — claude, cursor or codex — whether or not it was found, without asking; repeat for more than one.")
    var agents: [InstallAgent] = []

    @Flag(name: .customLong("all"), help: "Install into all three agents, whether or not each was found, without asking.")
    var all = false

    @Flag(name: .customLong("yes"), help: "Install into every agent found, without asking.")
    var yes = false

    @Option(name: .customLong("cursor-dir"), help: "With Cursor installed, the directory holding Cursor's mcp.json and hooks.json to install into (defaults to ~/.cursor); it does not pick Cursor.")
    var cursorDirectory: String?

    @Option(name: .customLong("guide"), help: "For Claude Code, the agent guide to install, as `install-hook --guide` takes it.")
    var guide: String?

    @Flag(name: .customLong("dry-run"), help: "Say what would change in each agent chosen, and pass --dry-run to the other Fieldwork tools' installs; nothing is written and no `claude` runs.")
    var dryRun = false

    /// Where each line of the answer goes, injected so a test can read what the install printed.
    var emit: @Sendable (String) -> Void = StandardStreams.emit

    /// Everything detection reads and every path is resolved from, injected so a test stands in for the whole machine.
    var machine = AgentDetection.Machine(environment: ProcessInfo.processInfo.environment)

    /// Who is asked about each agent found, injected so a test answers for the terminal or its absence.
    var terminal: InstallTerminal = .standard

    /// The binary the registrations name, injected so a test need not run as `simwalk`; `nil` is this process's own path.
    var executable: String?

    /// Where Claude Code's step writes and the `claude` it registers with, injected so a test points `install-hook` at a scratch home and a fake `claude`; `nil` is the machine itself.
    var claudeSurroundings: InstallHookCommand.Surroundings?

    /// How the family step starts another tool's install, injected so a test records the call instead of running a real `sift`.
    var familyLaunch: Family.Launch = Family.launchInheritingTerminal

    /// Refuses `--cursor-dir` when the agents named leave Cursor out, so the flag is never silently ignored.
    func validate() throws {
        guard cursorDirectory == nil || agents.isEmpty || agents.contains(.cursor) else {
            throw ValidationError("--cursor-dir applies only when Cursor is installed — add --agent cursor")
        }
    }

    func run() throws {
        LaunchedBinary.capture()
        let detection = AgentDetection.detect(machine, tool: .simwalk)
        let flags = AgentSelection.Flags(agents: agents.compactMap { Agent(rawValue: $0.rawValue) }, all: all, yes: yes, dryRun: dryRun)
        var selection = AgentSelection.decide(flags, detection: detection, isInteractive: terminal.isInteractive)
        if case let .ask(found) = selection {
            selection = AgentSelection.afterAsking(accepted: InstallPrompt(tool: .simwalk, ask: terminal.ask).choose(found))
        }
        switch selection {
        case .needsFlags:
            emit(AgentSelection.needsFlagsText(detected: detection, tool: .simwalk))
        case .nothingDetected:
            emit(AgentSelection.nothingDetectedText(detection, tool: .simwalk))
        case let .nothingToDo(reason):
            emit(reason)
        case .ask:
            break
        case let .install(picks):
            let binary = executable ?? ExecutablePath.current
            let failed = dryRun ? describe(picks, binary: binary) : install(picks, binary: binary)
            let familyFailed = installFamily(picks, binary: binary)
            if failed || familyFailed {
                throw ExitCode(1)
            }
        }
    }

    /// Says what each pick's step would change, writing nothing; never a failure.
    private func describe(_ picks: [AgentSelection.Pick], binary: String) -> Bool {
        for pick in picks {
            if let note = pick.note {
                emit(note)
            }
        }
        var decisions: SimWalkInstallDryRun.ClaudeDecisions?
        if picks.contains(where: { $0.agent == .claude }) {
            let surroundings = claudeSurroundings ?? (try? InstallHookCommand.parse(guide.map { ["--guide", $0] } ?? []))?.standardSurroundings(environment: machine.environment)
            decisions = surroundings.map { SimWalkInstallDryRun.ClaudeDecisions(locations: $0.locations, claudeOnPath: $0.claude != nil) }
        }
        SimWalkInstallDryRun.lines(picks, binary: binary, environment: machine.environment, cursorDirectory: cursorDirectory, claude: decisions).forEach(emit)
        return false
    }

    /// The other Fieldwork tools' installs, run once into the agents this install ran a step for; true when any member that started did not succeed.
    private func installFamily(_ picks: [AgentSelection.Pick], binary: String) -> Bool {
        let flags = AgentSelection.Flags(agents: picks.map(\.agent), all: false, yes: true, dryRun: dryRun)
        let launch = familyLaunch
        let emit = emit
        let results = Family.install(
            members: SimWalkFamily.members,
            caller: .simwalk,
            flags: flags,
            environment: machine.environment,
            besideDirectory: URL(fileURLWithPath: binary).deletingLastPathComponent().path,
            launch: { executable, arguments, environment in
                emit("family: running \(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " "))")
                return try launch(executable, arguments, environment)
            }
        )
        for result in results where !result.succeeded {
            let name = result.member
            emit(result.launchFailure.map { "family: \(name) install could not be started: \($0)" } ?? "family: \(name) install exited \(result.exitStatus)")
        }
        return results.contains { !$0.succeeded }
    }

    /// Runs each pick's step, printing its note and its section and then the summary; exits 1 when any step failed.
    private func install(_ picks: [AgentSelection.Pick], binary: String) -> Bool {
        var reports: [InstallStepReport] = []
        for pick in picks {
            if let note = pick.note {
                emit(note)
            }
            guard pick.agent != .codex else {
                emit("codex: not supported by simwalk yet — skipped")
                continue
            }
            let report = step(pick.agent, binary: binary)
            Self.summary.section(report).forEach(emit)
            reports.append(report)
        }
        if !reports.isEmpty {
            Self.summary.summary(reports).forEach(emit)
        }
        return reports.contains { !$0.failures.isEmpty }
    }

    /// One agent's step, its lines captured and its failure kept to itself.
    private func step(_ agent: Agent, binary: String) -> InstallStepReport {
        let capture = InstallCapture()
        return InstallStepReport.attempt(agent, capture: capture) {
            switch agent {
            case .claude:
                let installed = try claudeStep(binary: binary)
                installed.answer.text.split(separator: "\n", omittingEmptySubsequences: false).forEach { capture.keep(String($0)) }
                guard installed.claudeFound else {
                    return InstallStepReport(agent: .claude, failures: [Self.claudeMissing])
                }
                return InstallStepReport(agent: .claude, written: installed.written, registered: installed.registered)
            case .cursor:
                let report = try SimWalkCursorSetup.step.run(binary: binary, environment: machine.environment, directory: cursorDirectory)
                report.lines.forEach(capture.keep)
                return report
            case .codex:
                return InstallStepReport(agent: .codex)
            }
        }
    }

    /// Why Claude Code's step installed nothing where `claude` is not on PATH.
    static var claudeMissing: String {
        "'claude' is not on PATH, so Claude Code's registrations were skipped"
    }

    /// What `install-hook` does for this binary — a refusal throws, which `InstallStepReport.attempt` turns into this agent's failure.
    private func claudeStep(binary: String) throws -> InstallHookCommand.Installed {
        let hook = try InstallHookCommand.parse(guide.map { ["--guide", $0] } ?? [])
        return try hook.installed(executable: binary, environment: machine.environment, in: claudeSurroundings)
    }

    /// The summary `simwalk install` prints: the lines Cursor's installer repeats on every run are said once, and its restart line gives way to each agent's next step.
    private static var summary: InstallSummary {
        InstallSummary(tool: .simwalk, saidOnce: SimWalkCursorSetup.unsupported + [SimWalkCursorSetup.experimental], restarts: [CursorHookInstaller.restart])
    }
}

extension InstallCommand {
    /// The agents `--agent` names.
    enum InstallAgent: String, ExpressibleByArgument, CaseIterable {
        case claude
        case cursor
        case codex
    }

    /// Only the flags come off the command line; the injected parts keep their defaults on the parse path.
    enum CodingKeys: String, CodingKey {
        case agents
        case all
        case yes
        case cursorDirectory
        case guide
        case dryRun
    }
}
