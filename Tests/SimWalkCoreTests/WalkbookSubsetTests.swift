//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A subset is a walkbook in its own right, and the tests that matter are the ones pinning what it does *not* inherit from the original.
struct WalkbookSubsetTests {
    @Test
    func aSubsetKeepsOnlyTheNamedScreens() throws {
        let narrowed = try WalkbookSubset.narrow(Self.book(), to: ["browse", "you"])

        #expect(narrowed.screens.map(\.id) == ["browse", "you"])
    }

    /// The walkbook's order, never the caller's — a walk is a plan, and reordering it executes a route the author never wrote.
    @Test
    func aSubsetFollowsTheWalkbooksOrderNotTheArguments() throws {
        let narrowed = try WalkbookSubset.narrow(Self.book(), to: ["you", "progress"])

        #expect(narrowed.screens.map(\.id) == ["progress", "you"])
    }

    /// The subset hashes as itself, which is what stops its bundle standing in for a full walk's.
    @Test
    func aSubsetHashesDifferentlyFromTheWalkbookItCameFrom() throws {
        let book = Self.book()
        let narrowed = try WalkbookSubset.narrow(book, to: ["browse"])

        #expect(try WalkbookIdentity.hash(of: narrowed) != WalkbookIdentity.hash(of: book))
    }

    /// A name that is not there is a typo or a rename, and either way the answer has to carry the real names.
    @Test
    func anUnknownScreenIsRefusedListingTheOnesThatExist() {
        #expect(throws: WalkbookSubsetError.unknownScreens(
            requested: ["brwose"],
            available: ["progress", "browse", "you"]
        )) {
            try WalkbookSubset.narrow(Self.book(), to: ["brwose"])
        }
    }

    @Test
    func theRefusalNamesEveryScreenAvailable() {
        let error = WalkbookSubsetError.unknownScreens(requested: ["nope"], available: ["progress", "browse"])

        #expect(error.description.contains("'nope'"))
        #expect(error.description.contains("progress, browse"))
    }

    /// A comma separates ids, so `--screens progress,you` is the two screens, as the option repeated would be.
    @Test
    func aCommaSeparatedValueNarrowsToEachScreenNamed() throws {
        let narrowed = try WalkbookSubset.narrow(Self.book(), to: ["progress,you"])

        #expect(narrowed.screens.map(\.id) == ["progress", "you"])
    }

    /// A value of only commas and blanks names no screen, so it is refused as the value it was given rather than walking nothing (SimWalk#269 review).
    @Test
    func aValueOfOnlyCommasAndBlanksIsRefusedAsUnknown() {
        for value in [",", " , "] {
            #expect(throws: WalkbookSubsetError.unknownScreens(requested: [value], available: ["progress", "browse", "you"])) {
                try WalkbookSubset.narrow(Self.book(), to: [value])
            }
        }
    }

    @Test
    func spacesAroundAPartAndEmptyPartsAreIgnored() throws {
        let narrowed = try WalkbookSubset.narrow(Self.book(), to: ["progress, you,", ",browse"])

        #expect(narrowed.screens.map(\.id) == ["progress", "browse", "you"])
    }

    /// A screen whose id holds a comma still answers to its whole id: the split applies only when no screen has the value as its id.
    @Test
    func aScreenWhoseIdHoldsACommaIsTakenWhole() throws {
        let book = Walkbook(
            name: "example",
            appBundleID: "dev.simwalk.route-fixture",
            screens: ["x,y", "x", "y"].map { id in
                Walkbook.Screen(
                    id: id,
                    route: [.tab(label: id)],
                    states: [Walkbook.CaptureState(theme: .light)]
                )
            }
        )

        #expect(try WalkbookSubset.narrow(book, to: ["x,y"]).screens.map(\.id) == ["x,y"])
    }

    /// The refusal names the part that is no screen, not the whole value it came from.
    @Test
    func aCommaSeparatedValueWithAnUnknownPartIsRefusedNamingOnlyThatPart() {
        #expect(throws: WalkbookSubsetError.unknownScreens(
            requested: ["nope"],
            available: ["progress", "browse", "you"]
        )) {
            try WalkbookSubset.narrow(Self.book(), to: ["progress,nope"])
        }
    }

    private static func book() -> Walkbook {
        Walkbook(
            name: "example",
            appBundleID: "dev.simwalk.route-fixture",
            screens: ["progress", "browse", "you"].map { id in
                Walkbook.Screen(
                    id: id,
                    route: [.tab(label: id.capitalized)],
                    states: [Walkbook.CaptureState(theme: .light)]
                )
            }
        )
    }
}
