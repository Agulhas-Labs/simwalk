//
// Copyright © Agulhas Labs
//

import Fieldwork

/// What SimWalk registers with Cursor: the MCP server in `mcp.json` and the `preToolUse` hook in `hooks.json`, through the shared library's installers.
///
/// Cursor runs the hook as `<binary> hook pre-tool-use --agent cursor`, the same subcommand Claude Code's registration runs plus the flag that names the harness.
struct SimWalkCursorSetup {
    /// What SimWalk has no Cursor equivalent for, said once in the install summary.
    static let unsupported = [
        "unsupported on Cursor: the status line — Cursor has no status line",
        "unsupported on Cursor: the agent guide as a machine-wide rule — Cursor's rules are per project",
    ]

    static var experimental: String {
        "experimental: Cursor support has not yet been verified end to end in a live Cursor"
    }

    static let mcp = CursorMcpFile(server: SimWalkClaudeSetup.server)

    static let hooks = CursorHooksFile(
        tool: .simwalk,
        agentFlag: "--agent cursor",
        hooks: [CursorHooksFile.Hook(event: "preToolUse", subcommand: SimWalkClaudeSetup.hookSubcommand)]
    )

    static let install = CursorInstall(mcp: mcp, hooks: hooks, directoryFlag: "--cursor-dir")

    static let installer = CursorHookInstaller(cursor: install, unsupported: unsupported, experimental: experimental)

    static let step = CursorInstallStep(installer: installer)
}
