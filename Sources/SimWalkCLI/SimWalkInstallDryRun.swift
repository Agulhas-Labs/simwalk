//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// What `simwalk install --dry-run` says: per agent, the files and registrations its step would change, and none of them touched.
///
/// Claude Code's lines follow the decisions `install-hook` makes: whether `claude` is on PATH (without it the hook, status line, guide and server are all skipped, and the runner alone is installed), and where the status line goes (sift's segment file where sift is installed, `settings.json` otherwise). Nothing is compared with what is there, so each file is worded "would install or update" and a re-run says the same.
struct SimWalkInstallDryRun {
    static func lines(_ picks: [AgentSelection.Pick], binary: String, environment: [String: String], cursorDirectory: String?, claude: ClaudeDecisions? = nil) -> [String] {
        var lines = ["dry run: nothing is written and no `claude` runs"]
        for pick in picks {
            switch pick.agent {
            case .claude:
                let decisions = claude ?? ClaudeDecisions(locations: nil, claudeOnPath: true)
                lines += claudeLines(decisions, binary: binary, environment: environment)
            case .cursor:
                let directory = cursorDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? AgentPaths.cursorDirectory(environment: environment)
                lines.append("cursor: would register the simwalk MCP server in \(directory.appendingPathComponent(AgentPaths.cursorMcpFileName).path)")
                lines.append("cursor: would register the preToolUse hook in \(directory.appendingPathComponent(AgentPaths.cursorHooksFileName).path)")
            case .codex:
                lines.append("codex: not supported by simwalk yet — would be skipped")
            }
        }
        return lines
    }

    private static func claudeLines(_ decisions: ClaudeDecisions, binary: String, environment: [String: String]) -> [String] {
        let settings = decisions.locations?.settings ?? AgentPaths.claudeSettings(environment: environment)
        let rule = decisions.locations?.rule ?? AgentPaths.claudeRule(named: FieldworkTool.simwalk.installedRuleName, environment: environment)
        var lines = ["claude: would snapshot the walk runner for this binary and prune old runner paths no install uses"]
        guard decisions.claudeOnPath else {
            lines.append("claude: `claude` is not on PATH, so the hook, status line, guide and `claude mcp add` would be skipped (the step would fail)")
            return lines
        }
        lines.append("claude: would install or update the PreToolUse hook `\(binary) \(SimWalkClaudeSetup.hookSubcommand)` in \(settings.path)")
        if let segments = decisions.locations?.segments {
            lines.append("claude: would install or update the status line segment \(segments.fileURL.path) — sift runs it")
        } else {
            lines.append("claude: would set the status line in \(settings.path) unless another is already there")
        }
        lines.append("claude: would install or update the agent guide at \(rule.path)")
        lines.append("claude: would run `claude mcp add` to register the simwalk MCP server (`\(binary) mcp`) unless it is already registered")
        return lines
    }
}

extension SimWalkInstallDryRun {
    /// What the Claude Code step settles before it writes anything: where it writes, and whether `claude` is there to register with.
    struct ClaudeDecisions {
        let locations: HookLocations?
        let claudeOnPath: Bool
    }
}
