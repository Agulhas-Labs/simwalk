//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The wire contract: what a client gets back for each method, that a refusal is an answer rather than a protocol fault, and that stdout carries nothing but JSON-RPC.
struct MCPServerTests {
    @Test
    func initializeNamesTheServerAndEchoesTheProtocolVersion() async throws {
        let responses = try await MCPExchange.send([
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26"]],
        ])

        let result = try #require(responses.first?["result"] as? [String: Any])
        let info = try #require(result["serverInfo"] as? [String: Any])

        #expect(responses.count == 1)
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        #expect(info["name"] as? String == "simwalk")
        #expect(info["version"] as? String == SimWalkVersion.current)
        #expect(result["capabilities"] is [String: Any])
    }

    /// A notification has no id, and the protocol forbids answering one — so the loop reads it, does nothing, and goes on serving.
    @Test
    func aNotificationDrawsNoResponseAndDoesNotEndTheSession() async throws {
        let responses = try await MCPExchange.send([
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 7, "method": "ping"],
        ])

        #expect(responses.count == 1)
        #expect(responses.first?["id"] as? Int == 7)
    }

    @Test
    func toolsListNamesTheSevenToolsAndTheArgumentsEachRequires() async throws {
        let responses = try await MCPExchange.send([
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["clientInfo": ["name": "claude-code"]]],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
        ])

        let result = try #require(responses.last?["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }

        #expect(names == ["walk", "validate", "inspect", "audit", "diff", "oracle", "session", "mirror"])
        #expect(names == SimWalkTool.allCases.filter { $0 != .walkStatus }.map(\.rawValue))
        for tool in tools {
            let schema = try #require(tool["inputSchema"] as? [String: Any])
            let properties = try #require(schema["properties"] as? [String: Any])
            let required = try #require(schema["required"] as? [String])
            #expect(!(tool["description"] as? String ?? "").isEmpty)
            #expect(required.allSatisfy { properties[$0] != nil })
        }
    }

    /// The catalog is the text an agent actually reads, so it says what a screen-scoped `inspect` answers: `match` searches values as well as labels, and the text is what lies inside the screenshot's frame — never "visible", which the answer does not check (SimWalk#20 round 4, finding 6).
    @Test
    func inspectsDescriptionSaysWhatAStepAndAMatchActuallyAnswer() async throws {
        let responses = try await MCPExchange.send([["jsonrpc": "2.0", "id": 2, "method": "tools/list"]])

        let tools = try #require((responses.first?["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let inspect = try #require(tools.first { $0["name"] as? String == "inspect" })
        let description = try #require(inspect["description"] as? String)
        let properties = try #require((inspect["inputSchema"] as? [String: Any])?["properties"] as? [String: [String: Any]])
        let match = try #require(properties["match"]?["description"] as? String)

        #expect(match.contains("label or value"))
        #expect(!description.contains("visible"))
        #expect(description.contains("not unobscured"))
        #expect(description.contains("localised"))
    }

    @Test
    func anAnsweredCallComesBackAsTheTextTheCLIWouldHavePrinted() async throws {
        let answer = Answer(header: "walk: 'x'", verdict: .qualified(["1 screen unreachable"], detail: "0 of 1 screens captured"))

        let responses = try await MCPExchange.send([
            MCPExchange.call(id: 3, tool: "validate", arguments: ["walkbook": "book.json"]),
        ], answering: { _, _, _, _ in answer })

        let response = try #require(responses.first)

        #expect(MCPExchange.text(of: response) == answer.text)
        #expect(!MCPExchange.isError(response))
    }

    /// A refusal is a tool result the model reads, not a JSON-RPC error the client swallows — and it is written in the same three words the CLI writes to stderr.
    @Test
    func aRefusalComesBackAsAnErroredToolResultInTheContractsWords() async throws {
        let responses = try await MCPExchange.send([
            MCPExchange.call(id: 4, tool: "walk", arguments: ["walkbook": "book.json"]),
        ])

        let response = try #require(responses.first)
        let text = try #require(MCPExchange.text(of: response))

        #expect(MCPExchange.isError(response))
        #expect(text.hasPrefix("refused — "))
        #expect(text.contains("output"))
        #expect(response["error"] == nil)
    }

    /// The three ways a line is not a request send a client somewhere different, so they are three codes: bad bytes, a well-formed non-request, and a request for something not served.
    @Test
    func ajsonValueThatIsNotARequestIsAnInvalidRequestRatherThanAParseError() async throws {
        let input = Pipe()
        let output = Pipe()
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: { _ in },
            usage: nil,
            session: nil,
            answering: { _, _, _, _ in MCPExchange.answer }
        )
        try input.fileHandleForWriting.write(contentsOf: Data("[1, 2, 3]\n".utf8))
        try input.fileHandleForWriting.close()
        await server.run()
        try output.fileHandleForWriting.close()

        let written = try output.fileHandleForReading.readToEnd() ?? Data()
        let response = try #require(try MCPExchange.decode(written).first)

        #expect((response["error"] as? [String: Any])?["code"] as? Int == -32600)
        #expect(response["id"] is NSNull)
    }

    /// A message with no method is not a notification either — a notification is a request without an *id* — so it is answered rather than ignored.
    @Test
    func amessageWithNoMethodIsAnInvalidRequest() async throws {
        let responses = try await MCPExchange.send([["jsonrpc": "2.0", "id": 8]])

        let error = try #require(responses.first?["error"] as? [String: Any])

        #expect(responses.count == 1)
        #expect(error["code"] as? Int == -32600)
        #expect(error["message"] as? String == "invalid request: no method")
    }

    /// Stdout carries JSON-RPC and nothing else, and one response per request that asked for one: `send` throws on a line that is not protocol JSON, so this counts what came back.
    @Test
    func stdoutCarriesOneProtocolLinePerAnsweredRequestAndNothingElse() async throws {
        let responses = try await MCPExchange.send([
            ["jsonrpc": "2.0", "id": 1, "method": "initialize"],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            MCPExchange.call(id: 3, tool: "validate", arguments: ["walkbook": "book.json"]),
            MCPExchange.call(id: 4, tool: "walk", arguments: [:]),
            ["jsonrpc": "2.0", "method": "notifications/cancelled"],
        ])

        #expect(responses.count == 4)
        #expect(responses.compactMap { $0["id"] as? Int } == [1, 2, 3, 4])
        #expect(responses.allSatisfy { $0["jsonrpc"] as? String == "2.0" })
    }

    /// A call cancelled while it runs goes unanswered even when its tool goes on to return an answer, and the server goes on answering (SimWalk#83).
    ///
    /// The cancel is sent only once the tool has started — a cancel read ahead of its call reaches nothing — and the tool returns only once it has heard it, so the answer always arrives after the cancel: no timing involved.
    @Test(.timeLimit(.minutes(1)))
    func aCallCancelledWhileItRunsGoesUnansweredThoughItsToolReturns() async throws {
        let input = Pipe()
        let output = Pipe()
        let started = AsyncStream.makeStream(of: Void.self)
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: { _ in },
            usage: nil,
            session: nil,
            answering: { _, _, cancellation, _ in
                let heard = DispatchSemaphore(value: 0)
                cancellation.onCancel { heard.signal() }
                started.continuation.yield()
                _ = heard.wait(timeout: .now() + 20)
                return MCPExchange.answer
            }
        )
        let serving = Task { await server.run() }

        try Self.send(MCPExchange.call(id: 7, tool: "validate", arguments: ["walkbook": "book.json"]), to: input)
        for await _ in started.stream {
            break
        }
        try Self.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 7, "reason": "test"]], to: input)
        try Self.send(["jsonrpc": "2.0", "id": 8, "method": "ping"], to: input)
        try input.fileHandleForWriting.close()
        await serving.value
        try output.fileHandleForWriting.close()
        let responses = try MCPExchange.decode(output.fileHandleForReading.readToEnd() ?? Data())

        #expect(responses.map { $0["id"] as? Int } == [8])
    }

    /// A call cancelled while still queued is skipped: no answer, and its tool never runs (SimWalk#85).
    ///
    /// The cancel is written ahead of the call it names, which is what the reader hears for a call queued behind a walk.
    @Test(.timeLimit(.minutes(1)))
    func aCallCancelledBeforeItStartsIsNeitherRunNorAnswered() async throws {
        let input = Pipe()
        let output = Pipe()
        let ran = Ran()
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: { _ in },
            usage: nil,
            session: nil,
            answering: { _, _, _, _ in
                ran.mark()
                return MCPExchange.answer
            }
        )
        try Self.send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 7, "reason": "test"]], to: input)
        try Self.send(MCPExchange.call(id: 7, tool: "validate", arguments: ["walkbook": "book.json"]), to: input)
        try Self.send(["jsonrpc": "2.0", "id": 8, "method": "ping"], to: input)
        try input.fileHandleForWriting.close()
        await server.run()
        try output.fileHandleForWriting.close()
        let responses = try MCPExchange.decode(output.fileHandleForReading.readToEnd() ?? Data())

        #expect(responses.map { $0["id"] as? Int } == [8])
        #expect(!ran.value)
    }

    /// A server that has lost its output has nothing left to answer with, and must not sit in `read(2)` waiting for a client that has gone.
    @Test(.timeLimit(.minutes(1)))
    func aclosedOutputEndsTheSessionWithoutWaitingForMoreInput() async throws {
        let input = Pipe()
        let output = Pipe()
        // The client's end of stdout, closed before anything is written — so the first response fails.
        try output.fileHandleForReading.close()
        let diagnostics = LogRecorder()
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: diagnostics.record,
            usage: nil,
            session: nil,
            answering: { _, _, _, _ in MCPExchange.answer }
        )
        var request = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"])
        request.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: request)

        // The write end of stdin is deliberately left open: reaching EOF is exactly what must not be needed
        // to get out of the loop. A hang here is the regression, which the time limit turns into a failure.
        await server.run()

        #expect(diagnostics.lines.contains { $0.contains("stdout closed") })
    }

    @Test
    func anUnknownMethodIsAJSONRPCError() async throws {
        let responses = try await MCPExchange.send([["jsonrpc": "2.0", "id": 5, "method": "nonesuch"]])

        let error = try #require(responses.first?["error"] as? [String: Any])

        #expect(error["code"] as? Int == -32601)
        #expect(error["message"] as? String == "method not found: nonesuch")
    }

    @Test
    func alineThatIsNotJSONIsAParseErrorRatherThanASilentDrop() async throws {
        let input = Pipe()
        let output = Pipe()
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: { _ in },
            usage: nil,
            session: nil,
            answering: { _, _, _, _ in MCPExchange.answer }
        )
        try input.fileHandleForWriting.write(contentsOf: Data("not json\n".utf8))
        try input.fileHandleForWriting.close()
        await server.run()
        try output.fileHandleForWriting.close()

        let written = try #require(try output.fileHandleForReading.readToEnd())
        let response = try #require(try JSONSerialization.jsonObject(with: written) as? [String: Any])

        #expect((response["error"] as? [String: Any])?["code"] as? Int == -32700)
    }

    /// Every call is recorded under the CLI's own name for the verb, so one report covers both faces — and under the session that made it, which is the only thing that lets a status line price its own calls and nobody else's.
    @Test
    func everyCallIsLoggedUnderTheCLIsVerbAndTheSessionThatMadeIt() async throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        _ = try await MCPExchange.send([
            MCPExchange.call(id: 1, tool: "inspect", arguments: ["bundle": "x.simwalk"]),
            MCPExchange.call(id: 2, tool: "audit", arguments: ["bundle": "x.simwalk"]),
            MCPExchange.call(id: 3, tool: "validate", arguments: [:]),
            // A screen-scoped inspect is logged as the verb it runs — both when its `step` is refused
            // before it resolves (named before the invocation exists) and when it resolves (named by it).
            MCPExchange.call(id: 4, tool: "inspect", arguments: ["bundle": "x.simwalk", "step": -1]),
            MCPExchange.call(id: 5, tool: "inspect", arguments: ["bundle": "x.simwalk", "step": 1]),
        ], usage: log, session: "session-1")

        let entries = try Self.entries(in: directory)

        #expect(entries.map(\.tool) == ["bundle inspect", "bundle audit", "validate", "bundle screen", "bundle screen"])
        #expect(entries.allSatisfy { $0.session == "session-1" })
        #expect(entries.map(\.succeeded) == [true, true, false, false, true])
        #expect(entries.dropFirst(2).first?.error?.contains("walkbook") == true)
        #expect(entries.dropFirst(3).first?.error?.contains("'step' of -1") == true)
        #expect(entries.prefix(2).allSatisfy { $0.target == "x.simwalk" })
        // MCPToolInvocation refusing a missing argument is a bad argument, the same as any other.
        #expect(entries.dropFirst(2).first?.kind == .inputRefused)
        #expect(entries.last?.target == "x.simwalk")
    }

    /// A `walk` failure this server does not itself classify is still this tool's own machinery, never a caller's mistake, by the time `answering` runs — `MCPToolInvocation` has already checked the argument.
    ///
    /// It falls back to `runner-failed`, the same default the CLI's own `TimedCall` uses for `walk`, rather than reaching `simwalk usage` as `unclassified`.
    @Test
    func awalkFailureWithNoMappedKindIsRecordedAsRunnerFailed() async throws {
        struct Unmapped: Error, CustomStringConvertible {
            var description: String {
                "something this codebase has never classified"
            }
        }
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        _ = try await MCPExchange.send([
            MCPExchange.call(id: 1, tool: "walk", arguments: ["walkbook": "book.json", "output": "x.simwalk"]),
        ], usage: log, session: "session-1", answering: { _, _, _, _ in throw Unmapped() })

        let entry = try #require(try Self.entries(in: directory).first)

        #expect(entry.kind == .runnerFailed)
    }

    /// `validate`, `inspect` and `audit` run nothing but this tool's own code over an argument `MCPToolInvocation` already checked, so an error nothing classified is `tool-error` — never recorded with no kind at all, which `simwalk usage` would read as `unclassified`.
    @Test
    func averbOtherThanWalkRecordsAnUnmappedFailureAsToolError() async throws {
        struct Unmapped: Error {}
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        _ = try await MCPExchange.send([
            MCPExchange.call(id: 1, tool: "validate", arguments: ["walkbook": "book.json"]),
            MCPExchange.call(id: 2, tool: "inspect", arguments: ["bundle": "x.simwalk"]),
            MCPExchange.call(id: 3, tool: "audit", arguments: ["bundle": "x.simwalk"]),
        ], usage: log, session: "session-1", answering: { _, _, _, _ in throw Unmapped() })

        let entries = try Self.entries(in: directory)

        #expect(entries.map(\.tool) == ["validate", "bundle inspect", "bundle audit"])
        #expect(entries.map(\.kind) == [.toolError, .toolError, .toolError])
    }

    /// The default is a fallback for an error with no kind of its own, never a floor over one that has: a walk refused for the caller's own walkbook stays `input-refused`, where the default would have filed it as the runner's failure — and a verb's `tool-error` default cannot turn a runner's unreadable tree into its own bug either.
    @Test
    func aclassifiedFailureKeepsItsOwnKindOverTheVerbsDefault() async throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })

        _ = try await MCPExchange.send([
            MCPExchange.call(id: 1, tool: "walk", arguments: ["walkbook": "book.json", "output": "x.simwalk"]),
            MCPExchange.call(id: 2, tool: "audit", arguments: ["bundle": "x.simwalk"]),
        ], usage: log, session: "session-1", answering: { tool, _, _, _ in
            switch tool {
            case .walk: throw WalkbookLoadError.unreadable(source: "book.json", reason: "no such file")
            default: throw CaptureBundleError.artefactUnreadable(path: "x.simwalk/tree.json", reason: "torn")
            }
        })

        // A client sending no `initialize` is bounded, and a bounded walk logs when it ends, so the two lines may land in either order.
        let entries = try Self.entries(in: directory)

        #expect(Dictionary(uniqueKeysWithValues: entries.map { ($0.tool, $0.kind) }) == ["walk": .inputRefused, "bundle audit": .runnerFailed])
    }

    /// A saving measured by the answer is what the log records, so the status line and `usage` price the same call the same way.
    @Test
    func ameasuredAnswerRecordsWhatItStoodInForAgainstTheSession() async throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let measured = Answer(
            header: "walk: 'x'",
            verdict: .unqualified("1 of 1 screens captured"),
            weighing: ContextSaving(screenshotTokens: [4070], treeBytes: 40000, servedBytes: 0)
        )

        _ = try await MCPExchange.send([
            MCPExchange.call(id: 1, tool: "walk", arguments: ["walkbook": "book.json", "output": "x.simwalk"]),
        ], usage: log, session: "session-1", answering: { _, _, _, _ in measured })

        let entry = try #require(try Self.entries(in: directory).first)

        #expect(entry.tokensSaved == measured.saving?.savedTokens)
        #expect(entry.session == "session-1")
    }

    private static func entries(in directory: TemporaryDirectory) throws -> [UsageLog.Entry] {
        let text = try String(contentsOf: directory.url.appendingPathComponent("usage.jsonl"), encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try JSONDecoder().decode(UsageLog.Entry.self, from: Data(line.utf8))
        }
    }

    /// Writes `message` to `input` as one protocol line.
    private static func send(_ message: [String: Any], to input: Pipe) throws {
        var line = try JSONSerialization.data(withJSONObject: message)
        line.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: line)
    }
}

private extension MCPServerTests {
    /// Whether a stand-in tool ran, set from the server's actor and read after it ends.
    final class Ran: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false

        var value: Bool {
            lock.withLock { flag }
        }

        func mark() {
            lock.withLock { flag = true }
        }
    }
}
