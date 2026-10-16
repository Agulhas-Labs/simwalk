//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkMCP

/// `simwalk hook pre-tool-use` — Claude Code's `PreToolUse` hook: reads the payload on stdin, leaves the slip that tags a command-line call with its session (SimWalk#14), prints the hand-driving nudge's one-time refusal where there is one (SimWalk#12), and exits 0.
///
/// **Not through `TimedCall`, deliberately.** Every other verb answers a caller and logs the call; this one runs before every shell call a session makes, and stdout is Claude Code's to read as the hook's output, so the only thing written there is the nudge's `PreToolUse` refusal, and a log line would bury the calls the log counts. What it does is ``PreToolUseHook``'s, which says why it never fails.
struct PreToolUseCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "pre-tool-use",
            abstract: "Claude Code's PreToolUse hook: attribute this tool's shell calls to their session, and refuse a hand-driven simulator once where a walkbook drives it."
        )
    }

    func run() {
        // Run by hand at a terminal there is no payload coming, and waiting for one would hang the shell.
        guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { return }
        let payload = FileHandle.standardInput.readDataToEndOfFile()
        let log = UsageLog.standard()
        guard let output = PreToolUseHook.handle(payload, attribution: CallAttribution(beside: log), nudges: NudgeLedger(beside: log)) else { return }
        StandardStreams.emit(output)
    }
}
