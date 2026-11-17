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

        #expect(moves == [.swipe(.up), .swipe(.up), .found])
        #expect(search.swipes == 2)
    }

    /// A swipe after which the screen reads exactly as before is the end of the list: the step stops there, naming the label, the swipes taken and the standstill.
    @Test
    func aSwipeThatMovesNothingStopsAtTheEndOfTheList() {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let top = Self.list(["Display & Text Size", "Motion"], from: 100)
        let bottom = Self.list(["Spoken Content", "Audio Descriptions"], from: 100)

        #expect(search.seek(in: top) == .swipe(.up))
        #expect(search.seek(in: bottom) == .swipe(.up))
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
            reason: "nothing on screen is labelled or identified 'Sav'; nearest: 'Save' (starts with it, but a step matches the start of a label only up to a comma, a sentence's end, or a space before a number): nothing on this screen scrolls (no table, collection, scroll or web view), so nothing was swiped"
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

        #expect(search.seek(in: tree) == .swipe(.up))
    }

    /// **The whole tree, frames included**: a scroll moves rows without changing what they say, and a comparison that ignored geometry — as `ScreenIdentity` does — would call the first swipe of a long list its end.
    @Test
    func rowsThatOnlyMoveAreNotTheEndOfTheList() {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)

        #expect(search.seek(in: Self.list(["Motion", "Spoken Content"], from: 400)) == .swipe(.up))
        #expect(search.seek(in: Self.list(["Motion", "Spoken Content"], from: 100)) == .swipe(.up))
    }

    /// A screen that never stops moving is given the step's swipes and no more, and the give-up says it ran out rather than reached an end.
    @Test
    func theSwipesRunOutOnAScreenStillMoving() {
        var search = ScrollSearch(label: "Classic Invert", limit: 3)
        let moves = [100.0, 90, 80, 70].map { search.seek(in: Self.list(["Row"], from: $0)) }

        #expect(moves == [.swipe(.up), .swipe(.up), .swipe(.up), .stopped(
            .limit,
            reason: "nothing on screen is labelled or identified 'Classic Invert': swiped up 3 times, the most a step takes, and the screen was still moving"
        )])
    }

    /// A list at its end whose button an endless SwiftUI pulse rescales between the reads is still at its end, not a screen that kept moving for every swipe the step has.
    @Test
    func aSwipeThatOnlyAPulseMovedStopsAtTheEndOfTheList() {
        var search = ScrollSearch(label: "Correct", limit: 12)
        let resting = Self.list(["Start"], from: 100)
        var pulsed = resting
        pulsed.children[0].children[0].frame = AXNode.Frame(x: -12, y: 98.7, width: 426, height: 46.6)

        #expect(search.seek(in: resting) == .swipe(.up))
        #expect(search.seek(in: pulsed) == .stopped(
            .endOfList,
            reason: "nothing on screen is labelled or identified 'Correct': swiped up once and the last swipe moved nothing — the list is at its end, or nothing here scrolls"
        ))
    }

    /// One swipe is said as one.
    @Test
    func oneSwipeIsSaidOnce() {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let still = Self.list(["Row"], from: 100)

        #expect(search.seek(in: still) == .swipe(.up))
        #expect(search.seek(in: still) == .stopped(
            .endOfList,
            reason: "nothing on screen is labelled or identified 'Classic Invert': swiped up once and the last swipe moved nothing — the list is at its end, or nothing here scrolls"
        ))
    }

    /// An element found and never within reach of a tap is named as such — it is there, which sends a reader to the screen rather than the walkbook.
    @Test
    func anElementFoundAndNeverWithinReachIsNamed() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let tree = Self.list(["Smart Invert", "Classic Invert"], from: 600)
        let target = try #require(Self.target("Classic Invert", in: tree))

        #expect(search.reach(target, at: target.node.frame, in: tree, hittable: false) == .swipe(.up))
        #expect(search.reach(target, at: target.node.frame, in: tree, hittable: false) == .stopped(
            .endOfList,
            reason: "a Cell labelled 'Classic Invert' never came within reach of a tap: swiped up once and the last swipe moved nothing — the list is at its end, or nothing here scrolls"
        ))
    }

    /// **One budget for both halves**: the swipes that found the label count against the swipes that bring it within reach, so a step takes the bound it documents and no more.
    @Test
    func theSwipesToFindAndToReachShareOneBudget() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 3)
        #expect(search.seek(in: Self.list(["Motion"], from: 100)) == .swipe(.up))
        let found = Self.list(["Classic Invert"], from: 800)
        #expect(search.seek(in: found) == .found)
        let target = try #require(Self.target("Classic Invert", in: found))

        let moves = [700.0, 600, 500].map { search.reach(target, at: target.node.frame, in: Self.list(["Classic Invert"], from: $0), hittable: false) }

        guard case let .stopped(stop, reason) = moves.last else {
            Issue.record("expected the swipes to run out, got \(moves)")
            return
        }
        #expect(moves.dropLast() == [.swipe(.up), .swipe(.up)])
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

        #expect(moves.filter { $0 == .swipe(.up) }.count == 3)
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
        #expect(search.seek(in: Self.list(["Motion"], from: 100)) == .swipe(.up))
        let found = Self.list(["Classic Invert"], from: 800)
        #expect(search.seek(in: found) == .found)

        let target = try #require(Self.target("Classic Invert", in: found))

        #expect(search.reach(target, at: target.node.frame, in: found, hittable: false) == .swipe(.up))
    }

    /// A hittable element is arrived at without a swipe.
    @Test
    func aHittableElementIsFoundAtOnce() throws {
        var search = ScrollSearch(label: "Classic Invert", limit: 12)
        let tree = Self.list(["Classic Invert"], from: 100)

        let target = try #require(Self.target("Classic Invert", in: tree))

        #expect(search.reach(target, at: target.node.frame, in: tree, hittable: true) == .found)
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
            swipe: { _ in swipes += 1 }
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
            swipe: { _ in swipes += 1 }
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

        let result = try search.resolveSeeking(reaching: .control, resolve: { .none }, read: { screen }, swipe: { _ in })

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
            swipe: { _ in swipes += 1 }
        )

        #expect(result.choice == .none)
        #expect(result.stopped != nil)
        #expect(swipes == 3)
        #expect(search.swipes == 3)
    }

    /// **SimWalk#273**: `scrollTo 'Reset asked for'` chooses the text `Reset asked for. The PIN clears at 18:02 on Sun 25 Oct.` — a label that begins with the step's text and a sentence's end.
    @Test
    func aLabelBeginningWithTheStepsTextAndASentencesEndIsChosen() {
        let sentence = "Reset asked for. The PIN clears at 18:02 on Sun 25 Oct."
        let tree = Self.list(["Reset all settings", sentence], from: 100)

        #expect(Self.target("Reset asked for", in: tree)?.node.label == sentence)
        #expect(Self.target("Reset asked for", in: tree)?.match == .leadingSentence)
    }

    /// An arbitrary prefix still does not match: `Reset` is not the start of `Reset all settings` in any way a step reads.
    @Test
    func aBareWordDoesNotReachALongerLabelItBegins() {
        #expect(Self.target("Reset", in: Self.list(["Reset all settings"], from: 100)) == nil)
    }

    /// A miss lists the labels that contain the step's text, the first that starts with it carrying the rule, each cut to 60 characters (SimWalk#273).
    @Test
    func aMissNamesTheNearestLabelsAndHowEachCompared() {
        var search = ScrollSearch(label: "Reset asked", limit: 12)
        let long = "Please note that the Reset asked for earlier is still pending approval"
        let tree = Self.list(["Reset asked for. The PIN clears at 18:02 on Sun 25 Oct.", "RESET ASKED", "Reset asked again", long, "General"], from: 100)
        _ = search.seek(in: tree)

        guard case let .stopped(_, reason) = search.seek(in: tree) else {
            Issue.record("expected a stop")
            return
        }

        #expect(reason == "nothing on screen is labelled or identified 'Reset asked'; nearest: "
            + "'Reset asked for. The PIN clears at 18:02 on Sun 25 Oct.' (starts with it, but a step matches the start of a label only up to a comma, a sentence's end, or a space before a number), "
            + "'RESET ASKED' (differs in case), 'Reset asked again' (starts with it): "
            + "swiped up once and the last swipe moved nothing — the list is at its end, or nothing here scrolls")
    }

    /// A label that starts with the step's text only when case is ignored is `(differs in case)`, not explained by the comma rule (SimWalk#273 review).
    @Test
    func aLabelStartingWithTheTextIgnoringCaseDiffersInCase() {
        var search = ScrollSearch(label: "Reset asked for", limit: 12)
        let tree = Self.list(["reset asked for, 3"], from: 100)
        _ = search.seek(in: tree)

        guard case let .stopped(_, reason) = search.seek(in: tree) else {
            Issue.record("expected a stop")
            return
        }

        #expect(reason.contains("; nearest: 'reset asked for, 3' (differs in case): "))
    }

    /// A label past 60 characters is cut with `…` at 60, and one that merely contains the text reads `(contains it)`.
    @Test
    func aLongNearestLabelIsCutToSixtyCharacters() {
        var search = ScrollSearch(label: "Reset asked", limit: 12)
        let long = "Please note that the Reset asked for earlier is still pending approval"
        let tree = Self.list([long], from: 100)
        _ = search.seek(in: tree)

        guard case let .stopped(_, reason) = search.seek(in: tree) else {
            Issue.record("expected a stop")
            return
        }

        #expect(reason.contains("; nearest: '\(long.prefix(59))…' (contains it): "))
    }

    /// **A home screen left scrolled to its foot (SimWalk#280)**: its `Partitioning` button is in the tree above the visible part of the list, under the pinned header, so the step swipes down to it rather than up into the list's end.
    @Test
    func anElementAboveTheVisiblePartOfItsListIsSwipedDownTo() throws {
        var search = ScrollSearch(label: "Partitioning", limit: 12)
        let above = Self.pinnedHome(partitioningAt: 71)
        let target = try #require(Self.target("Partitioning", in: above))

        #expect(search.reach(target, at: target.node.frame, in: above, hittable: false) == .swipe(.down))
        let below = Self.pinnedHome(partitioningAt: 500)
        #expect(search.reach(target, at: AXNode.Frame(x: 162, y: 500, width: 78, height: 82), in: below, hittable: true) == .found)
        #expect(search.swipes == 1)
    }

    /// A swipe down that moves nothing reached the list's start, and the refusal says so, with the direction it swiped.
    @Test
    func aSwipeDownThatMovesNothingStopsAtTheStartOfTheList() throws {
        var search = ScrollSearch(label: "Partitioning", limit: 12)
        let tree = Self.pinnedHome(partitioningAt: 71)
        let target = try #require(Self.target("Partitioning", in: tree))

        #expect(search.reach(target, at: target.node.frame, in: tree, hittable: false) == .swipe(.down))
        #expect(search.reach(target, at: target.node.frame, in: tree, hittable: false) == .stopped(
            .endOfList,
            reason: "a Button labelled 'Partitioning' never came within reach of a tap: swiped down once and the last swipe moved nothing — the list is at its start, or nothing here scrolls"
        ))
    }

    /// A step that swiped both ways says how many each, and which end it stopped at.
    @Test
    func swipesBothWaysAreCountedApart() throws {
        var search = ScrollSearch(label: "Partitioning", limit: 12)
        let tree = Self.pinnedHome(partitioningAt: 71)
        let target = try #require(Self.target("Partitioning", in: tree))
        let overshot = Self.pinnedHome(partitioningAt: 840)

        #expect(search.reach(target, at: target.node.frame, in: tree, hittable: false) == .swipe(.down))
        #expect(search.reach(target, at: AXNode.Frame(x: 162, y: 840, width: 78, height: 82), in: overshot, hittable: false) == .swipe(.up))
        #expect(search.reach(target, at: AXNode.Frame(x: 162, y: 840, width: 78, height: 82), in: overshot, hittable: false) == .stopped(
            .endOfList,
            reason: "a Button labelled 'Partitioning' never came within reach of a tap: swiped up once and down once and the last swipe moved nothing — the list is at its end, or nothing here scrolls"
        ))
    }

    /// Down only for an element wholly above the visible top of its own scroll container, clipped to the screen; partly above, it is swiped up as before.
    @Test
    func theDirectionIsDownOnlyForAnElementWhollyAboveTheVisibleTop() {
        let button = AXNode(type: "Button", frame: AXNode.Frame(x: 162, y: 71, width: 78, height: 82), label: "Partitioning", identifier: "play.fill")
        let partlyAbove = AXNode.Frame(x: 162, y: 250, width: 78, height: 82)
        #expect(ScrollSearch.direction(towards: button, at: partlyAbove, in: Self.pinnedHome(partitioningAt: 250)) == .up)
        // A container reaching above the screen: the visible top is the screen's, so a row at y -60 is above it.
        let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let offTop = AXNode.Frame(x: 0, y: -60, width: 100, height: 44)
        let row = AXNode(type: "Cell", frame: offTop, label: "Up")
        let tall = AXNode(type: "Application", frame: screen, children: [
            AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: -200, width: 402, height: 1074), children: [row]),
        ])
        #expect(ScrollSearch.direction(towards: row, at: offTop, in: tall) == .down)
    }

    /// **SimWalk#241's sheet**: a row the table has not laid out is read at the scroll view's top corner, inside the visible part, so it is swiped up to as it always was, never down over a sheet at its start.
    @Test
    func aRowReadAtTheTablesCornerBeforeItWasLaidOutIsSwipedUpTo() throws {
        var search = ScrollSearch(label: "About NetNewsWire", limit: 12)
        let placeholder = AXNode.Frame(x: 0, y: 117, width: 308, height: 52)
        let screen = AXNode.Frame(x: 0, y: 0, width: 390, height: 844)
        let sheet = AXNode(type: "Application", frame: screen, children: [
            AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 47, width: 390, height: 797), children: [
                AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 47, width: 390, height: 70)),
                AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 117, width: 390, height: 727), children: [
                    AXNode(type: "Cell", frame: AXNode.Frame(x: 16, y: 401, width: 358, height: 52), label: "Dinosaurs"),
                    AXNode(type: "Cell", frame: placeholder, label: "About NetNewsWire"),
                ]),
            ]),
        ])
        let target = try #require(Self.target("About NetNewsWire", in: sheet))

        #expect(search.reach(target, at: placeholder, in: sheet, hittable: false) == .swipe(.up))
    }

    /// The home screen as the #280 capture read it: a header pinned above a scroll view whose visible part is y 299–874, and a `Partitioning` button in it at `y`.
    private static func pinnedHome(partitioningAt y: Double) -> AXNode {
        let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        let button = AXNode(type: "Button", frame: AXNode.Frame(x: 162, y: y, width: 78, height: 82), label: "Partitioning", identifier: "play.fill")
        let content = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: y - 395, width: 402, height: 1164), children: [button])
        let list = AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 299, width: 402, height: 575), children: [content])
        let header = AXNode(type: "StaticText", frame: AXNode.Frame(x: 286, y: 186, width: 100, height: 29), label: "Today: 0")
        return AXNode(type: "Application", frame: screen, children: [header, list])
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
