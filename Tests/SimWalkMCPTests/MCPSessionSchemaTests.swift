//
// Copyright © Agulhas Labs
//

import SimWalkCore
@testable import SimWalkMCP
import Testing

/// The `session` schema lists the state keys and step kinds the decoder takes (SimWalk#293).
///
/// An agent guessed a state key, left out `theme` and named a step kind that does not exist, each a refusal the schema could have prevented. The schema is generated from the lists the decoder checks against, so it cannot name a key the decoder refuses or miss one it takes.
struct MCPSessionSchemaTests {
    private static var sessionProperties: [String: [String: Any]] {
        let tool = MCPToolCatalog.tools(for: .blocking).first { $0["name"] as? String == SimWalkTool.session.rawValue }
        let schema = tool?["inputSchema"] as? [String: Any]
        return schema?["properties"] as? [String: [String: Any]] ?? [:]
    }

    @Test
    func theStateSchemaListsEveryStateKeyAndRequiresTheme() throws {
        let state = try #require(Self.sessionProperties["state"])
        let properties = try #require(state["properties"] as? [String: Any])

        #expect(Set(properties.keys) == Set(Walkbook.CaptureState.keys))
        #expect(state["required"] as? [String] == ["theme"])
        #expect(state["additionalProperties"] as? Bool == false)
        #expect((properties["theme"] as? [String: Any])?["enum"] as? [String] == ["light", "dark"])
    }

    @Test
    func theStepDescriptionNamesEveryKindWithItsKeys() throws {
        let step = try #require(Self.sessionProperties["step"])
        let description = try #require(step["description"] as? String)

        for kind in Walkbook.RouteStep.kinds {
            #expect(description.contains("\(kind.name){\(kind.keys.joined(separator: ","))}"), "\(kind.name) is missing from: \(description)")
        }
    }
}
