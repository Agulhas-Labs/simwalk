//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// What the runner binds when the element a step chose is not where the snapshot recorded it (`RouteTarget.Choice.rebinding`), and how it checks an element it has bound is still that element (`RouteTarget.Candidate.isStill`).
///
/// A `{n}` pattern or a lead-in is bound by the label it was read with, and those labels are the ones that tick; the label is chosen again, and only the same element is bound without a word. A literal match's miss stays final.
struct RouteTargetRebindingTests {
    /// A chip whose count ticks between the read and the bind is the same element at its new count — the same place in the tree — and is bound as it now reads: the label `{n}` exists for is exactly the one that moves on.
    @Test
    func apatternWhoseLabelTickedBeforeTheBindIsTheSameElementAtItsNewCount() {
        let before = Self.screen([AXNode(type: "Button", frame: AXNode.Frame(x: 156, y: 401, width: 81, height: 45), label: "Sailing 22")])
        let after = Self.screen([AXNode(type: "Button", frame: AXNode.Frame(x: 156, y: 401, width: 88, height: 45), label: "Sailing 23")])

        let rebinding = RouteTarget.choose(labelled: "Sailing {n}", in: before).rebinding(labelled: "Sailing {n}", in: after)

        guard case let .same(fresh) = rebinding, case let .chosen(target, _) = fresh else {
            Issue.record("expected the chip at its new count, got \(rebinding)")
            return
        }

        #expect(target.node.label == "Sailing 23")
        #expect(target.match == .pattern)
    }

