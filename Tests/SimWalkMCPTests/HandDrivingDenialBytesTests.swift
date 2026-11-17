//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The refusal the hand-driving nudge prints is Claude Code's `PreToolUse` denial byte for byte: sorted keys, slashes unescaped, nothing else.
struct HandDrivingDenialBytesTests {
    @Test
    func theNudgePrintsExactlyTheDenialJSON() throws {
        let scratch = try TemporaryDirectory()
        let root = scratch.url.appendingPathComponent("repo", isDirectory: true)
        let folder = root.appendingPathComponent("Docs/Walkbooks", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let walkbook = #"{"name": "x", "appBundleID": "com.example.app", "screens": [{"id": "home", "route": [{"tab": {"label": "Home"}}], "states": [{"theme": "light"}]}]}"#
        try Data(walkbook.utf8).write(to: folder.appendingPathComponent("x.json"))

        func hook(_ command: String) throws -> String? {
            let payload: [String: Any] = ["session_id": "s1", "tool_name": "Bash", "tool_input": ["command": command], "cwd": root.path]
            return try PreToolUseHook.handle(
                JSONSerialization.data(withJSONObject: payload),
                attribution: CallAttribution(directory: scratch.url.appendingPathComponent("callers")),
                nudges: NudgeLedger(directory: scratch.url.appendingPathComponent("nudges"))
            )
        }
        _ = try hook("xcrun simctl io booted screenshot first.png")
        let output = try #require(try hook("xcrun simctl io booted screenshot a.png"))

        let parsed = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        let specific = try #require(parsed["hookSpecificOutput"] as? [String: Any])
        let reason = try #require(specific["permissionDecisionReason"] as? String)
        #expect(reason.contains("simwalk walk Docs/Walkbooks/x.json"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let quoted = try String(decoding: encoder.encode(reason), as: UTF8.self)
        let expected = #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"# + quoted + "}}"
        #expect(output == expected)
    }
}
