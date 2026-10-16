//
// Copyright © Agulhas Labs
//

import Foundation

/// Writes the shape of a Claude Code transcript a status line reads: one JSON object per line, tool calls and their results inside an assistant message's content.
struct TranscriptFixture {
    /// One assistant line carrying one `tool_use` block.
    static func toolUse(_ name: String, id: String = UUID().uuidString, _ input: [String: Any]) throws -> String {
        try line(["type": "tool_use", "id": id, "name": name, "input": input])
    }

    /// One assistant line carrying the result of a call, which is the only thing that can say the call never ran.
    static func toolResult(id: String, isError: Bool = false, text: String = "done") throws -> String {
        try line([
            "type": "tool_result",
            "tool_use_id": id,
            "is_error": isError,
            "content": [["type": "text", "text": text]],
        ])
    }

    /// Appends lines to a transcript, creating it if it is not there — transcripts are append-only, which is what the incremental scan leans on.
    static func append(_ lines: [String], to url: URL) throws {
        let text = lines.map { $0 + "\n" }.joined()
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try Data(text.utf8).write(to: url)
            return
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// How Claude Code words a call the user did not allow — not this tool's refusal, and telling the two apart is the whole point.
    static var denial: String {
        "The user doesn't want to take this action right now. Stop what you are doing."
    }

    private static func line(_ block: [String: Any]) throws -> String {
        let object: [String: Any] = [
            "type": "assistant",
            "timestamp": "2026-09-05T08:00:00.000Z",
            "message": ["role": "assistant", "content": [block]],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
