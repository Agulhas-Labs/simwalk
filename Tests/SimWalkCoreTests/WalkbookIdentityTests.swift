//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The manifest says which build it validated; the walkbook hash is what lets it say which *plan* produced it.
///
/// It has to be stable against reformatting and sensitive to the route actually changing, or it answers neither question.
struct WalkbookIdentityTests {
    @Test
    func thesameWalkbookHashesTheSameEveryTime() throws {
        let first = try WalkbookIdentity.hash(of: Self.walkbook())
        let second = try WalkbookIdentity.hash(of: Self.walkbook())

        #expect(first == second)
        #expect(first.count == 64)
    }

    @Test
    func aReformattedFileHashesToTheSameWalk() throws {
        let compact = Data(#"{"name":"w","appBundleID":"a","screens":[]}"#.utf8)
        let spaced = Data(
            """
            {
              "appBundleID" : "a",
              "screens" : [],
              "name" : "w"
            }
            """.utf8
        )

        let fromCompact = try WalkbookIdentity.hash(of: JSONDecoder().decode(Walkbook.self, from: compact))
        let fromSpaced = try WalkbookIdentity.hash(of: JSONDecoder().decode(Walkbook.self, from: spaced))

        #expect(fromCompact == fromSpaced)
    }

    @Test
    func aChangedRouteHashesToADifferentWalk() throws {
        var changed = Self.walkbook()
        changed.screens[0].route.append(.back)

        #expect(try WalkbookIdentity.hash(of: changed) != WalkbookIdentity.hash(of: Self.walkbook()))
    }

    @Test
    func aChangedCaptureStateHashesToADifferentWalk() throws {
        var changed = Self.walkbook()
        changed.screens[0].states.append(Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "accessibility3"))

        #expect(try WalkbookIdentity.hash(of: changed) != WalkbookIdentity.hash(of: Self.walkbook()))
    }

    /// **A pinned digest, because the alternative is a hash that drifts silently.**
    ///
    /// Every field added to the model changes the canonical encoding unless it is optional and absent, and a manifest's claim about *which plan ran* would then change under every consumer at once — two bundles of the same walk reading as two different walks, which is the exact question this hash exists to answer. A field that legitimately changes this number changes it here first, deliberately.
    @Test
    func awalkbookOfThisShapeHashesToAknownValue() throws {
        #expect(try WalkbookIdentity.hash(of: Self.walkbook()) == "09b899a8ab35dd47e62498d1acc7eb12907f42d66ea2e197bba3e2ca65502955")
    }

    /// A screen stating its own quiet period is a different plan from one that does not: it changes what the runner waits for, so two bundles taken under the two are not comparable as the same walk.
    @Test
    func aScreenStatingItsOwnQuietPeriodHashesToAdifferentWalk() throws {
        var changed = Self.walkbook()
        changed.screens[0].settle = 6000

        #expect(try WalkbookIdentity.hash(of: changed) != WalkbookIdentity.hash(of: Self.walkbook()))
    }

    // MARK: isPlan

    @Test
    func theFullWalkbookIsThePlanOfAManifestThatHashedIt() throws {
        let book = Self.twoScreenWalkbook()
        let manifest = try Self.manifest(hash: WalkbookIdentity.hash(of: book), screens: ["today", "you"])

        #expect(try WalkbookIdentity.isPlan(book, of: manifest))
    }

    /// A `--screens` walk hashes its subset, so the full walkbook it was narrowed from is still its plan.
    @Test
    func theFullWalkbookIsThePlanOfASubsetWalk() throws {
        let book = Self.twoScreenWalkbook()
        let subset = try WalkbookSubset.narrow(book, to: ["today"])
        let manifest = try Self.manifest(hash: WalkbookIdentity.hash(of: subset), screens: ["today"])

        #expect(try WalkbookIdentity.isPlan(book, of: manifest))
    }

    @Test
    func aChangedRouteInTheSubsetIsNotThePlan() throws {
        let book = Self.twoScreenWalkbook()
        let subset = try WalkbookSubset.narrow(book, to: ["today"])
        let manifest = try Self.manifest(hash: WalkbookIdentity.hash(of: subset), screens: ["today"])
        var changed = book
        changed.screens[0].route.append(.back)

        #expect(try !WalkbookIdentity.isPlan(changed, of: manifest))
    }

    @Test
    func aManifestNamingAScreenTheWalkbookLacksIsNotItsPlan() throws {
        let book = Self.twoScreenWalkbook()
        let manifest = try Self.manifest(hash: "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0", screens: ["today", "gone"])

        #expect(try !WalkbookIdentity.isPlan(book, of: manifest))
    }

    private static func twoScreenWalkbook() -> Walkbook {
        var book = walkbook()
        book.screens.append(Walkbook.Screen(id: "you", route: [.tab(label: "You")], states: [Walkbook.CaptureState(theme: .light)]))
        return book
    }

    /// A manifest recording `hash` and holding `screens`, written through the bundle fixture and read back.
    private static func manifest(hash: String, screens: [String]) throws -> CaptureManifest {
        let directory = try TemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.url) }
        let specs = screens.map { id in
            CaptureBundleFixture.ScreenSpec(id: id, captures: [
                CaptureBundleFixture.Capture(screenID: id, state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button")),
            ])
        }
        return try CaptureBundleFixture.writeWalk(in: directory, screens: specs, walkbookHash: hash).manifest
    }

    private static func walkbook() -> Walkbook {
        Walkbook(
            name: "example-validation",
            appBundleID: "dev.simwalk.route-fixture",
            screens: [
                Walkbook.Screen(
                    id: "today",
                    route: [.tab(label: "Today")],
                    states: [Walkbook.CaptureState(theme: .light), Walkbook.CaptureState(theme: .dark)]
                ),
            ]
        )
    }
}
