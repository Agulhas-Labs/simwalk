//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A walk-level `setup` is decoded strictly and its privacy services are held to `simctl privacy`'s own list.
struct WalkbookSetupTests {
    @Test
    func aSetupNamingKnownServicesLoads() throws {
        let book = try WalkbookLoader.load(from: Self.walkbook(setup: #"{"privacy":{"grant":["photos","location"],"revoke":["contacts"]},"statusBar":"clean","increaseContrast":true}"#), source: "book.json")

        #expect(book.setup == Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["photos", "location"], revoke: ["contacts"]), statusBar: .clean, increaseContrast: true))
        #expect(book.setup?.changesDevice == true)
    }

    @Test
    func anUnknownServiceIsRefusedWithItsNearestName() {
        let problems = Self.problems(setup: #"{"privacy":{"grant":["locaton","health"]}}"#)

        #expect(problems.contains(.unknownPrivacyService(value: "locaton", suggestion: "location")))
        #expect(problems.contains {
            if case .unknownPrivacyService("health", _) = $0 {
                true
            } else {
                false
            }
        })
        #expect(problems.map(\.description).contains { $0.contains("HealthKit is not one of them") })
    }

    @Test
    func aServiceBothGrantedAndRevokedIsRefused() {
        #expect(Self.problems(setup: #"{"privacy":{"grant":["photos"],"revoke":["photos"]}}"#) == [.privacyGrantedAndRevoked(service: "photos")])
    }

    /// A per-state reset puts the resource back to not-yet-asked before launch, so a walk-level grant of it is undone (SimWalk#62).
    @Test
    func aGrantUndoneByAStateResetIsRefused() {
        let problems = Self.problems(setup: #"{"privacy":{"grant":["photos-add","motion"]}}"#, states: #"[{"theme":"light","resetPermissions":["photos","bluetooth"]}]"#)

        guard problems.count == 1, case let .privacyGrantUndoneByReset(screenID, index, state, resource, service) = problems[0] else {
            Issue.record("expected one privacyGrantUndoneByReset, got \(problems)")
            return
        }
        #expect((screenID, index, resource, service) == ("home", 0, "photos", "photos-add"))
        #expect(state.hasPrefix("light-reset_"))
        let message = problems[0].description
        #expect(message.contains("'photos'") && message.contains("'photos-add'") && message.contains("'\(state)'") && message.contains("resetPermissions") && message.contains("setup.privacy.grant"))
    }

    @Test
    func aResetOfAnotherResourceLeavesTheGrantAlone() {
        #expect(Self.problems(setup: #"{"privacy":{"grant":["photos","motion"]}}"#, states: #"[{"theme":"light","resetPermissions":["camera","health"]}]"#).isEmpty)
    }

    @Test
    func anUnknownSetupKeyIsRefusedWithItsNearestName() {
        #expect(Self.problems(setup: #"{"statusbar":"clean"}"#).contains {
            if case .unknownKey(_, "statusbar", "statusBar") = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test
    func aWalkbookWithoutSetupHashesAsItDidBefore() throws {
        let data = Self.walkbook(setup: nil)
        let book = try WalkbookLoader.load(from: data, source: "book.json")

        #expect(book.setup == nil)
        #expect(try !String(decoding: JSONEncoder().encode(book), as: UTF8.self).contains("setup"))
    }

    private static func problems(setup: String, states: String = #"[{"theme":"light"}]"#) -> [WalkbookProblem] {
        do {
            _ = try WalkbookLoader.load(from: walkbook(setup: setup, states: states), source: "book.json")
            return []
        } catch let WalkbookLoadError.invalid(_, problems) {
            return problems
        } catch {
            return [.undecodable(reason: "\(error)")]
        }
    }

    private static func walkbook(setup: String?, states: String = #"[{"theme":"light"}]"#) -> Data {
        let setupField = setup.map { #","setup":\#($0)"# } ?? ""
        return Data(#"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"home","route":[{"tab":{"label":"Home"}}],"states":\#(states)}]\#(setupField)}"#.utf8)
    }
}
