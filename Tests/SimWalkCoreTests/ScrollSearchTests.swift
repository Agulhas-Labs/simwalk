//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// `ScrollSearch`: a `scrollTo` swipes towards a row a lazy list has not built, and a give-up names the label, the swipes and why they stopped (SimWalk#74).
struct ScrollSearchTests {
    /// **The Settings re-walk (#66)**: `Privacy & Security` is not in the tree until the list is swiped, so the step swipes and reads again rather than answering a bare "did not land" from its first read.
    @Test
    func aRowTheListHasNotBuiltIsSwipedTowardsUntilItIsThere() {
        var search = ScrollSearch(label: "Privacy & Security", limit: 12)

        let moves = [
            search.seek(in: Self.list(["General", "Accessibility"], from: 100)),
            search.seek(in: Self.list(["Camera", "Display & Brightness"], from: 100)),
            search.seek(in: Self.list(["Siri", "Privacy & Security"], from: 100)),
        ]

        #expect(moves == [.swipe, .swipe, .found])
        #expect(search.swipes == 2)
    }

    /// A swipe after which the screen reads exactly as before is the end of the list: the step stops there, naming the label, the swipes taken and the standstill.
    @Test
    func aSwipeThatMovesNothingStopsAtTheEndOfTheList() {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let top = Self.list(["Display & Text Size", "Motion"], from: 100)
        let bottom = Self.list(["Spoken Content", "Audio Descriptions"], from: 100)

        #expect(search.seek(in: top) == .swipe)
        #expect(search.seek(in: bottom) == .swipe)
        #expect(search.seek(in: bottom) == .stopped(
            .endOfList,
            reason: "nothing on screen is labelled or identified 'Classic Invert': swiped up 2 times and the last swipe moved nothing — the list is at its end, or nothing here scrolls"
        ))
    }

    /// **A misspelt `tap` label on a screen with nothing to scroll** is refused at the first read, not after a swipe and a second read (SimWalk#119).
    @Test
    func aScreenWithNoScrollContainerIsNotSwipedAtAll() {
        var search = ScrollSearch(label: "Sav", limit: 12)
        let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let tree = AXNode(type: "Application", frame: frame, children: [AXNode(type: "Button", frame: frame, label: "Save")])

        #expect(search.seek(in: tree) == .stopped(
            .nothingScrolls,
            reason: "nothing on screen is labelled or identified 'Sav': nothing on this screen scrolls (no table, collection, scroll or web view), so nothing was swiped"
        ))
        #expect(search.swipes == 0)
    }

    /// **A web page scrolls with no scroll view in the tree**, so a label not yet on it is swiped towards rather than refused as unscrollable.
    @Test
    func aWebViewIsSwipedTowardsAsAScrollContainer() {
        var search = ScrollSearch(label: "Sign up", limit: 12)
        let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let tree = AXNode(type: "Application", frame: frame, children: [
            AXNode(type: "WebView", frame: frame, children: [AXNode(type: "StaticText", frame: frame, label: "Welcome")]),
        ])

        #expect(search.seek(in: tree) == .swipe)
    }

    /// **The whole tree, frames included**: a scroll moves rows without changing what they say, and a comparison that ignored geometry — as `ScreenIdentity` does — would call the first swipe of a long list its end.
    @Test
    func rowsThatOnlyMoveAreNotTheEndOfTheList() {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)

        #expect(search.seek(in: Self.list(["Motion", "Spoken Content"], from: 400)) == .swipe)
        #expect(search.seek(in: Self.list(["Motion", "Spoken Content"], from: 100)) == .swipe)
    }

    /// A screen that never stops moving is given the step's swipes and no more, and the give-up says it ran out rather than reached an end.
    @Test
    func theSwipesRunOutOnAScreenStillMoving() {
        var search = ScrollSearch(label: "Classic Invert", limit: 3)
        let moves = [100.0, 90, 80, 70].map { search.seek(in: Self.list(["Row"], from: $0)) }

        #expect(moves == [.swipe, .swipe, .swipe, .stopped(
            .limit,
            reason: "nothing on screen is labelled or identified 'Classic Invert': swiped up 3 times, the most a step takes, and the screen was still moving"
        )])
    }

    /// One swipe is said as one.
    @Test
    func oneSwipeIsSaidOnce() {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let still = Self.list(["Row"], from: 100)

        #expect(search.seek(in: still) == .swipe)
        #expect(search.seek(in: still) == .stopped(
            .endOfList,
            reason: "nothing on screen is labelled or identified 'Classic Invert': swiped up once and the last swipe moved nothing — the list is at its end, or nothing here scrolls"
        ))
    }

    /// An element found and never within reach of a tap is named as such — it is there, which sends a reader to the screen rather than the walkbook.
    @Test
    func anElementFoundAndNeverWithinReachIsNamed() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let tree = Self.list(["Smart Invert", "Classic Invert"], from: 100)
        let target = try #require(Self.target("Classic Invert", in: tree))

        #expect(search.reach(target, in: tree, hittable: false) == .swipe)
        #expect(search.reach(target, in: tree, hittable: false) == .stopped(
            .endOfList,
            reason: "a Cell labelled 'Classic Invert' never came within reach of a tap: swiped up once and the last swipe moved nothing — the list is at its end, or nothing here scrolls"
        ))
    }

    /// **One budget for both halves**: the swipes that found the label count against the swipes that bring it within reach, so a step takes the bound it documents and no more.
    @Test
    func theSwipesToFindAndToReachShareOneBudget() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 3)
        #expect(search.seek(in: Self.list(["Motion"], from: 100)) == .swipe)
        let found = Self.list(["Classic Invert"], from: 800)
        #expect(search.seek(in: found) == .found)
        let target = try #require(Self.target("Classic Invert", in: found))

        let moves = [700.0, 600, 500].map { search.reach(target, in: Self.list(["Classic Invert"], from: $0), hittable: false) }

        guard case let .stopped(stop, reason) = moves.last else {
            Issue.record("expected the swipes to run out, got \(moves)")
            return
        }
        #expect(moves.dropLast() == [.swipe, .swipe])
        #expect(stop == .limit)
        #expect(reason.hasPrefix("a Cell labelled 'Classic Invert' never came within reach of a tap: swiped up 3 times"))
        #expect(search.swipes == 3)
    }

    /// **The documented bound holds when the label flickers**: a seek read that carries it and a resolve that then finds nothing is a swipe spent, so a label that keeps doing that ends at the step's swipes rather than looping.
    @Test
    func aLabelFoundAndThenLostSpendsTheSwipeBudget() {
        var search = ScrollSearch(label: "Classic Invert", limit: 3)

        var moves: [ScrollSearch.Move] = []
        for step in 0 ..< 4 {
            let tree = Self.list(["Classic Invert"], from: 100 - Double(step) * 10)
            moves.append(search.seek(in: tree))
            moves.append(search.lostAfterFound(in: tree))
        }

        #expect(moves.filter { $0 == .swipe }.count == 3)
        #expect(search.swipes == 3)
        guard case let .stopped(stop, _) = moves.last else {
            Issue.record("expected the swipes to run out, got \(moves)")
            return
        }
        #expect(stop == .limit)
    }

    /// The read that starts bringing a found element within reach is not judged a standstill: the tree the last swipe was taken from did not carry the label.
    @Test
    func findingTheLabelStartsTheNextHalfAfresh() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        #expect(search.seek(in: Self.list(["Motion"], from: 100)) == .swipe)
        let found = Self.list(["Classic Invert"], from: 800)
        #expect(search.seek(in: found) == .found)

        let target = try #require(Self.target("Classic Invert", in: found))

        #expect(search.reach(target, in: found, hittable: false) == .swipe)
    }

    /// A hittable element is arrived at without a swipe.
    @Test
    func aHittableElementIsFoundAtOnce() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let tree = Self.list(["Classic Invert"], from: 100)

        let target = try #require(Self.target("Classic Invert", in: tree))

        #expect(search.reach(target, in: tree, hittable: true) == .found)
        #expect(search.swipes == 0)
    }

    /// `type` does not seek (SimWalk#104): a field that is absent is answered as it is, with no tree read and no swipe.
    @Test
    func aTextEntryReachThatResolvesToNothingIsNeitherReadNorSwiped() throws {
        var search = ScrollSearch(label: "Name", limit: 12)
        var reads = 0
        var swipes = 0

        let result = try search.resolveSeeking(
            reaching: .textEntry,
            resolve: { .none },
            read: { reads += 1
                return Self.list(["General"], from: 100)
            },
            swipe: { swipes += 1 }
        )

        #expect(result.choice == .none)
        #expect(result.stopped == nil)
        #expect(reads == 0)
        #expect(swipes == 0)
    }

    /// A seeking reach swipes until a read carries the label, then resolves it.
    @Test
    func aSeekingReachSwipesUntilAReadCarriesTheLabelThenResolves() throws {
        var search = ScrollSearch(label: "Privacy & Security", limit: 12)
        let found = Self.list(["Siri", "Privacy & Security"], from: 100)
        let chosen = try #require(Self.choice("Privacy & Security", in: found))
        var trees = [Self.list(["General"], from: 100), Self.list(["Camera"], from: 100), found]
        var swipes = 0
        var resolved = 0

        let result = try search.resolveSeeking(
            reaching: .anything,
            resolve: { resolved += 1
                return swipes == 2 ? chosen : .none
            },
            read: { trees.removeFirst() },
            swipe: { swipes += 1 }
        )

        #expect(result.choice == chosen)
        #expect(result.stopped == nil)
        #expect(swipes == 2)
        #expect(resolved == 2)
    }

    /// A search that stops hands its reason back, with the choice `.none`.
    @Test
    func aStoppedSearchHandsItsReasonBack() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let screen = Self.list(["Spoken Content"], from: 100)

        let result = try search.resolveSeeking(reaching: .control, resolve: { .none }, read: { screen }, swipe: {})

        #expect(result.choice == .none)
        #expect(result.stopped?.contains("the list is at its end") == true)
    }

    /// The label on the seek read and gone from resolve's costs a swipe, so the loop is bounded by the step's limit rather than going round for ever.
    @Test
    func aLabelLostAfterItWasFoundCostsASwipe() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 3)
        var swipes = 0

        // Each read differs from the last, so a swipe is never judged a standstill.
        let result = try search.resolveSeeking(
            reaching: .anything,
            resolve: { .none },
            read: { Self.list(["Classic Invert"], from: 100 + Double(swipes) * 10) },
            swipe: { swipes += 1 }
        )

        #expect(result.choice == .none)
        #expect(result.stopped != nil)
        #expect(swipes == 3)
        #expect(search.swipes == 3)
    }

    /// A screen of cells, one per label, 44pt apart from `y`.
    private static func list(_ labels: [String], from y: Double) -> AXNode {
        let cells = labels.enumerated().map { index, label in
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: y + Double(index) * 44, width: 402, height: 44), label: label)
        }
        let table = AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: cells)
        return AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [table])
    }

    /// What a `scrollTo` labelled `label` chooses in `tree`, `nil` where it chooses nothing.
    private static func target(_ label: String, in tree: AXNode) -> RouteTarget.Candidate? {
        guard case let .chosen(candidate, _) = RouteTarget.choose(labelled: label, in: tree, reaching: .anything) else { return nil }
        return candidate
    }

    /// What a `scrollTo` labelled `label` chooses in `tree`.
    private static func choice(_ label: String, in tree: AXNode) -> RouteTarget.Choice? {
        let choice = RouteTarget.choose(labelled: label, in: tree, reaching: .anything)
        return choice == .none ? nil : choice
    }
}
