//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkMCP

/// `simwalk doctor` — proves each agent `simwalk install` would set up is wired end to end: the registration, the registered binary, each hook fed a payload of that agent's shape, and the server's tool list.
///
/// Detection and every path come from the same ``AgentDetection/Machine`` and Fieldwork setup values the install uses, so the two cannot disagree about where an agent lives. Everything it runs runs in a scratch directory with `HOME` pointed into it, removed before it answers. Codex is not checked, since SimWalk does not support it.
struct DoctorCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "doctor",
            abstract: "Check that each agent simwalk is installed into really runs it: registration, binary, hooks, MCP server, version.",
            discussion: """
            One line per check. With no --agent, only the agents found on this machine are checked; one not found is named on a line and skipped, neither counted nor failed. An agent found with nothing of simwalk's in it is named on a line and not counted; one with some of simwalk's installed but broken still fails. --agent names the agents to check, found or not. Exits 1 when a check failed, or when agents were found and none has simwalk installed. Codex is not checked: simwalk does not support it.
            """
        )
    }

    @Option(name: .customLong("agent"), help: "Check only this agent, found on this machine or not — claude or cursor; repeat for more than one. Codex is not checked.")
    var agents: [DoctorAgent] = []

    @Option(name: .customLong("cursor-dir"), help: "The directory holding Cursor's mcp.json and hooks.json (defaults to ~/.cursor); checks Cursor whether or not it was found.")
    var cursorDirectory: String?

    @Flag(name: .customLong("json"), help: "Print the answer as one JSON object.")
    var json = false

    /// Where each line of the answer goes, injected so a test can read what doctor printed.
    var emit: @Sendable (String) -> Void = StandardStreams.emit

    /// Everything detection reads and every path is resolved from, injected so a test stands in for the whole machine.
    var machine = AgentDetection.Machine(environment: ProcessInfo.processInfo.environment)

    /// Refuses `--cursor-dir` when the agents named leave Cursor out, so the flag is never silently ignored.
    func validate() throws {
        guard cursorDirectory == nil || agents.isEmpty || agents.contains(.cursor) else {
            throw ValidationError("--cursor-dir applies only when Cursor is checked — add --agent cursor")
        }
    }

    func run() throws {
        let report = try diagnose()
        if json {
            try emit(String(bytes: report.encoded(), encoding: .utf8) ?? "{}")
        } else {
            report.lines.forEach(emit)
        }
        if report.failsTheRun {
            throw ExitCode(1)
        }
    }

    /// Every check of every agent asked about: the agents found with no `--agent`, those named with it.
    ///
    /// The skipped are the agents left out for not being found; the not installed are those found with nothing of simwalk's in them, left out of the checks and the verdict unless named.
    func diagnose() throws -> DoctorReport {
        let detection = AgentDetection.detect(machine, tool: .simwalk)
        let probe = try DoctorProbe(tool: .simwalk, version: SimWalkVersion.current, environment: machine.environment, scrubbing: ["SIMWALK_"])
        defer { probe.close() }
        // Every file the hook and the server write (the usage log, the call attribution and nudge ledger beside it) follows `HOME`, which the probe points into its scratch, so nothing more is pointed.
        let tools = SimWalkTool.allCases.map(\.rawValue)
        var checks: [DoctorCheck] = []
        var skipped: [(agent: Agent, lookedFor: [String])] = []
        var notInstalled: [Agent] = []
        let asked = [Agent.claude, .cursor].filter { agent in agents.isEmpty || agents.contains { $0.rawValue == agent.rawValue } }
        for agent in asked {
            let named = !agents.isEmpty || (agent == .cursor && cursorDirectory != nil)
            guard named || detection.finding(agent).isDetected else {
                skipped.append((agent, detection.finding(agent).lookedFor))
                continue
            }
            switch agent {
            case .claude:
                var doctor = DoctorClaude(
                    environment: machine.environment,
                    probe: probe,
                    hooks: SimWalkClaudeSetup.hooks,
                    server: SimWalkClaudeSetup.server,
                    expectedTools: tools,
                    rule: SimWalkClaudeSetup.rule
                )
                if machine.pathLookup("claude") == nil {
                    doctor.manualRegistration = SimWalkClaudeSetup.server.manual(binary: ExecutablePath.current)
                }
                if !named, doctor.hasNothingInstalled {
                    notInstalled.append(agent)
                } else {
                    checks += doctor.checks()
                }
            default:
                let directory = cursorDirectory.map { URL(fileURLWithPath: $0) } ?? AgentPaths.cursorDirectory(environment: machine.environment)
                let doctor = DoctorCursor(directory: directory, probe: probe, install: SimWalkCursorSetup.install, expectedTools: tools)
                if !named, doctor.hasNothingInstalled {
                    notInstalled.append(agent)
                } else {
                    checks += doctor.checks()
                }
            }
        }
        return DoctorReport(tool: .simwalk, checks: checks, skipped: skipped, notInstalled: notInstalled)
    }
}

extension DoctorCommand {
    /// The agents `--agent` names: Codex is not among them, since simwalk does not support it.
    enum DoctorAgent: String, ExpressibleByArgument, CaseIterable {
        case claude
        case cursor
    }

    /// Only the flags come off the command line; the injected parts keep their defaults on the parse path.
    enum CodingKeys: String, CodingKey {
        case agents
        case cursorDirectory
        case json
    }
}
