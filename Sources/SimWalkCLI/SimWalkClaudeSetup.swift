//
// Copyright © Agulhas Labs
//

import Fieldwork
import SimWalkMCP

/// What SimWalk registers with Claude Code, as values for the shared Fieldwork library: its identity and the hook events it registers.
///
/// The library does the registering; this is the one place that says what SimWalk registers, so its identity is spelled once.
struct SimWalkClaudeSetup {
    /// The words after the binary on the registered hook command.
    static var hookSubcommand: String {
        "hook pre-tool-use"
    }

    /// The `PreToolUse` hook that tags a command-line call's usage line with its session (SimWalk#14).
    ///
    /// Only shell calls can start this tool's process, and they and the Xcode build MCP server's tools are the ways to drive a simulator by hand (SimWalk#12), so only they are worth a process launch. Five seconds is generous for a hook that does one small write and short enough that a hung one costs a call five seconds rather than the default minute.
    static let preToolUse = HookRegistration.Event(
        name: "PreToolUse",
        subcommand: hookSubcommand,
        matchers: ["Bash|mcp__XcodeBuildMCP__.*"],
        timeout: 5
    )

    /// Every event SimWalk registers for.
    static let events = [preToolUse]

    /// The hooks SimWalk registers in a Claude Code `settings.json`.
    static let hooks = HookRegistration(tool: .simwalk, events: events)

    /// The user-scope MCP server SimWalk registers, with no npm package: SimWalk does not ship on npm, so the server is never registered through `npx`.
    ///
    /// Removed at user scope and with no scope, since an earlier `claude mcp add` by hand leaves a scopeless entry that would shadow the new one.
    static let server = ClaudeMcpServer(tool: .simwalk, arguments: ["mcp"], removal: .userScopeAndUnscoped)

    /// The MCP server half of the install.
    static let mcp = ClaudeMcpInstall(server: server)

    /// The agent rule: the `SimWalk.md` that Homebrew and the release tarball ship beside the binary (no script writes it), loaded on walkbooks, capture bundles and UI-test files.
    static let rule = ClaudeRuleInstall(tool: .simwalk, shippedFileName: "SimWalk.md", shareDirectory: "simwalk", loadsOn: "a walkbook, capture bundle or UI-test file", installCommand: "simwalk install-hook", shippedBy: "Homebrew or the release tarball", writtenBy: nil)
}

extension FieldworkTool {
    /// SimWalk as Fieldwork names it: its binary, and the subcommands its registered hooks run.
    static let simwalk = FieldworkTool(name: SimWalkPaths.binaryName, hookSubcommands: SimWalkClaudeSetup.events.map(\.subcommand))
}
