//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// `simwalk hook pre-tool-use --agent cursor` judges Cursor's `preToolUse` payload as the Claude Code payload the hook already judges, and writes a refusal in Cursor's schema (SimWalk J12).
struct CursorPreToolUseHookTests {
    /// A call the hook has no business with lets the shell run: no bytes at all.
    @Test
    func ahundredCallsThatAreNotTheNudgesPrintNothing() throws {
        let repo = try Repo()
        let commands = ["ls", "git status", "swift build", "xcodebuild -list", "echo hello", "cat Package.swift", "xcrun simctl boot booted", "axe describe-ui", "pwd"]

        let outputs = (0 ..< 100).map { repo.cursorHook("\(commands[$0 % commands.count]) \($0)", session: "c\($0)") }

        #expect(outputs.count == 100)
        #expect(outputs.allSatisfy { $0 == nil })
    }

    /// The refusal reaches Cursor as its own denial, the reason in the message the model reads.
    @Test
    func ascreenshotByHandIsRefusedInCursorsSchema() throws {
        let repo = try Repo()

        let output = try #require(repo.cursorHook("xcrun simctl io booted screenshot x.png"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let reason = try #require(object["user_message"] as? String)

        #expect(Set(object.keys) == ["permission", "user_message", "agent_message"])
        #expect(object["permission"] as? String == "deny")
        #expect(object["agent_message"] as? String == reason)
        #expect(reason.contains("simwalk walk Docs/Walkbooks/x.json"))
        #expect(!output.contains("hookSpecificOutput"))
    }

    /// `--agent cursor` reaches Cursor's handler through the command's own dispatch, and `--agent claude` does not.
    @Test
    func theAgentOptionPicksTheHandlerTheCommandRuns() throws {
        let repo = try Repo()
        let cursor = try PreToolUseCommand.parse(["--agent", "cursor"])
        let claude = try PreToolUseCommand.parse([])

        let cursorOutput = try #require(repo.dispatch(cursor.agent, session: "conversation-1"))
        let claudeOutput = repo.dispatch(claude.agent, session: "conversation-1")

        #expect(cursorOutput.contains(#""permission":"deny""#), "\(cursorOutput)")
        #expect(!cursorOutput.contains("hookSpecificOutput"))
        #expect(claudeOutput == nil, "a Cursor payload is not a Claude Code one: \(String(describing: claudeOutput))")
    }

    /// Without `--agent` the same call is answered as it always was, in Claude Code's schema.
    @Test
    func theDefaultPathStillAnswersInClaudeCodesSchema() throws {
        let repo = try Repo()
        let claude: [String: Any] = ["session_id": "conversation-1", "tool_name": "Bash", "tool_input": ["command": "xcrun simctl io booted screenshot x.png"], "cwd": repo.root.path]

        let output = try #require(repo.handle(JSONSerialization.data(withJSONObject: claude)))

        #expect(output.contains(#""permissionDecision":"deny""#))
        #expect(output.contains("hookSpecificOutput"))
        #expect(!output.contains("user_message"))
    }
}

private extension CursorPreToolUseHookTests {
    /// A git working tree in scratch with a two-screen walkbook, and a nudge ledger of its own.
    struct Repo {
        let scratch: TemporaryDirectory

        init() throws {
            scratch = try TemporaryDirectory()
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
            let folder = root.appendingPathComponent("Docs/Walkbooks", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(Self.walkbook.utf8).write(to: folder.appendingPathComponent("x.json"))
            // A context's first hand-driving call is let through, so the one under test is its second.
            _ = cursorHook("xcrun simctl io booted screenshot first-call.png")
        }

        var root: URL {
            scratch.url.appendingPathComponent("repo", isDirectory: true)
        }

        /// What `--agent cursor` prints for `command`, as a Cursor `Shell` call in a conversation, from the repository's root.
        func cursorHook(_ command: String, session: String = "conversation-1") -> String? {
            let payload: [String: Any] = [
                "hook_event_name": "preToolUse",
                "tool_name": "Shell",
                "tool_input": ["command": command],
                "conversation_id": session,
                "generation_id": "generation-1",
                "workspace_roots": [root.path],
                "cwd": "",
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return PreToolUseCommand.cursorAnswer(data, attribution: attribution, nudges: nudges)
        }

        /// What the command's dispatch prints for `agent` given a Cursor payload for the second hand-driven screenshot.
        func dispatch(_ agent: PreToolUseCommand.Agent, session: String) -> String? {
            let payload: [String: Any] = [
                "hook_event_name": "preToolUse",
                "tool_name": "Shell",
                "tool_input": ["command": "xcrun simctl io booted screenshot x.png"],
                "conversation_id": session,
                "generation_id": "generation-1",
                "workspace_roots": [root.path],
                "cwd": "",
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return PreToolUseCommand.answer(for: agent, data, attribution: attribution, nudges: nudges)
        }

        /// What the default path prints for a Claude Code `payload`.
        func handle(_ payload: Data) -> String? {
            PreToolUseHook.handle(payload, attribution: attribution, nudges: nudges)
        }

        private var attribution: CallAttribution {
            CallAttribution(directory: scratch.url.appendingPathComponent("callers"))
        }

        private var nudges: NudgeLedger {
            NudgeLedger(directory: scratch.url.appendingPathComponent("nudges"))
        }

        static var walkbook: String {
            """
            {"name": "x", "appBundleID": "com.example.app", "screens": [
              {"id": "home", "route": [{"tab": {"label": "Home"}}], "states": [{"theme": "light"}, {"theme": "dark"}]},
              {"id": "settings", "route": [{"tab": {"label": "Settings"}}], "states": [{"theme": "light"}]}
            ]}
            """
        }
    }
}
