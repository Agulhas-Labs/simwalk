//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The `PreToolUse` hook's slips (SimWalk#14): one for each call of this tool a shell command makes, in the words the process will be handed, and none for anything else.
struct PreToolUseHookTests {
    /// The words stop where the process's `argv` does — at the end of the command and at a redirection — and a second invocation in the same command gets a slip of its own.
    @Test
    func theinvocationsAreTheWordsTheProcessWillBeHanded() {
        let command = "cd app && simwalk walk 'Docs/My Book.json' --only a,b 2>&1 | tail -5; ~/.local/bin/simwalk validate b.json > out.txt"

        let invocations = TranscriptScan.invocations(in: command)

        #expect(invocations == [["walk", "Docs/My Book.json", "--only", "a,b"], ["validate", "b.json"]])
    }

    /// A slip is claimed by the call of its shape, once, and preferably by a call from the directory the hook saw.
    @Test
    func aslipIsClaimedOnceAndThisDirectorysFirst() throws {
        let scratch = try TemporaryDirectory()
        // Claude Code's Bash environment, stated rather than inherited: a claim is made only under it, and this
        // test must pass from a plain terminal or the pre-push hook too.
        let attribution = CallAttribution(directory: scratch.url.appendingPathComponent("callers"), environment: ["CLAUDECODE": "1"])
        let here = scratch.url.path
        Self.handle(attribution, session: "elsewhere", command: "simwalk walk a.json", cwd: "/somewhere/else")
        Self.handle(attribution, session: "mine", command: "simwalk walk a.json", cwd: here)

        let first = attribution.take(arguments: ["walk", "a.json"], workingDirectory: here)
        let second = attribution.take(arguments: ["walk", "a.json"], workingDirectory: here)
        let third = attribution.take(arguments: ["walk", "a.json"], workingDirectory: here)

        #expect(first == "mine")
        #expect(second == "elsewhere")
        #expect(third == nil)
    }

    /// Anything that is not a call of this tool — another command, another tool, a payload that is not one — leaves nothing behind.
    @Test(arguments: [
        #"{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls ~/.local/bin/simwalk"}}"#,
        #"{"session_id":"s1","tool_name":"Read","tool_input":{"file_path":"simwalk walk a.json"}}"#,
        #"{"session_id":"../s1","tool_name":"Bash","tool_input":{"command":"simwalk walk a.json"}}"#,
        "simwalk walk a.json",
    ])
    func anythingElseWritesNoSlip(_ payload: String) throws {
        let scratch = try TemporaryDirectory()
        let callers = scratch.url.appendingPathComponent("callers")

        PreToolUseHook.handle(Data(payload.utf8), attribution: CallAttribution(directory: callers), nudges: NudgeLedger(directory: scratch.url.appendingPathComponent("nudges")))
        let written = (try? FileManager.default.contentsOfDirectory(atPath: callers.path)) ?? []

        #expect(written.isEmpty)
    }

    /// Only a process running under Claude Code can claim a slip — `PreToolUse` fires before the permission prompt, so a call denied there and run by hand outside Claude Code must not steal the slip.
    @Test
    func aslipIsOnlyClaimedUnderClaudeCode() throws {
        let scratch = try TemporaryDirectory()
        let here = scratch.url.path
        let outside = CallAttribution(directory: scratch.url.appendingPathComponent("callers"), environment: [:])
        Self.handle(outside, session: "mine", command: "simwalk walk a.json", cwd: here)

        #expect(outside.take(arguments: ["walk", "a.json"], workingDirectory: here) == nil)

        let underClaude = CallAttribution(directory: scratch.url.appendingPathComponent("callers"), environment: ["CLAUDECODE": "1"])

        #expect(underClaude.take(arguments: ["walk", "a.json"], workingDirectory: here) == "mine")
    }

    /// A slip past the claim window is never claimed.
    @Test
    func aslipPastTheWindowIsNotClaimed() throws {
        let scratch = try TemporaryDirectory()
        let directory = scratch.url.appendingPathComponent("callers")
        let then = Date()
        Self.handle(CallAttribution(directory: directory, now: { then }), session: "s1", command: "simwalk walk a.json", cwd: nil)

        let later = CallAttribution(directory: directory, now: { then.addingTimeInterval(CallAttribution.claimWindow + 1) }, environment: ["CLAUDECODE": "1"])

        #expect(later.take(arguments: ["walk", "a.json"], workingDirectory: scratch.url.path) == nil)
    }

    private static func handle(_ attribution: CallAttribution, session: String, command: String, cwd: String?) {
        var payload: [String: Any] = ["session_id": session, "tool_name": "Bash", "tool_input": ["command": command]]
        payload["cwd"] = cwd
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        PreToolUseHook.handle(data, attribution: attribution, nudges: NudgeLedger(directory: attribution.directory.deletingLastPathComponent().appendingPathComponent("nudges")))
    }
}
