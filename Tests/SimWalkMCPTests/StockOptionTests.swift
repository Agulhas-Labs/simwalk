//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import Testing

/// The MCP `walk` tool's `stock` reaches the command line as `--stock`.
struct StockOptionTests {
    @Test
    func stockReachesTheCommandLine() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: ["walkbook": "example.json", "output": "out.simwalk", "stock": true])

        #expect(invocation.argumentVector == ["--output=out.simwalk", "--stock", "--", "example.json"])
    }
}
