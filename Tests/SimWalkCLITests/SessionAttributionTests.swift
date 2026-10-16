//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// SimWalk#14: a call made from an agent's shell is priced in that agent's session.
///
/// Every line carrying a saving came from the command line, which has no session of its own, so a status line pricing its session's calls priced nothing for a session that used the documented face. The `PreToolUse` hook now leaves a slip the process claims, and this holds the whole chain as the machine runs it: the built binary as the hook, fed Claude Code's payload on stdin, then the built binary as the call, then the status line's own reader over the log.
///
/// **Driven as two processes, deliberately** — the claim matches the process's real `argv` against the words the hook read off the command line, which no in-process call can stand in for. `bundle inspect` is the verb because it is the one that prices a saving without a simulator; `walk` claims through the same `TimedCall`. `CFFIXED_USER_HOME` and `SIMWALK_USAGE_LOG` keep both processes out of the real `~/.simwalk`.
struct SessionAttributionTests {
    @Test
    func ashellCallMadeInASessionIsPricedInThatSession() throws {
        let scratch = try TemporaryDirectory()
        let home = scratch.url.appendingPathComponent("home", isDirectory: true)
        let log = scratch.url.appendingPathComponent("moved/usage.jsonl")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // `CLAUDECODE` stated, not inherited: the claim is made only under Claude Code, and this must pass from a plain shell too.
        let environment = ["CFFIXED_USER_HOME": home.path, UsageLog.overrideVariable: log.path, "CLAUDECODE": "1"]
        let binary = try UsageLogOverrideTests.binary()
        let bundle = try CaptureBundleFixture.write(
            in: scratch,
            captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen())]
        )
        let session = "session-\(UUID().uuidString)"
        let payload: [String: Any] = [
            "session_id": session,
            "tool_name": "Bash",
            "tool_input": ["command": "simwalk bundle inspect '\(bundle.url.path)' 2>&1 | tail -20"],
            "cwd": scratch.url.path,
        ]
        let payloadFile = scratch.url.appendingPathComponent("payload.json")
        try JSONSerialization.data(withJSONObject: payload).write(to: payloadFile)

        let hook = try Shell().run("/bin/sh", ["-c", "\"$0\" hook pre-tool-use < \"$1\"", binary.path, payloadFile.path], environment: environment)
        let call = try Shell().run(binary.path, ["bundle", "inspect", bundle.url.path], environment: environment)
        let usage = SessionUsage.scanning(log, after: SessionUsage(), session: session)
        let again = try Shell().run(binary.path, ["bundle", "inspect", bundle.url.path], environment: environment)
        let entries = try UsageReport.entries(at: log).entries

        #expect(hook.status == 0)
        #expect(hook.standardOutput.isEmpty)
        #expect(call.status == 0)
        #expect(usage.tokensSaved > 0)
        // A slip is consumed by the call that claims it: the same command run again, with no hook before it, is not the session's.
        #expect(again.status == 0)
        #expect(entries.map(\.session) == [session, nil])
    }
}
