//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// Which mode a client gets, the catalog it is shown, and the budget a bounded call waits.
struct MCPClientModeTests {
    private static var listRequest: [String: Any] {
        ["jsonrpc": "2.0", "id": 2, "method": "tools/list"]
    }

    private static var boundedWalkSentence: String {
        "A walk takes minutes, and a call answers within the budget with either the answer or a handle to poll with walk_status; the answer names"
    }

    private static func fixture(_ name: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        return try Data(contentsOf: url)
    }

    private static func initialize(_ fixtureName: String?) throws -> [Data] {
        try fixtureName.map { try [fixture($0).trimmedLine] } ?? []
    }

    private static func listedTools(initializeFixture: String?, environment: [String: String] = [:], sourceLocation: SourceLocation = #_sourceLocation) async throws -> [[String: Any]] {
        let responses = try await MCPExchange.send(
            lines: initialize(initializeFixture) + [JSONSerialization.data(withJSONObject: listRequest)],
            environment: environment
        )
        let result = try #require(responses.last?["result"] as? [String: Any], sourceLocation: sourceLocation)
        return try #require(result["tools"] as? [[String: Any]], sourceLocation: sourceLocation)
    }

    private static func call(_ tool: String, initializeFixture: String?, environment: [String: String] = [:], sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String: Any] {
        let responses = try await MCPExchange.send(
            lines: initialize(initializeFixture) + [JSONSerialization.data(withJSONObject: MCPExchange.call(id: 3, tool: tool, arguments: ["handle": "x@1-2"]))],
            environment: environment
        )
        return try #require(responses.last, sourceLocation: sourceLocation)
    }

    // MARK: Claude Code, a blocking client

    /// The recorded fixture is what a blocking client is sent: the list from before bounded mode, re-recorded when J13 cut its text.
    ///
    /// The comparison is of the parsed list re-serialised with sorted keys, so it pins the JSON, not the bytes the server wrote.
    @Test
    func claudeCodeToolsListIsTheSameJSONAsTheRecordedFixture() async throws {
        let tools = try await Self.listedTools(initializeFixture: "claude-code-2.1.302-initialize")
        let bytes = try JSONSerialization.data(withJSONObject: ["tools": tools], options: [.sortedKeys])

        #expect(try bytes == (Self.fixture("claude-code-tools-list")))
        #expect(tools.compactMap { $0["name"] as? String } == ["walk", "validate", "inspect", "audit", "diff", "oracle", "session", "mirror"])
    }

    /// The whole of a Claude Code session as the recorded client sends it: its `initialize`, the list, one `walk`, with nothing bounded reaching it.
    @Test
    func claudeCodeIsServedInitializeListAndOneBlockingWalkAnswer() async throws {
        let responses = try await MCPExchange.send(
            lines: Self.initialize("claude-code-2.1.302-initialize") + [
                JSONSerialization.data(withJSONObject: Self.listRequest),
                JSONSerialization.data(withJSONObject: MCPExchange.call(id: 3, tool: "walk", arguments: ["walkbook": "book.json", "output": "out.simwalk"])),
            ]
        )
        let list = try #require(responses.first { $0["id"] as? Int == 2 })
        let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let walk = try #require(responses.first { $0["id"] as? Int == 3 })

        #expect(try JSONSerialization.data(withJSONObject: ["tools": tools], options: [.sortedKeys]) == Self.fixture("claude-code-tools-list"))
        #expect(!tools.contains { $0["name"] as? String == "walk_status" })
        #expect(MCPExchange.text(of: walk) == MCPExchange.answer.text)
        #expect(!MCPExchange.isError(walk))
        #expect(responses.filter { $0["id"] as? Int == 3 }.count == 1)
    }

    private static var cursorInstructions: String {
        """
        SimWalk drives a running iOS app through a walkbook (*.walkbook.json) and writes a capture bundle: a screenshot and accessibility tree per screen, and a manifest of what happened. Prefer it to tapping through the app by hand.
        - After an app change, call walk with dryRun: true first. It checks every screen's route still resolves, in seconds, and captures nothing. validate checks a walkbook can run as written.
        - A full walk takes minutes. Here a walk call answers within a time budget: with the result, or with a handle. Pass the handle to walk_status until the result arrives. Start no second walk meanwhile.
        - The first line is the verdict. ok passes; "qualified — ..." is an answer with each qualification named, not a failure; "refused — ..." is an error saying what would make it answerable.
        - Read the answer and the bundle's manifest before any screenshot. For one screen's text, call inspect with step.
        - Don't reboot or drive the simulator by hand. A walk settles the device itself when it needs to.
        Full guide: Docs/Reference.md at github.com/Agulhas-Labs/simwalk.
        """
    }

