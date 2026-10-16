//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import Testing

/// `mirror`'s JSON arguments as the command line `simwalk mirror <action>` parses: the action first, options attached, positionals after the terminator.
struct MCPMirrorInvocationTests {
    @Test
    func eachActionBuildsItsSubcommandsCommandLineAndLogsAsTheCLIDoes() throws {
        let read = try MCPToolInvocation(tool: "mirror", arguments: ["action": "read", "match": "row", "settleMs": 500, "out": "/tmp/k"])
        let tap = try MCPToolInvocation(tool: "mirror", arguments: ["action": "tap", "at": [0.25, 0.5]])
        let swipe = try MCPToolInvocation(tool: "mirror", arguments: ["action": "swipe", "at": [0.5, 0.8], "to": [0.5, 0.2], "ms": 600])
        let scroll = try MCPToolInvocation(tool: "mirror", arguments: ["action": "scroll", "lines": -3, "horizontal": true, "at": [0.1, 0.9]])
        let menu = try MCPToolInvocation(tool: "mirror", arguments: ["action": "menu", "item": "switcher"])
        let burst = try MCPToolInvocation(tool: "mirror", arguments: ["action": "burst", "at": [0.5, 0.5], "frames": 12, "sheet": true])

        #expect(read.argumentVector == ["read", "--match=row", "--settle-ms=500", "--out=/tmp/k", "--"])
        #expect(tap.argumentVector == ["tap", "--", "0.25", "0.5"])
        #expect(swipe.argumentVector == ["swipe", "--ms=600", "--", "0.5", "0.8", "0.5", "0.2"])
        #expect(scroll.argumentVector == ["scroll", "--horizontal", "--at=0.1,0.9", "--", "-3"])
        #expect(menu.argumentVector == ["menu", "--", "switcher"])
        #expect(burst.argumentVector == ["burst", "--frames=12", "--sheet", "--", "0.5", "0.5"])
        #expect(tap.logName == "mirror tap")
        #expect(burst.logName == "mirror burst")
        #expect(tap.tool == .mirror)
    }

    @Test
    func aStrayArgumentIsRefusedByName() {
        let error = #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "mirror", arguments: ["action": "tap", "at": [0.5, 0.5], "lines": 3])
        }

        #expect(error?.message.contains("'lines'") == true)
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "burst", "at": [0.5, 0.5], "frames": 3, "match": "x"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "dance"]) }
    }

    @Test
    func aGestureOutsideItsBoundsIsRefusedAsInputRefusedNamingTheRange() {
        let scrolls: [Any] = [0, 51, -51, 100_000, 5_000_000_000]
        for lines in scrolls {
            let error = #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "scroll", "lines": lines]) }
            #expect(error?.kind == .inputRefused)
            #expect(error?.message.contains("1 to 50") == true)
        }
        for ms in [0, 49, 5001, 600_000] {
            let error = #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "swipe", "at": [0.5, 0.8], "to": [0.5, 0.2], "ms": ms]) }
            #expect(error?.kind == .inputRefused)
            #expect(error?.message.contains("50 to 5000") == true)
        }
    }

    @Test
    func anAtThatIsNotTwoNumbersIsRefused() {
        for point: Any in [[0.5], [0.5, 0.5, 0.5], ["a", "b"], [true, false], "0.5,0.5", 0.5] {
            #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "tap", "at": point]) }
        }

        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "tap"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "scroll"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "menu", "item": "dock"]) }
        #expect(throws: MCPError.self) { try MCPToolInvocation(tool: "mirror", arguments: ["action": "burst", "at": [0.5, 0.5]]) }
    }

    @Test
    func theCatalogListsMirrorWithItsSixActions() throws {
        let entry = try #require(MCPToolCatalog.tools.first { $0["name"] as? String == "mirror" })
        let schema = try #require(entry["inputSchema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        let action = try #require(properties["action"] as? [String: Any])

        #expect(action["enum"] as? [String] == ["read", "tap", "swipe", "scroll", "menu", "burst"])
        #expect(MCPToolCatalog.tools.count == SimWalkTool.allCases.count)
    }
}
