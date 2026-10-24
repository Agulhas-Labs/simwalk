//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import Testing

/// The text `tools/list` spends in every session is held to a budget, so a later addition that grows it fails here rather than waiting for the next measurement (Brief, J13).
struct MCPToolCatalogBudgetTests {
    private static let replyBytes = 12000
    private static let toolDescriptionCharacters = 400
    private static let propertyDescriptionCharacters = 120

    private static let clients = ["claude-code-2.1.302-initialize", "cursor-1.0.0-initialize"]

    private static func fixture(_ name: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        return try Data(contentsOf: url)
    }

    /// The reply line to `tools/list`, as the server wrote it.
    private static func listReply(initializeFixture: String, sourceLocation: SourceLocation = #_sourceLocation) async throws -> Data {
        let initialize = try Self.fixture(initializeFixture, sourceLocation: sourceLocation).trimmedLine
        let list = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let written = try await MCPExchange.written(lines: [initialize, list])
        let lines = written.split(separator: 0x0A, omittingEmptySubsequences: true)
        let reply = try #require(lines.last.map { Data($0) }, sourceLocation: sourceLocation)
        let object = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any], sourceLocation: sourceLocation)
        #expect(object["id"] as? Int == 2, "the last line the server wrote is not the tools/list reply", sourceLocation: sourceLocation)
        _ = try tools(from: reply, sourceLocation: sourceLocation)
        return reply
    }

    @Test(arguments: clients)
    func theReplyStaysWithinTheByteBudget(client: String) async throws {
        let reply = try await Self.listReply(initializeFixture: client)

        #expect(reply.count <= Self.replyBytes, "\(client): the tools/list reply is \(reply.count) bytes, the budget \(Self.replyBytes)")
    }

    @Test(arguments: clients)
    func everyToolDescriptionStaysWithinItsBudget(client: String) async throws {
        let tools = try await Self.tools(from: Self.listReply(initializeFixture: client))

        #expect(!tools.isEmpty)
        for tool in tools {
            let name = tool["name"] as? String ?? "?"
            let size = (tool["description"] as? String ?? "").count
            #expect(size <= Self.toolDescriptionCharacters, "\(client): the description of '\(name)' is \(size) characters, the budget \(Self.toolDescriptionCharacters)")
        }
    }

    @Test(arguments: clients)
    func everyPropertyDescriptionStaysWithinItsBudget(client: String) async throws {
        let tools = try await Self.tools(from: Self.listReply(initializeFixture: client))
        var seen = 0

        for tool in tools {
            let name = tool["name"] as? String ?? "?"
            let properties = (tool["inputSchema"] as? [String: Any])?["properties"] as? [String: [String: Any]] ?? [:]
            for (property, schema) in properties {
                let size = (schema["description"] as? String ?? "").count
                seen += 1
                #expect(size <= Self.propertyDescriptionCharacters, "\(client): '\(name).\(property)' is \(size) characters, the budget \(Self.propertyDescriptionCharacters)")
            }
        }

        #expect(seen > 0)
    }

    private static func tools(from reply: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [[String: Any]] {
        let object = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any], sourceLocation: sourceLocation)
        return try #require((object["result"] as? [String: Any])?["tools"] as? [[String: Any]], sourceLocation: sourceLocation)
    }
}
