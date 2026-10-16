//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// How a route step reaches a label that carries data: by naming the data's place with `{n}` (SimWalk#13), or — as a last resort — by the lead-in to it (SimWalk#9).
///
/// The rule every test here holds the resolver to: **nothing that resolved before resolves differently.** A `{n}` pattern and a lead-in are each consulted only where the answer used to be nothing, so each test pits them against the matches that would have won without them — a whole label, a leading component, across kinds — and the specimens are shaped like the real screens where the looser first cut picked the wrong element.
struct RouteTargetDataLabelTests {
    // MARK: - `{n}`: a data-carrying label, addressed on purpose

    /// SimWalk#13: the Workouts filter chip `Sailing 1` has no label free of its count, and `'Sailing {n}'` reaches it — on a screen that also has the *By sport* row `Sailing, …`, which is what a bare `'Sailing'` means.
    ///
    /// Not settled on the first read, though it is a control, and not taken once the screen holds still either: a pattern is what the step found while nothing matched literally, so it is taken only once the lookup has run out with nothing literal found (`RouteTargetTracker`), in case an element that does is still arriving.
    @Test
    func aplaceholderReachesTheFilterChipBesideTheBySportRowThatSharesItsWord() {
        let choice = RouteTarget.choose(labelled: "Sailing {n}", in: Self.workoutsScreen())

        guard case let .chosen(target, all) = choice else {
            Issue.record("expected the chip, got \(choice)")
            return
        }

        #expect(target.node.label == "Sailing 1")
        #expect(target.node.type == "Button")
        #expect(target.match == .pattern)
        #expect(target.index == nil)
        #expect(all.count == 1)
        #expect(!choice.isSettled)
        #expect(!choice.acceptsOnceStill)
        #expect(!choice.matchedLiterally)
    }

