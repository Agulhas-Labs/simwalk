//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

struct ShardPlanTests {
    /// The Settings fixture's shape: five screens of 3, 2, 1, 2 and 1 states.
    private static func book() throws -> Walkbook {
        let screens = [("root", 3), ("general", 2), ("accessibility", 1), ("display", 2), ("account", 1)].map { id, states in
            #"{"id": "\#(id)", "route": [], "states": [\#(Array(repeating: #"{"theme": "light"}"#, count: states).joined(separator: ", "))]}"#
        }
        let json = #"{"name": "settings", "appBundleID": "com.example.app", "screens": [\#(screens.joined(separator: ", "))]}"#
        return try JSONDecoder().decode(Walkbook.self, from: Data(json.utf8))
    }

    @Test func eachScreenGoesToTheShardWithTheFewestStatesTiesToTheLowestIndex() throws {
        let plan = try ShardPlan(Self.book(), devices: 3)

        #expect(plan.shards == [["root"], ["general", "account"], ["accessibility", "display"]])
        #expect(!plan.clamped)
    }

    @Test func oneDeviceIsTheSerialWalkEveryScreenInWalkbookOrder() throws {
        try #expect(ShardPlan(Self.book(), devices: 1).shards == [["root", "general", "accessibility", "display", "account"]])
    }

    @Test func moreDevicesThanScreensIsClampedToTheScreenCountAndSaysSo() throws {
        let plan = try ShardPlan(Self.book(), devices: 7)

        #expect(plan.shards == [["root"], ["general"], ["accessibility"], ["display"], ["account"]])
        #expect(plan.requested == 7)
        #expect(plan.clamped)
    }
}
