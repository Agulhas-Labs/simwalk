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

    /// SimWalk#293: a variable the same command line set is spelled out in the slip, as the process's `argv` will hold it, in every way a line sets one; `;` and `&&` each start a command of their own.
    @Test(arguments: [
        "U=X; simwalk walk w.json --udid $U",
        "U=X && simwalk walk w.json --udid $U",
        "export U=X; simwalk walk w.json --udid ${U}",
        "U=\"X\"; simwalk walk w.json --udid $U",
        "A=1; U=X && simwalk walk w.json --udid $U",
    ])
    func avariableTheSameCommandSetIsSpelledOutInTheSlip(command: String) {
        #expect(TranscriptScan.invocations(in: command) == [["walk", "w.json", "--udid", "X"]])
    }

    /// A name the line never set, and one set on the call itself (which the shell expands first), stay as written: untagged rather than tagged wrongly.
    @Test
    func aVariableTheCommandDidNotSetStaysAsWritten() {
        #expect(TranscriptScan.invocations(in: "simwalk walk w.json --udid $V") == [["walk", "w.json", "--udid", "$V"]])
        #expect(TranscriptScan.invocations(in: "U=X simwalk walk w.json --udid $U") == [["walk", "w.json", "--udid", "$U"]])
        #expect(TranscriptScan.invocations(in: "U=X; echo hi; simwalk walk --udid $V") == [["walk", "--udid", "$V"]])
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

    /// The process under Claude Code tags itself from `CLAUDE_CODE_SESSION_ID`, with no slip, and a slip from another session does not outrank it (SimWalk#293).
    @Test
    func theEnvironmentsSessionIsTakenWithOrWithoutASlip() throws {
        let scratch = try TemporaryDirectory()
        let here = scratch.url.path
        let directory = scratch.url.appendingPathComponent("callers")
        let environment = ["CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "env-session"]

        #expect(CallAttribution(directory: directory, environment: environment).take(arguments: ["walk", "a.json"], workingDirectory: here) == "env-session")

        Self.handle(CallAttribution(directory: directory), session: "other", command: "simwalk walk a.json", cwd: here)
        let attribution = CallAttribution(directory: directory, environment: environment)

        #expect(attribution.take(arguments: ["walk", "a.json"], workingDirectory: here) == "env-session")
        #expect(CallAttribution(directory: directory, environment: ["CLAUDECODE": "1"]).take(arguments: ["walk", "a.json"], workingDirectory: here) == "other")
    }

    /// An invalid environment id falls back to the slip; outside Claude Code nothing is returned even with the id.
    @Test
    func anInvalidEnvironmentSessionFallsBackAndOutsideClaudeCodeIsNil() throws {
        let scratch = try TemporaryDirectory()
        let here = scratch.url.path
        let directory = scratch.url.appendingPathComponent("callers")
        Self.handle(CallAttribution(directory: directory), session: "other", command: "simwalk walk a.json", cwd: here)

        let outside = CallAttribution(directory: directory, environment: ["CLAUDE_CODE_SESSION_ID": "env-session"])

        #expect(outside.take(arguments: ["walk", "a.json"], workingDirectory: here) == nil)

        let invalid = CallAttribution(directory: directory, environment: ["CLAUDECODE": "1", "CLAUDE_CODE_SESSION_ID": "../bad"])

        #expect(invalid.take(arguments: ["walk", "a.json"], workingDirectory: here) == "other")
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
