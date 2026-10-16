//
// Copyright © Agulhas Labs
//

import ArgumentParser

/// `simwalk hook` — the verbs Claude Code runs as hooks, one subcommand per hook event, registered by `install-hook` (SimWalk#14).
///
/// A group rather than a flag on one verb, so a hook for another event is another subcommand beside `pre-tool-use` and the registered command line names the event it answers.
struct HookCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "hook",
            abstract: "Run as a Claude Code hook (registered by install-hook; reads the hook payload on stdin).",
            subcommands: [PreToolUseCommand.self]
        )
    }
}
