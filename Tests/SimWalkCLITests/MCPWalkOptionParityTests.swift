//
// Copyright © Agulhas Labs
//

import ArgumentParser
@testable import SimWalkCLI
@testable import SimWalkMCP
import Testing

/// The `walk` tool's command line is one the CLI's own `WalkCommand` parses — checkable only where both faces are in scope.
struct MCPWalkOptionParityTests {
    /// Every option the tool builds reaches `WalkCommand`, which parses the vector without refusing any of it.
    @Test
    func theWalkToolsCommandLineParsesThroughWalkCommand() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "example.json",
            "output": "out.simwalk",
            "device": "iPhone 17 Pro",
            "appPath": "/build/App.app",
            "settle": 800,
            "motion": true,
            "appleAudit": true,
            "animations": true,
            "stock": true,
            "screenIDs": ["today", "steps-detail"],
            "verbose": true,
        ])

        let parsed = try WalkCommand.parse(invocation.argumentVector)
        #expect(parsed.stock)
        #expect(parsed.appleAudit)
    }
}
