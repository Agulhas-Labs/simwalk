//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The Phase 0 gate (Brief §6): the hand-written walkbook for the route fixture app parses and validates, and carries the launch argument that fixture needs to show its tabbed root.
///
/// It is read off disk rather than built in Swift on purpose — the gate is about the *format*, so a test that constructed the model directly would pass while the committed file was unparseable.
struct ExampleWalkbookTests {
    @Test
    func theExampleWalkbookParsesAndValidates() throws {
        let walkbook = try WalkbookLoader.load(contentsOf: Self.fixtureURL())

        #expect(walkbook.name == "example-validation")
        #expect(walkbook.appBundleID == "dev.simwalk.route-fixture")
        #expect(WalkbookLoader.problems(in: walkbook).isEmpty)
    }

    @Test
    func theExampleWalkbookLaunchesEveryStateIntoTheTabbedRootAndExpectsEachScreen() throws {
        let walkbook = try WalkbookLoader.load(contentsOf: Self.fixtureURL())
        let expected = [
            "hub": "hub-screen",
            "hub-form": "form-screen",
            "rows": "rows-screen",
            "rows-partly-covered": "rows-screen",
            "hub-form-return": "hub-screen",
        ]

        #expect(walkbook.screens.map(\.id).sorted() == expected.keys.sorted())
        for screen in walkbook.screens {
            #expect(screen.expect == expected[screen.id], "screen '\(screen.id)' should expect its fixture screen identifier")
            for state in screen.states {
                #expect(state.arguments == ["-RouteFixtureTabs"], "screen '\(screen.id)' needs the argument that shows the tabbed root")
            }
        }
    }

    @Test
    func theExampleWalkbookCoversARootScreenAndItsDetailScreensInBothThemes() throws {
        let walkbook = try WalkbookLoader.load(contentsOf: Self.fixtureURL())
        let ids = walkbook.screens.map(\.id)

        #expect(ids.contains("hub"))
        #expect(ids.contains("hub-form"))
        #expect(ids.contains("rows-partly-covered"))
        for screen in walkbook.screens where screen.id != "hub-form-return" {
            let themes = Set(screen.states.map(\.theme))
            #expect(themes == [.light, .dark], "screen '\(screen.id)' should be captured in both themes")
        }
    }

    @Test
    func theExampleWalkbookRoutesReachDetailScreensByTabThenTap() throws {
        let walkbook = try WalkbookLoader.load(contentsOf: Self.fixtureURL())
        let form = try #require(walkbook.screens.first { $0.id == "hub-form" })
        let popped = try #require(walkbook.screens.first { $0.id == "hub-form-return" })

        #expect(form.route == [.tab(label: "Hub"), .tap(label: "Open form")])
        let covered = try #require(walkbook.screens.first { $0.id == "rows-partly-covered" })

        #expect(popped.route.last == .back)
        #expect(covered.route == [.tab(label: "Rows"), .scrollTo(label: "Partly covered row")])
    }

    private static func fixtureURL(sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        try #require(
            Bundle.module.url(forResource: "example-walk", withExtension: "json", subdirectory: "Fixtures"),
            sourceLocation: sourceLocation
        )
    }
}
