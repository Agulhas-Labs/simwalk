//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
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

    @Option(name: .customLong("agent"), help: "The agent running the hook: claude or cursor (default claude). cursor reads Cursor's preToolUse payload and answers in Cursor's schema.")
    var agent: Agent = .claude

    func run() {
        // Run by hand at a terminal there is no payload coming, and waiting for one would hang the shell.
        guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { return }
        let payload = FileHandle.standardInput.readDataToEndOfFile()
        let log = UsageLog.standard()
        let attribution = CallAttribution(beside: log)
        let nudges = NudgeLedger(beside: log)
        guard let answer = Self.answer(for: agent, payload, attribution: attribution, nudges: nudges) else { return }
        StandardStreams.emit(answer)
    }
}

extension PreToolUseCommand {
    /// What the hook prints for `payload` from `agent`, or `nil` for nothing: the one place `--agent` picks the harness, so a test drives the dispatch `run()` does.
    static func answer(for agent: Agent, _ payload: Data, attribution: CallAttribution, nudges: NudgeLedger) -> String? {
        switch agent {
        case .claude: PreToolUseHook.handle(payload, attribution: attribution, nudges: nudges)
        case .cursor: cursorAnswer(payload, attribution: attribution, nudges: nudges)
        }
    }

    /// The harness a hook command answers, named by the `--agent` its registration carries and never sniffed from the payload.
    enum Agent: String, ExpressibleByArgument, CaseIterable {
        case claude
        case cursor
    }

    /// What `--agent cursor` prints for Cursor's `preToolUse` `payload`, or `nil` for nothing: the payload read as the Claude Code one ``PreToolUseHook`` judges (Cursor's `Shell` as `Bash`), and its answer written in Cursor's schema.
    ///
    /// Nothing is printed for a payload that is not a `preToolUse` of a tool input Fieldwork reads, or for an answer Cursor's schema has no room for. SimWalk's hook acts on shell calls only, so no MCP tool name maps in either direction.
    static func cursorAnswer(_ payload: Data, attribution: CallAttribution, nudges: NudgeLedger) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let claude = CursorPreToolUse.claudePayload(from: object, mcpToolName: { _, _ in nil }),
              let translated = try? JSONSerialization.data(withJSONObject: claude),
              let output = PreToolUseHook.handle(translated, attribution: attribution, nudges: nudges)
        else {
            return nil
        }
        return CursorPreToolUse.response(to: output, toolName: claude["tool_name"] as? String) { _ in false }
    }
}