    /// The same step keeps reaching the chip when the store changes its count — which is the whole point of not writing the count.
    @Test
    func aplaceholderReachesTheChipWhateverItsCountReads() {
        for count in ["1", "22", "1,234"] {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 400, height: 45), label: "Sailing \(count)")])

            guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Sailing {n}", in: tree) else {
                Issue.record("expected 'Sailing {n}' to reach 'Sailing \(count)'")
                continue
            }

            #expect(target.node.label == "Sailing \(count)")
        }
    }

    /// A bare `'Sailing'` resolves exactly as it did before either fix: to the *By sport* row, a whole leading component — not to the chip, and not to the text `Sailing` inside the row.
    ///
    /// Also pins what `index` means: the row is the first element the runner's live predicate returns for `'Sailing'`, so it binds at 0. The chip before it in tree order is no match at all, where the first cut counted it and bound the row at 1.
    @Test
    func abareSportNameStillReachesTheBySportRowAtTheIndexTheLiveQueryHasIt() {
        let choice = RouteTarget.choose(labelled: "Sailing", in: Self.workoutsScreen())

        guard case let .chosen(target, all) = choice else {
            Issue.record("expected the By-sport row, got \(choice)")
            return
        }

        #expect(target.node.label == "Sailing, Wednesday · 1.48 km in 8 min, 1")
        #expect(target.match == .leadingComponent)
        #expect(target.index == 0)
        #expect(all.map(\.node.type) == ["Button", "StaticText"])
        #expect(all.map(\.index) == [0, 1])
    }

    /// `{n}` stands for one number — digits, perhaps signed (a plus, a hyphen, or the minus sign iOS formatters draw), perhaps grouped or with a decimal point — and the rest of the label must match to the letter: it is a whole-label match with the number left open, not a looser prefix.
    @Test
    func aplaceholderStandsForOneNumberAndTheRestMustMatchWhole() {
        let matches: [(String, String)] = [
            ("Distance {n} km", "Distance 3.43 km"),
            ("{n} km", "+0.62 km"),
            ("{n} km", "-0.62 km"),
            ("{n} km", "−0.62 km"),
            ("Week {n} of {n}", "Week 3 of 12"),
        ]
        let misses: [(String, String)] = [
            ("Sailing {n}", "Sailing Total"),
            ("Sailing {n}", "Sailing 22 today"),
            ("Sailing {n}", "Sailing, Wednesday · 1.48 km in 8 min, 1"),
            ("Sailing {n}", "Walking 22"),
            ("{n} km", "km"),
        ]

        for (step, label) in matches {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: step, in: tree) != .none, "'\(step)' should reach '\(label)'")
        }
        for (step, label) in misses {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: step, in: tree) == .none, "'\(step)' should not reach '\(label)'")
        }
    }

    /// A label that really does read `{n}` is what a step reading `'Week {n}'` reached before the placeholder existed, and it still is — ahead of a pattern match earlier in tree order, and bound at the index the live predicate has it at.
    @Test
    func alabelThatLiterallyReadsThePlaceholderBeatsAPatternMatchBeforeIt() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "Week 3"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Week {n}"),
        ])

        let choice = RouteTarget.choose(labelled: "Week {n}", in: tree)

        guard case let .chosen(target, all) = choice else {
            Issue.record("expected the literal label, got \(choice)")
            return
        }

        #expect(target.node.label == "Week {n}")
        #expect(target.match == .label)
        #expect(target.index == 0)
        #expect(all.count == 1)
        #expect(choice.isSettled)
    }

    /// **The placeholder is a tier below every literal match, not a rank beside a whole label**: a text that literally reads `Week {n}` beats a button `Week 3` the pattern reaches, although a button outranks a text in any one tier.
    @Test
    func aliteralMatchOnContentBeatsAPatternMatchOnAControl() {
        let tree = Self.screen([
            AXNode(type: "StaticText", frame: Self.frame(y: 100, height: 20), label: "Week {n}"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Week 3"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Week {n}", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.type == "StaticText")
        #expect(target.match == .label)
    }

    /// And a leading component that literally reads `Week {n}, …` beats the pattern too — a leading component is literal, so the pattern does not even rank beside it, let alone take a tie by coming first in tree order.
    @Test
    func aleadingComponentThatLiterallyReadsThePlaceholderBeatsAPatternMatch() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "Week 3"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Week {n}, summary"),
        ])

        guard case let .chosen(target, all) = RouteTarget.choose(labelled: "Week {n}", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.label == "Week {n}, summary")
        #expect(target.match == .leadingComponent)
        #expect(target.index == 0)
        #expect(all.count == 1)
    }

    // MARK: - A lead-in: the last resort

    /// SimWalk#9: a composed row label that runs from its date straight into its time has no comma to end a leading component on, and the lead-in reaches it — only because nothing else on screen matches.
    @Test
    func aleadInToARowsDataReachesItWhenNothingElseMatches() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 14:50 · 3.43 km, 12 min"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Walk, 11 August 08:53 · 1.07 km, 12 min"),
        ])

        let choice = RouteTarget.choose(labelled: "Sail, 12 August", in: tree)

        guard case let .chosen(target, _) = choice else {
            Issue.record("expected the row, got \(choice)")
            return
        }

        #expect(target.node.label == "Sail, 12 August 14:50 · 3.43 km, 12 min")
        #expect(target.match == .prefix)
        #expect(target.index == nil)
        #expect(!choice.isSettled)
        #expect(!choice.acceptsOnceStill)
    }

    /// Whitespace of any width, a `·`, and runs of them all separate words from figures — iOS formatters draw non-breaking and thin spaces — so long as a digit follows.
    @Test
    func aleadInCrossesAnyRunOfSeparatorsThatEndsInADigit() {
        let cases: [(String, String)] = [
            ("Sail, 12 August 14:50", "Sail, 12 August 14:50 · 3.43 km, 12 min"),
            ("Sailing", "Sailing\u{00A0}22"),
            ("Training time", "Training time\u{2009}·\u{2009}11 August"),
        ]

        for (step, label) in cases {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            guard case let .chosen(target, _) = RouteTarget.choose(labelled: step, in: tree) else {
                Issue.record("'\(step)' should lead into '\(label)'")
                continue
            }
            #expect(target.match == .prefix)
        }
    }

    /// The review's field case: on the Progress screen `tap 'Heart Rate'` used to come back UNREACHABLE, honestly, and must go on doing so — `Heart Rate Variability` is a different named thing, and a space followed by a word is not data.
    @Test
    func aleadInNeverReachesADifferentNamedThingThatSharesItsWords() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 300), label: "Heart Rate Variability, Up 17 ms on the previous day, 75 ms"),
            AXNode(type: "Button", frame: Self.frame(y: 400), label: "Resting Heart Rate, 58 bpm"),
        ])

        #expect(RouteTarget.choose(labelled: "Heart Rate", in: tree) == .none)
        #expect(RouteTarget.choose(labelled: "Edit", in: Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: "Edit Profile")])) == .none)
    }

    /// The separator is not optional: a step ending partway through a word, or partway through a number, has pinned part of the data it meant to leave out.
    ///
    /// `'Sailing 2'` is not a lead-in to `'Sailing 22'`, and `'Distance 3'` is not one to `'Distance 3.43 km'` — the decimal point continues the number rather than ending it. **Nor does a comma end it**, which is why a comma is not a separator: `'Steps 4'` must not reach `'Steps 4,210'`, nor `'Distance 3'` a decimal comma's `'Distance 3,43 km'`; a comma that does end words is followed by a space, and that is a leading component, matched literally before any lead-in.
    @Test
    func aleadInMustEndOnASeparatorNotInsideAWordOrANumber() {
        let misses: [(String, String)] = [
            ("Sailing 2", "Sailing 22"),
            ("Distance 3", "Distance 3.43 km"),
            ("Steps 4", "Steps 4,210"),
            ("Distance 3", "Distance 3,43 km"),
            ("Sail", "Sailing 22"),
            ("Sailing", "Sailing22"),
            ("Sailing", "Sailing Total"),
        ]

        for (step, label) in misses {
            let tree = Self.screen([AXNode(type: "Button", frame: Self.frame(y: 200), label: label)])
            #expect(RouteTarget.choose(labelled: step, in: tree) == .none, "'\(step)' should not lead into '\(label)'")
        }
    }

    /// A lead-in loses to an exact label of the same kind wherever it sits in tree order.
    @Test
    func aleadInNeverBeatsAWholeLabelOfTheSameKind() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "Steps 4,210"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Steps"),
        ])

        guard case let .chosen(target, all) = RouteTarget.choose(labelled: "Steps", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.label == "Steps")
        #expect(all.map(\.node.label) == ["Steps"])
    }

    /// A lead-in loses to a leading component of the same kind — the family the step already meant.
    @Test
    func aleadInNeverBeatsALeadingComponent() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "Sail, 12 August 14:50 · 3.43 km"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August, 3.43 km"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Sail, 12 August", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.label == "Sail, 12 August, 3.43 km")
        #expect(target.match == .leadingComponent)
    }

    /// **Across kinds too**: a lead-in on a control does not beat a whole label on content, because kind is ranked within a tier and a lead-in is a tier below everything.
    ///
    /// The review's probe: a StaticText `Sailing` beside the chip `Sailing 22`.
    @Test
    func aleadInOnAControlNeverBeatsAWholeLabelOnContent() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100, height: 45), label: "Sailing 22"),
            AXNode(type: "StaticText", frame: Self.frame(y: 200, height: 20), label: "Sailing"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Sailing", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.type == "StaticText")
        #expect(target.match == .label)
    }

    /// The review's other probe: a navigation bar's `Edit` — a bar control, a whole label — keeps the tap beside an in-screen `Edit Profile` and an in-screen `Edit 3`, neither of which it lost to before.
    @Test
    func anavigationBarsEditKeepsTheTapBesideInScreenButtonsThatBeginWithIt() {
        let tree = Self.screen([
            AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 330, y: 60, width: 60, height: 44), label: "Edit"),
            ]),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Edit Profile"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Edit 3"),
        ])

        guard case let .chosen(target, all) = RouteTarget.choose(labelled: "Edit", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.insideBar == "NavigationBar")
        #expect(target.node.label == "Edit")
        #expect(all.count == 1)
    }

    /// Two rows the lead-in reaches equally are refused, named, rather than guessed between — unlike a tie on a leading component, which keeps meaning "the first of a family".
    @Test
    func twoRowsALeadInReachesEquallyAreRefusedAndNamed() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 07:10 · 5.10 km"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Sail, 12 August 18:30 · 3.20 km"),
        ])

        let choice = RouteTarget.choose(labelled: "Sail, 12 August", in: tree)

        guard case let .ambiguous(candidates) = choice else {
            Issue.record("expected a refusal, got \(choice)")
            return
        }

        #expect(candidates.count == 2)
        #expect(!choice.isSettled)
        #expect(choice.reason(for: "Sail, 12 August") == "'Sail, 12 August' only begins the labels of 2 elements, equally, and names none of them outright: a Button labelled 'Sail, 12 August 07:10 · 5.10 km'; a Button labelled 'Sail, 12 August 18:30 · 3.20 km'")
    }

    /// A wrapper and the text inside it, sharing a label and a frame, are one thing on screen: they count once, and the step is not refused over a tie with itself.
    @Test
    func awrapperAndItsChildSharingALabelAndFrameAreOneSpotNotATie() {
        let spot = Self.frame(y: 855, height: 14)
        let tree = Self.screen([
            AXNode(type: "Other", frame: spot, label: "Pace 5:12 /km", children: [
                AXNode(type: "StaticText", frame: spot, label: "Pace 5:12 /km"),
            ]),
        ])

        let choice = RouteTarget.choose(labelled: "Pace", in: tree)

        guard case let .chosen(target, all) = choice else {
            Issue.record("expected one spot, got \(choice)")
            return
        }

        #expect(target.node.type == "Other")
        #expect(all.count == 2)
    }

    /// Two siblings with one label at one frame — real trees duplicate an element this way, as the Workouts screen's scroll bar is — are one spot too.
    @Test
    func twoSiblingsWithOneLabelAtOneFrameAreOneSpotNotATie() {
        let spot = Self.frame(y: 116, height: 675)
        let tree = Self.screen([
            AXNode(type: "Other", frame: spot, label: "Vertical scroll bar, 2 pages"),
            AXNode(type: "Other", frame: spot, label: "Vertical scroll bar, 2 pages"),
        ])

        let choice = RouteTarget.choose(labelled: "Vertical scroll bar,", in: tree)

        guard case .chosen = choice else {
            Issue.record("expected one spot, got \(choice)")
            return
        }
    }

    /// What makes two candidates one spot is the label *and* the place: an element and one drawn inside it, or two at one frame, that carry **different** labels the lead-in reaches equally are two things to tap, and refused as a tie.
    ///
    /// A group row whose summary names one session and whose inset button names another, and two readings stacked at one frame, are each two answers to `'Sail, 12 August'` — folding either pair into its first would tap a session the step never chose between.
    @Test
    func elementsAtOneSpotWithDifferentLabelsAreStillATie() {
        let nested = Self.screen([
            AXNode(type: "Cell", frame: Self.frame(y: 200, height: 90), label: "Sail, 12 August 07:10 · 5.10 km", children: [
                AXNode(type: "Button", frame: Self.frame(y: 250, height: 30), label: "Sail, 12 August 18:30 · 3.20 km"),
            ]),
        ])
        let stacked = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 07:10 · 5.10 km"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 18:30 · 3.20 km"),
        ])

        for tree in [nested, stacked] {
            let choice = RouteTarget.choose(labelled: "Sail, 12 August", in: tree)
            guard case let .ambiguous(candidates) = choice else {
                Issue.record("expected a refusal, got \(choice)")
                continue
            }
            #expect(candidates.count == 2)
        }
    }

    /// A table cell and the button inset inside it carry one label at two frames, as every row of Settings' *About* screen does — still one element, so a lead-in to it is taken rather than refused as a tie with itself.
    @Test
    func acellAndTheButtonInsetInItAreOneElementForALeadIn() {
        let tree = Self.screen([
            AXNode(type: "Cell", frame: Self.frame(y: 186, height: 53), label: "iOS Version, 26.5", children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 203, width: 370, height: 20), label: "iOS Version, 26.5"),
            ]),
            AXNode(type: "Cell", frame: Self.frame(y: 239, height: 53), label: "Model Name, iPhone 17 Pro"),
        ])

        let choice = RouteTarget.choose(labelled: "iOS Version,", in: tree)

        guard case let .chosen(target, all) = choice else {
            Issue.record("expected the cell, got \(choice)")
            return
        }

        #expect(target.node.type == "Cell")
        #expect(all.count == 2)
    }

    /// a Workouts screen as a mid-August capture read it, cut to the part that matters: the filter chips, one session row, and the *By sport* rows whose labels begin with the chips' words.
    ///
    /// None of the chips carries an identifier, so no identifier route reaches one either.
    private static func workoutsScreen() -> AXNode {
        screen([
            AXNode(type: "ScrollView", frame: frame(y: 0, height: 874), identifier: "WorkoutsScreen", children: [
                AXNode(type: "StaticText", frame: frame(y: 379, height: 12), label: "Sessions, Most recent first"),
                AXNode(type: "Button", frame: AXNode.Frame(x: 21, y: 401, width: 49, height: 45), label: "All 4"),
                AXNode(type: "Button", frame: AXNode.Frame(x: 75, y: 401, width: 76, height: 45), label: "Cycling 2"),
                AXNode(type: "Button", frame: AXNode.Frame(x: 156, y: 401, width: 81, height: 45), label: "Sailing 1"),
                AXNode(type: "Button", frame: AXNode.Frame(x: 242, y: 401, width: 78, height: 45), label: "Walking 1"),
                AXNode(type: "Button", frame: frame(y: 560, height: 55), label: "Sail, Wednesday 07:42 · 1.48 km, 8 min", identifier: "sessionRow", children: [
                    AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 572, width: 27, height: 16), label: "Sail"),
                ]),
                AXNode(type: "StaticText", frame: frame(y: 686, height: 12), label: "By sport, 3 sports"),
                AXNode(type: "Button", frame: frame(y: 700, height: 45), label: "Cycling, Saturday · 4.74 km in 18 min, 2", children: [
                    AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 707, width: 51, height: 16), label: "Cycling"),
                ]),
                AXNode(type: "Button", frame: frame(y: 745, height: 45), label: "Sailing, Wednesday · 1.48 km in 8 min, 1", children: [
                    AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 752, width: 57, height: 16), label: "Sailing"),
                ]),
            ]),
            AXNode(type: "TabBar", frame: frame(y: 791, height: 83), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 110, y: 795, width: 95, height: 54), label: "Workouts"),
            ]),
        ])
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