    /// A lead-in whose data ticked is the same element too.
    @Test
    func aleadInWhoseDataTickedIsTheSameElement() {
        let before = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: "Updated 3 min ago")])
        let ticked = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: "Updated 4 min ago")])

        guard case let .same(fresh) = RouteTarget.choose(labelled: "Updated", in: before).rebinding(labelled: "Updated", in: ticked),
              case let .chosen(target, _) = fresh
        else {
            Issue.record("expected the same row")
            return
        }

        #expect(target.node.label == "Updated 4 min ago")
    }

    /// **A different element is never bound silently** — not even a row matching literally that has just arrived.
    ///
    /// The lead-in was acted on because the lookup ran out with nothing literal in it; a literal row arriving after that is not what the tracker chose, and binding it would act on an element nothing settled on. The step looks again, and a second different answer is refused, naming both.
    @Test
    func aliteralRowThatArrivedAfterTheLookupIsADifferentElementNotARebind() {
        let before = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: "Updated 3 min ago")])
        let arrived = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Updated 4 min ago"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Updated"),
        ])
        let choice = RouteTarget.choose(labelled: "Updated", in: before)

        let first = choice.rebinding(labelled: "Updated", in: arrived)
        let second = choice.rebinding(to: RouteTarget.choose(labelled: "Updated", in: arrived))

        guard case let .different(from, to) = second else {
            Issue.record("expected a different element, got \(second)")
            return
        }

        #expect(first == second)
        #expect(from.node.label == "Updated 3 min ago")
        #expect(to.node.label == "Updated")
        #expect(second.reason == "a Button labelled 'Updated 3 min ago' moved before it could be bound, and reading the screen again chose a different element, a Button labelled 'Updated' — a step never acts on an element it did not choose")
    }

    /// A literal row inserted above the lead-in's row takes the lead-in's place in the tree — and still is not the lead-in's row moved on, because it is matched another way.
    @Test
    func aliteralRowInsertedAtTheLeadInsPlaceIsStillADifferentElement() {
        let before = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: "Updated 3 min ago")])
        let inserted = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Updated"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Updated 4 min ago"),
        ])

        guard case let .different(_, to) = RouteTarget.choose(labelled: "Updated", in: before).rebinding(labelled: "Updated", in: inserted) else {
            Issue.record("expected a different element")
            return
        }

        #expect(to.path == [0, 0])
    }

    /// A neighbour that moved into the gap — another chip the pattern reaches, at a different place in the tree — is a different element too, though it matches in the very same way.
    @Test
    func aneighbourThePatternAlsoReachesIsADifferentElement() {
        let before = Self.screen([
            AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 401, width: 81, height: 45), label: "All 4"),
            AXNode(type: "Button", frame: AXNode.Frame(x: 156, y: 401, width: 81, height: 45), label: "Sailing 22"),
        ])
        let after = Self.screen([AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 401, width: 81, height: 45), label: "Sailing 22")])

        guard case .different = RouteTarget.choose(labelled: "Sailing {n}", in: before).rebinding(labelled: "Sailing {n}", in: after) else {
            Issue.record("expected a different element")
            return
        }
    }

    /// Once the tracker has settled on the step's label again, the same element is bound, whatever it now reads.
    @Test
    func thetrackersSecondLookBindsTheSameElement() {
        let before = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 400, height: 45), label: "Sailing 22")])
        let settled = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 400, height: 45), label: "Sailing 24")])
        let choice = RouteTarget.choose(labelled: "Sailing {n}", in: before)

        guard case .same = choice.rebinding(to: RouteTarget.choose(labelled: "Sailing {n}", in: settled)) else {
            Issue.record("expected the same element")
            return
        }
    }

    /// **The reach is kept**: a `type` step's second look is still among fields, so it never lands on the button beside the field that carries the same label — a `typeText` on which would be an XCTest failure, failing the walk.
    @Test
    func atypeStepsSecondLookIsStillAmongFields() {
        let before = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100, height: 44), label: "Notes 3"),
            AXNode(type: "TextField", frame: Self.frame(y: 200, height: 44), label: "Notes 3"),
        ])
        let after = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100, height: 44), label: "Notes 4"),
            AXNode(type: "TextField", frame: Self.frame(y: 200, height: 44), label: "Notes 4"),
        ])

        let rebinding = RouteTarget.choose(labelled: "Notes {n}", in: before, reaching: .textEntry).rebinding(labelled: "Notes {n}", in: after)

        guard case let .same(fresh) = rebinding, case let .chosen(target, _) = fresh else {
            Issue.record("expected the field at its new count, got \(rebinding)")
            return
        }

        #expect(target.node.type == "TextField")
        #expect(target.reach == .textEntry)
    }

    /// A literal match is not chosen again: it is bound at the live predicate's index and checked by frame, so a miss means it moved, and the step says so as it always did.
    @Test
    func aliteralMatchThatMissedIsNotChosenAgain() {
        let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 745, height: 45), label: "Sailing, Wednesday · 1.48 km in 8 min, 1")])

        #expect(RouteTarget.choose(labelled: "Sailing", in: tree).rebinding(labelled: "Sailing", in: tree) == .final)
        #expect(RouteTarget.Choice.none.rebinding(labelled: "Sailing", in: tree) == .final)
    }

    /// A fresh read that finds nothing, or a tie between lead-ins, leaves the miss standing rather than acting on something the tracker never saw.
    @Test
    func afreshReadThatChoosesNothingLeavesTheMissStanding() {
        let chip = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 400, height: 45), label: "Sailing 22")])
        let gone = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 400, height: 45), label: "All 4")])
        let row = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 07:10 · 5.10 km")])
        let tied = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 07:10 · 5.10 km"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Sail, 12 August 18:30 · 3.20 km"),
        ])

        #expect(RouteTarget.choose(labelled: "Sailing {n}", in: chip).rebinding(labelled: "Sailing {n}", in: gone) == .final)
        #expect(RouteTarget.choose(labelled: "Sail, 12 August", in: row).rebinding(labelled: "Sail, 12 August", in: tied) == .final)
        #expect(RouteTarget.Rebinding.final.reason == nil)
    }

    // MARK: - A bound element, read again while scrolling

    /// A scroll moves an element up or down the screen: the same label at the same width and height, anywhere vertically, is still the element chosen.
    @Test
    func anElementAScrollMovedUpTheScreenIsStillTheOneChosen() throws {
        let target = try #require(Self.candidate(labelled: "Trend", in: Self.screen([AXNode(type: "Button", frame: Self.frame(y: 1400), label: "Trend")])))

        #expect(target.isStill(label: "Trend", identifier: nil, frame: Self.frame(y: 700)))
        #expect(target.isStill(label: "Trend", identifier: nil, frame: Self.frame(y: 1400)))
    }

    /// A bound index that names a later row once a lazy list recycles the ones above is caught by the label, or by a size a scroll does not change.
    @Test
    func anElementWhoseLabelOrSizeChangedIsNotTheOneChosen() throws {
        let target = try #require(Self.candidate(labelled: "Trend", in: Self.screen([AXNode(type: "Button", frame: Self.frame(y: 1400), label: "Trend")])))

        #expect(!target.isStill(label: "Trend, 12 August", identifier: nil, frame: Self.frame(y: 700)))
        #expect(!target.isStill(label: nil, identifier: "Trend", frame: Self.frame(y: 700)))
        #expect(!target.isStill(label: "Trend", identifier: nil, frame: AXNode.Frame(x: 0, y: 700, width: 380, height: 60)))
        #expect(!target.isStill(label: "Trend", identifier: nil, frame: AXNode.Frame(x: 0, y: 700, width: 402, height: 44)))
    }

    /// SimWalk#241: a row read before it was laid out, at a placeholder origin, is still the one chosen once a swipe brings it on screen.
    ///
    /// A sheet's table builds its rows before they scroll into view and reports one not yet laid out at its scroll view's corner; on screen the same row sits inset, at the same size. That is still the row chosen, or a `scrollTo` loses it on its first swipe where a `tap` reaches it.
    @Test
    func aRowReadBeforeItWasLaidOutIsStillTheOneChosenOnceOnScreen() throws {
        let placeholder = AXNode.Frame(x: 0, y: 117, width: 308, height: 52)
        let sheet = Self.screen([
            AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 47, width: 390, height: 797), children: [
                AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 47, width: 390, height: 70), children: [
                    AXNode(type: "Button", frame: AXNode.Frame(x: 334, y: 67, width: 36, height: 36), label: "Done"),
                ]),
                AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 117, width: 390, height: 727), children: [
                    AXNode(type: "Cell", frame: AXNode.Frame(x: 16, y: 401, width: 358, height: 52), children: [
                        AXNode(type: "StaticText", frame: AXNode.Frame(x: 32, y: 401, width: 308, height: 52), label: "Dinosaurs"),
                    ]),
                    AXNode(type: "Cell", frame: placeholder, children: [
                        AXNode(type: "StaticText", frame: placeholder, label: "About NetNewsWire"),
                    ]),
                ]),
            ]),
        ])
        let target = try #require(Self.candidate(labelled: "About NetNewsWire", in: sheet))

        #expect(target.node.frame == placeholder)
        #expect(target.isStill(label: "About NetNewsWire", identifier: nil, frame: AXNode.Frame(x: 32, y: 609, width: 308, height: 52)))
    }

    /// An element chosen by its identifier is held to that identifier, whatever its label reads.
    @Test
    func anElementChosenByItsIdentifierIsHeldToIt() throws {
        let target = try #require(Self.candidate(labelled: "trend-card", in: Self.screen([AXNode(type: "Button", frame: Self.frame(y: 1400), label: "Trend, 3 of 4", identifier: "trend-card")])))

        #expect(target.isStill(label: "Trend, 4 of 4", identifier: "trend-card", frame: Self.frame(y: 700)))
        #expect(!target.isStill(label: "Trend, 3 of 4", identifier: "other-card", frame: Self.frame(y: 700)))
    }

    private static func candidate(labelled label: String, in tree: AXNode) -> RouteTarget.Candidate? {
        guard case let .chosen(candidate, _) = RouteTarget.choose(labelled: label, in: tree, reaching: .anything) else { return nil }
        return candidate
    }

    private static func screen(_ content: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: frame(y: 0, height: 874), children: [
            AXNode(type: "Window", frame: frame(y: 0, height: 874), children: content),
        ])
    }

    private static func frame(y: Double, height: Double = 60) -> AXNode.Frame {
        AXNode.Frame(x: 0, y: y, width: 402, height: height)
    }
}
