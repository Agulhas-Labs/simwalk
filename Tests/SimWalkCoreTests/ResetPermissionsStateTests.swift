//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The `resetPermissions` axis: decoded strictly beside the others, slugged after them, and refused at validate when it names nothing the runner could reset.
struct ResetPermissionsStateTests {
    @Test
    func aStateCarryingResetPermissionsDecodesThem() throws {
        let json = #"{"theme":"light","resetPermissions":["location","camera"]}"#

        let state = try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))

        #expect(state == Walkbook.CaptureState(theme: .light, resetPermissions: ["location", "camera"]))
        #expect(state.resourcesToReset == [.camera, .location])
    }

    /// After `geo_`, over the names de-duplicated and sorted: the same resets written in another order, or twice, are one state.
    @Test
    func resetPermissionsSlugByTheirHashAfterTheLocation() {
        let london = Walkbook.Location(latitude: 51.5, longitude: -0.12)
        let state = Walkbook.CaptureState(theme: .light, location: london, resetPermissions: ["location", "camera"])
        let located = Walkbook.CaptureState(theme: .light, location: london).slug

        #expect(state.slug.hasPrefix(located + "-reset_"))
        #expect(state.slug.count == located.count + "-reset_".count + 8)
        #expect(state.slug == Walkbook.CaptureState(theme: .light, location: london, resetPermissions: ["camera", "location", "camera"]).slug)
        #expect(state.slug != Walkbook.CaptureState(theme: .light, location: london, resetPermissions: ["location"]).slug)
    }

    @Test
    func anUnknownPermissionIsRefusedWithTheNameItProbablyMeant() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","resetPermissions":["locaton"]}"#)

        #expect(problems == [.unknownPermission(screenID: "today", index: 0, value: "locaton", suggestion: "location")])
        #expect(try #require(problems.first).description.hasSuffix("; did you mean 'location'?"))
    }

    /// An empty list resets nothing while slugging as a different state, so it is refused rather than read as absent — as an empty `arguments` is.
    @Test
    func anEmptyResetPermissionsListIsRefusedAtValidate() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","resetPermissions":[]}"#)

        #expect(problems == [.emptyLaunchCondition(screenID: "today", index: 0, key: "resetPermissions")])
        #expect(problems.map(\.description) == ["screen 'today' requests resetPermissions [] — an empty list resets nothing exactly as its absence does, so omit the key"])
    }

    @Test
    func aMisspelledResetPermissionsKeyIsRefused() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","resetPermission":["location"]}"#)

        #expect(problems == [.unknownKey(path: "screens[0].states[0]", key: "resetPermission", suggestion: "resetPermissions")])
    }

    /// The problems `WalkbookLoader.load` reports for a one-screen walkbook whose `states` list holds `states`, written as JSON.
    private static func problems(loading states: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [WalkbookProblem] {
        let json = #"{"name":"w","appBundleID":"com.example.app","screens":[{"id":"today","route":[{"tab":{"label":"Today"}}],"states":["# + states + #"]}]}"#
        let thrown = try #require(
            #expect(throws: WalkbookLoadError.self, sourceLocation: sourceLocation) {
                try WalkbookLoader.load(from: Data(json.utf8), source: "memory")
            },
            sourceLocation: sourceLocation
        )
        guard case let .invalid(_, problems) = thrown else {
            Issue.record("expected an invalid refusal, got \(thrown)", sourceLocation: sourceLocation)
            return []
        }
        return problems
    }
}
