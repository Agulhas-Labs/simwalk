//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// What a device target refuses by name: everything that needs `simctl` (SimWalk#116).
struct DeviceTargetSupportTests {
    private static func walkbook(setup: String? = nil, states: String) throws -> Walkbook {
        let setupField = setup.map { #""setup": \#($0),"# } ?? ""
        let json = #"{"name":"w","appBundleID":"x.y",\#(setupField)"screens":[{"id":"home","route":[{"tab":{"label":"Progress"}}],"states":\#(states)}]}"#
        return try WalkbookLoader.load(from: Data(json.utf8), source: "w.json")
    }

    @Test
    func aPlainWalkbookIsSupported() throws {
        let book = try Self.walkbook(states: #"[{"theme":"light"},{"theme":"dark","dynamicTypeSize":"UICTContentSizeCategoryL"}]"#)

        #expect(DeviceTargetSupport.unsupported(in: book).isEmpty)
    }

    @Test
    func increaseContrastIsTheOneSetupKeyADeviceCanApply() throws {
        let book = try Self.walkbook(setup: #"{"increaseContrast":true}"#, states: #"[{"theme":"light"}]"#)

        #expect(DeviceTargetSupport.unsupported(in: book).isEmpty)
    }

    @Test(arguments: [
        #"{"privacy":{"grant":["location"]}}"#,
        #"{"statusBar":"clean"}"#,
        #"{"increaseContrast":true,"statusBar":"clean"}"#,
    ])
    func aWalkLevelSetupWithPrivacyOrAStatusBarIsNamed(_ setup: String) throws {
        let book = try Self.walkbook(setup: setup, states: #"[{"theme":"light"}]"#)

        let lines = DeviceTargetSupport.unsupported(in: book)

        #expect(lines.count == 1)
        #expect(lines[0].contains("setup") && lines[0].contains("simctl"))
    }

    @Test
    func eachOffendingStateIsListedWithItsScreen() throws {
        let book = try Self.walkbook(states: #"[{"theme":"light","locale":"en_GB"},{"theme":"light","location":{"latitude":1.5,"longitude":2.5}},{"theme":"light","resetPermissions":["location"]}]"#)

        let lines = DeviceTargetSupport.unsupported(in: book)

        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.contains("screen home") })
        #expect(lines[0].contains("locale"))
        #expect(lines[1].contains("location"))
        #expect(lines[2].contains("resetPermissions"))
    }
}
