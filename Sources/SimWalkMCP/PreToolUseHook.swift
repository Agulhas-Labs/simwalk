//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// What `simwalk hook pre-tool-use` does with the payload Claude Code sends before a tool runs.
///
/// **It never stands in the way of a call twice.** It exits 0 whatever it read, does nothing at all with a payload it does not understand, and prints nothing unless it is refusing a call whose identical re-run it will let through — a hook that fails loudly on every `ls` is a hook that gets uninstalled, and one that blocks for good takes the agent's shell with it. A payload that is not this tool's business costs one scan of its bytes for a handful of names before any JSON is parsed, since the hook fires on every shell call a session makes.
///
/// **One parsed call, then each behaviour in turn**, each a function over the same ``Call``:
/// - ``attribute(_:to:)``, the slip that tags a command-line call's log line with its session (SimWalk#14). It writes nothing to stdout.
/// - ``HandDrivingNudge``, the refusal of a simulator driven by hand in a repository whose walkbook already drives it (SimWalk#12). What it answers is the hook's output.
///
/// Not logged to the usage log: it runs on every shell call, and a line per `ls` would bury the calls the log exists to count.
public struct PreToolUseHook {
    /// Runs every behaviour over one hook payload, answering what the hook prints — `nil` for nothing, which lets the call through.
    @discardableResult
    public static func handle(_ payload: Data, attribution: CallAttribution, nudges: NudgeLedger) -> String? {
        guard needles.contains(where: { payload.range(of: Data($0.utf8)) != nil }),
              let call = try? JSONDecoder().decode(Call.self, from: payload)
        else {
            return nil
        }
        attribute(call, to: attribution)
        return HandDrivingNudge.respond(to: call, payload: payload, ledger: nudges)
    }

    /// Leaves a slip for every invocation of this tool in a shell call, so the process it starts can claim the session (SimWalk#14).
    static func attribute(_ call: Call, to attribution: CallAttribution) {
        guard call.toolName == "Bash", let command = call.toolInput?.command else { return }
        for arguments in TranscriptScan.invocations(in: command) {
            attribution.note(session: call.sessionID, arguments: arguments, workingDirectory: call.workingDirectory)
        }
    }
}

private extension PreToolUseHook {
    /// A name one of the behaviours acts on — this tool's for the slip, a simulator driver's for the nudge.
    ///
    /// A payload holding none is let through unparsed.
    static var needles: [String] {
        [SimWalkPaths.binaryName, "simctl", "axe", "XcodeBuildMCP"]
    }
}

public extension PreToolUseHook {
    /// The fields of Claude Code's `PreToolUse` payload any behaviour here reads — the rest is ignored, so a payload that grows fields is still read.
    struct Call: Decodable, Sendable {
        /// The session the call belongs to — a subagent's call carries its parent's.
        let sessionID: String

        /// The subagent making the call, where one is.
        let agentID: String?

        /// The tool about to run — `Bash` for a shell call.
        let toolName: String

        /// The tool's input, where it has one this reads.
        let toolInput: ToolInput?

        /// The directory the session's shell stands in when the call starts.
        let workingDirectory: String?
    }

    /// The part of a tool's input a behaviour reads: a shell call's command line.
    struct ToolInput: Decodable, Sendable {
        let command: String?
    }
}

extension PreToolUseHook.Call {
    /// Claude Code's own spellings of the payload's keys.
    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentID = "agent_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case workingDirectory = "cwd"
    }
}
