//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP

/// Drives the server over a pair of pipes and hands back the JSON it wrote.
///
/// The protocol is the contract, so it is exercised as bytes on a stream rather than by calling the handler: the framing, the notification that must draw no response, and the shutdown at EOF are all things only the loop itself can be asked about.
struct MCPExchange {
    /// Sends `requests` and returns every response line, in order.
    static func send(
        _ requests: [[String: Any]],
        usage: UsageLog? = nil,
        session: String? = nil,
        answering: @escaping SimWalkMCPServer.AnswerProvider = { _, _, _, _ in Self.answer },
        environment: [String: String] = [:],
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> [[String: Any]] {
        let lines = try requests.map { try JSONSerialization.data(withJSONObject: $0) }
        return try await send(lines: lines, usage: usage, session: session, answering: answering, environment: environment, log: log)
    }

    /// Sends request lines exactly as given (a recorded client line must reach the server as recorded) and returns every response line, in order.
    static func send(
        lines requests: [Data],
        usage: UsageLog? = nil,
        session: String? = nil,
        answering: @escaping SimWalkMCPServer.AnswerProvider = { _, _, _, _ in Self.answer },
        environment: [String: String] = [:],
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> [[String: Any]] {
        let input = Pipe()
        let output = Pipe()
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: log,
            usage: usage,
            session: session,
            answering: answering,
            environment: environment
        )
        for request in requests {
            var line = request
            line.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: line)
        }
        try input.fileHandleForWriting.close()
        await server.run()
        try output.fileHandleForWriting.close()

        let written = try output.fileHandleForReading.readToEnd() ?? Data()
        return try decode(written)
    }

    /// Every line the server wrote, decoded — and a *throw* for one that is not protocol JSON.
    ///
    /// The Brief's carved-in-stone rule is that stdout carries JSON-RPC and nothing else, and a filter that quietly skipped what it could not parse would let a stray `print` through every test in this suite while all of them stayed green. Refusing the line is what makes the rule checkable.
    static func decode(_ written: Data) throws -> [[String: Any]] {
        try written.split(separator: 0x0A, omittingEmptySubsequences: true).map { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw StrayOutput(line: String(bytes: line, encoding: .utf8) ?? "<not UTF-8>")
            }
            return object
        }
    }

    /// A `tools/call` request for one tool.
    static func call(id: Int, tool: String, arguments: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": tool, "arguments": arguments]]
    }

    /// The stand-in answer, for the tests that are about the protocol rather than about a verb.
    static var answer: Answer {
        Answer(header: "walk: 'x'", verdict: .unqualified("1 capture planned"))
    }

    /// The text of a tool result, or `nil` when the response is not one.
    static func text(of response: [String: Any]) -> String? {
        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String
    }

    /// Whether a tool result is marked as an error.
    static func isError(_ response: [String: Any]) -> Bool {
        (response["result"] as? [String: Any])?["isError"] as? Bool == true
    }
}

extension MCPExchange {
    /// A line on the server's stdout that is not a JSON-RPC message — the one thing that stream may never carry.
    struct StrayOutput: Error, CustomStringConvertible {
        let line: String

        var description: String {
            "the MCP server wrote a line to stdout that is not JSON-RPC: \(line)"
        }
    }
}