    private static func initializeResult(_ fixtureName: String?, sourceLocation: SourceLocation = #_sourceLocation) async throws -> [String: Any] {
        let responses = try await MCPExchange.send(lines: initialize(fixtureName) + [JSONSerialization.data(withJSONObject: listRequest)])
        return try #require(responses.first?["result"] as? [String: Any], sourceLocation: sourceLocation)
    }

    @Test
    func claudeCodeInitializeResultHasNoInstructions() async throws {
        let result = try await Self.initializeResult("claude-code-2.1.302-initialize")

        #expect(result["instructions"] == nil)
        #expect(Set(result.keys) == ["protocolVersion", "capabilities", "serverInfo"])
    }

    @Test
    func cursorInitializeResultCarriesTheShortInstructions() async throws {
        let result = try await Self.initializeResult("cursor-1.0.0-initialize")
        let instructions = try #require(result["instructions"] as? String)

        #expect(instructions == Self.cursorInstructions)
        #expect(instructions.utf8.count <= 1200)
    }

    @Test
    func aClientWithNoClientInfoGetsTheInstructions() async throws {
        let result = try await MCPExchange.send([["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25"]]]).first?["result"] as? [String: Any]

        #expect(try #require(result)["instructions"] as? String == Self.cursorInstructions)
    }

    @Test
    func claudeCodeIsRefusedWalkStatusAsAnUnknownToolListingTheEight() async throws {
        let response = try await Self.call("walk_status", initializeFixture: "claude-code-2.1.302-initialize")
        let text = try #require(MCPExchange.text(of: response))

        #expect(MCPExchange.isError(response))
        #expect(text == "refused — unknown tool 'walk_status' — this server serves walk, validate, inspect, audit, diff, oracle, session, mirror")
    }

    // MARK: Bounded clients

    @Test(arguments: ["cursor-1.0.0-initialize", nil] as [String?])
    func aBoundedClientIsListedNineToolsWithTheNoteTexts(initializeFixture: String?) async throws {
        let tools = try await Self.listedTools(initializeFixture: initializeFixture)
        let names = tools.compactMap { $0["name"] as? String }
        #expect(names == SimWalkTool.allCases.map(\.rawValue))
        #expect(names.count == 9)

        let blocking = try await Self.listedTools(initializeFixture: "claude-code-2.1.302-initialize")
        let blockingWalk = try #require(blocking.first?["description"] as? String)
        let walk = try #require(tools.first?["description"] as? String)
        #expect(walk == blockingWalk.replacingOccurrences(of: "A walk takes minutes and nothing is served until it finishes; the answer names", with: Self.boundedWalkSentence))
        #expect(walk.contains(Self.boundedWalkSentence))
        #expect(Array(tools.dropFirst().prefix(7)).map { $0["name"] as? String } == Array(blocking.dropFirst()).map { $0["name"] as? String })

        let status = try #require(tools.last)
        #expect(status["description"] as? String == "Poll a walk that 'walk' answered with a handle: waits up to the budget, then returns the walk's answer if it has ended, else one running line with its progress.")
        let schema = try #require(status["inputSchema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let handle = try #require(properties["handle"] as? [String: Any])
        #expect(handle["type"] as? String == "string")
        #expect(handle["description"] as? String == "the handle that 'walk' returned on its running line")
        #expect(schema["required"] as? [String] == ["handle"])
        #expect(properties.count == 1)
    }

    @Test(arguments: ["cursor-1.0.0-initialize", nil] as [String?])
    func aBoundedClientIsRefusedAMalformedHandleAndOneThatIsNotAString(initializeFixture: String?) async throws {
        let directory = try TemporaryDirectory()
        let usage = UsageLog(directory: directory.url, now: { Date() })
        let calls = [["handle": "x/../y"], [:], ["handle": 7]].enumerated().map { MCPExchange.call(id: 3 + $0.offset, tool: "walk_status", arguments: $0.element) }
        let responses = try await MCPExchange.send(
            lines: Self.initialize(initializeFixture) + calls.map { try JSONSerialization.data(withJSONObject: $0) },
            usage: usage
        )
        // A bounded client's calls answer on tasks of their own, in any order.
        let answers = responses.filter { ($0["id"] as? Int ?? 0) >= 3 }.sorted { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }

        #expect(answers.map { MCPExchange.text(of: $0) } == [
            "refused — x/../y is not a walk handle",
            "refused — walk_status needs a 'handle' string",
            "refused — walk_status needs a 'handle' string",
        ])
        #expect(answers.allSatisfy(MCPExchange.isError))
    }

    /// An unsafe session id files its progress under the stem `default` (``ProgressLocation/fileStem(_:)``), and a handle spelled with that stem reads it back.
    @Test
    func aBoundedPollAnswersAFinishedDryRunFiledUnderTheDefaultStem() async throws {
        let directory = try TemporaryDirectory()
        let progress = WalkProgress(tool: "walk --dry-run", phase: .done, pid: getpid(), startedAt: Date(timeIntervalSince1970: 1_700_000_000.123))
        let url = ProgressLocation.progressURL(session: "not/safe id", in: directory.url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WalkProgress.encoder().encode(progress).write(to: url)
        let handle = WalkHandle(stem: "default", progress: progress)

        let parsed = try #require(WalkHandle(parsing: handle.text))
        let responses = try await MCPExchange.send(
            lines: Self.initialize("cursor-1.0.0-initialize") + [JSONSerialization.data(withJSONObject: MCPExchange.call(id: 3, tool: "walk_status", arguments: ["handle": handle.text]))],
            usage: UsageLog(directory: directory.url, now: { Date() })
        )
        let poll = try #require(responses.first { $0["id"] as? Int == 3 })

        #expect(parsed == handle)
        #expect(url.deletingPathExtension().lastPathComponent == "default")
        #expect(MCPExchange.text(of: poll) == "ok — the dry run \(handle.text) finished; a dry run keeps no result file")
        #expect(!MCPExchange.isError(poll))
    }

    /// The usage line's `err` is the reason, as a walk's failure writes it; the `refused — ` is the answer's own prefix.
    @Test
    func aFailedWalkStatusLogsItsReasonWithoutTheRefusedPrefix() async throws {
        let directory = try TemporaryDirectory()
        let responses = try await MCPExchange.send(
            lines: Self.initialize("cursor-1.0.0-initialize") + [JSONSerialization.data(withJSONObject: MCPExchange.call(id: 3, tool: "walk_status", arguments: ["handle": "ghost@1-2"]))],
            usage: UsageLog(directory: directory.url, now: { Date() })
        )
        let poll = try #require(responses.first { $0["id"] as? Int == 3 })
        let text = try #require(MCPExchange.text(of: poll))
        let logged = try String(contentsOf: directory.url.appendingPathComponent("usage.jsonl"), encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(UsageLog.Entry.self, from: Data($0.utf8)) }
        let entry = try #require(logged.first { $0.tool == "walk_status" })

        #expect(MCPExchange.isError(poll))
        #expect(text.hasPrefix("refused — "))
        #expect(entry.error == String(text.dropFirst("refused — ".count)))
        #expect(entry.kind == .toolError)
    }

    @Test
    func theClientEnvironmentVariableReplacesTheRecordedName() async throws {
        let asBounded = try await Self.listedTools(initializeFixture: "claude-code-2.1.302-initialize", environment: ["SIMWALK_MCP_CLIENT": "Cursor"])
        let asBlocking = try await Self.listedTools(initializeFixture: "cursor-1.0.0-initialize", environment: ["SIMWALK_MCP_CLIENT": "claude-code"])

        #expect(asBounded.count == 9)
        #expect(asBlocking.count == 8)
    }

    // MARK: Budget

    @Test(arguments: [
        BudgetCase(raw: nil, seconds: 50, warns: false),
        BudgetCase(raw: "12.5", seconds: 12.5, warns: false),
        BudgetCase(raw: "0", seconds: 50, warns: true),
        BudgetCase(raw: "-3", seconds: 50, warns: true),
        BudgetCase(raw: "abc", seconds: 50, warns: true),
    ])
    func theBudgetParsesAndAFallbackWarnsOnStderrOnly(_ budgetCase: BudgetCase) async throws {
        let (raw, seconds, warns) = (budgetCase.raw, budgetCase.seconds, budgetCase.warns)
        let environment = raw.map { [MCPCallBudget.environmentKey: $0] } ?? [:]
        #expect(MCPCallBudget(environment: environment).seconds == seconds)

        let log = Lines()
        let responses = try await MCPExchange.send([["jsonrpc": "2.0", "id": 1, "method": "ping"]], environment: environment, log: { log.add($0) })

        // `MCPExchange.send` throws on any stdout line that is not JSON-RPC, so a warning there fails the call.
        #expect(responses.count == 1)
        #expect(log.all.count == (warns ? 1 : 0))
        if warns {
            #expect(log.all.first?.contains(MCPCallBudget.environmentKey) == true)
        }
    }
}

extension MCPClientModeTests {
    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        func add(_ line: String) {
            lock.withLock { stored.append(line) }
        }

        var all: [String] {
            lock.withLock { stored }
        }
    }

    struct BudgetCase: Sendable {
        let raw: String?
        let seconds: Double
        let warns: Bool
    }
}

extension Data {
    /// The fixture's one line, without its newline.
    var trimmedLine: Data {
        last == 0x0A ? dropLast() : self
    }
}
