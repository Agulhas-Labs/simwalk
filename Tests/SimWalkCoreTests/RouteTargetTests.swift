//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Which element a `tap` acts on when its label is carried by more than one (SimWalk#17).
///
/// The specimen is an app's *Sleep* category landing on 2026-09-10: a navigation bar identified `Sleep`, a large title `Sleep`, and the row `Sleep, Nothing earlier to compare with` that opens the record — in that tree order, so the first match was the bar and the tap went nowhere.
struct RouteTargetTests {
    /// The field case: `tap 'Sleep'` reaches the row, not the navigation bar or the title it shares the word with.
    @Test
    func atapNamedForTheScreensTitleReachesTheRowNotTheNavigationBar() {
        let choice = RouteTarget.choose(labelled: "Sleep", in: Self.sleepLanding())

        guard case let .chosen(target, all) = choice else {
            Issue.record("expected the row to be chosen, got \(choice)")
            return
        }

        #expect(target.node.type == "Button")
        #expect(target.node.label == "Sleep, Nothing earlier to compare with")
        #expect(all.map(\.node.type) == ["NavigationBar", "StaticText", "Button"])
        #expect(target.index == 2)
        #expect(choice.isSettled)
    }

    /// A control outranks content, and within one kind a whole label outranks a leading component — so an author naming a button exactly gets that button even beside a row whose composed label begins with the same word.
    @Test
    func acontrolOutranksContentAndAWholeLabelOutranksAComponent() {
        let tree = Self.screen([
            AXNode(type: "StaticText", frame: Self.frame(y: 100), label: "Steps"),
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Steps, 4,210 today"),
            AXNode(type: "Button", frame: Self.frame(y: 300), label: "Steps"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Steps", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.label == "Steps")
        #expect(target.node.type == "Button")
    }

    /// A tie at the best rank goes to the first in tree order, as it always did — `tap 'Coastal Cruise'` on a list of rides means the newest, at the top — and when that tap does not land, the reason says it was a tie.
    ///
    /// Refusing ties was measured against an app's book and cost it two screens whose routes reach a list's head this way.
    @Test
    func atieAtTheBestRankGoesToTheFirstInTreeOrderAndSaysSoWhenItFails() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Coastal Cruise, 28 August · 18.93 km"),
            AXNode(type: "Button", frame: Self.frame(y: 300), label: "Coastal Cruise, 24 August · 22.08 km"),
            AXNode(type: "Button", frame: Self.frame(y: 400), label: "Coastal Cruise, 23 August · 13.05 km"),
        ])

        let choice = RouteTarget.choose(labelled: "Coastal Cruise", in: tree)

        guard case let .chosen(target, _) = choice else {
            Issue.record("expected a choice, got \(choice)")
            return
        }

        #expect(target.index == 0)
        #expect(choice.isSettled)
        #expect(choice.reason(for: "Coastal Cruise").contains("the first of 3 that ranked equally"))
        #expect(choice.reason(for: "Coastal Cruise").contains("it also matched a Button labelled 'Coastal Cruise, 24 August · 22.08 km'; a Button labelled 'Coastal Cruise, 23 August · 13.05 km'"))
    }

    /// A long list of identical other matches is counted, not recited.
    @Test
    func manyIdenticalOtherMatchesAreCountedNotRecited() {
        let titles = (0 ..< 18).map { AXNode(type: "StaticText", frame: Self.frame(y: Double(100 + $0 * 40), height: 20), label: "Coastal Cruise") }
        let tree = Self.screen([AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), identifier: "Coastal Cruise")] + titles)

        let reason = RouteTarget.choose(labelled: "Coastal Cruise", in: tree).reason(for: "Coastal Cruise")

        #expect(reason.contains("the first of 18 that ranked equally"))
        #expect(reason.contains("(it also matched a NavigationBar identified 'Coastal Cruise'; 17 × a StaticText labelled 'Coastal Cruise')"))
    }

    /// A cell and the button drawn inside it tie, and the outermost — first in tree order — is taken, as it always was.
    @Test
    func acellAndTheButtonInsideItAreOneTarget() {
        let tree = Self.screen([
            AXNode(type: "Cell", frame: Self.frame(y: 200, height: 80), label: "Sleep, 7h 12m", children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 24, y: 210, width: 300, height: 60), label: "Sleep, 7h 12m"),
            ]),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Sleep", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.type == "Cell")
        #expect(target.index == 0)
    }

    /// Where the only match is chrome it is still the answer — a tap on it is what the step asked for — but the UNREACHABLE it leads to names what matched, rather than reading like a missing route.
    @Test
    func alabelOnlyChromeCarriesIsTappedAndNamedWhenTheScreenDoesNotMove() {
        let tree = Self.screen([
            AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), identifier: "Sleep"),
        ])

        let choice = RouteTarget.choose(labelled: "Sleep", in: tree)

        #expect(!choice.isSettled)
        #expect(choice.reason(for: "Sleep") == "tapped a NavigationBar identified 'Sleep', and the screen did not change")
    }

    /// A key that did not land names both things checked (SimWalk#94): the screen and the focused field, or the absence of one.
    @Test
    func akeyThatDidNotLandNamesTheScreenAndTheFocusedField() {
        let tree = Self.screen([
            AXNode(type: "Key", frame: Self.frame(y: 600, height: 50), label: "0"),
        ])

        let choice = RouteTarget.choose(labelled: "0", in: tree)

        #expect(choice.keyReason(for: "0", fieldHadFocus: true) == "tapped a Key labelled '0', and neither the screen nor the focused field's value changed")
        #expect(choice.keyReason(for: "0", fieldHadFocus: false) == "tapped a Key labelled '0', and the screen did not change, and no field had keyboard focus")
    }

    /// A button inside a bar ranks with the bar (the SimWalk#17 review): the tab item `Workouts` is a whole-label control, and ranked as one it beat the row `Workouts, 18` — and the tab it switched to was captured under the screen's id, silently.
    @Test
    func abuttonInsideATabBarDoesNotOutrankARowCarryingTheSameWord() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 300), label: "Workouts, 18"),
            AXNode(type: "TabBar", frame: Self.frame(y: 790, height: 84), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 200, y: 800, width: 80, height: 50), label: "Workouts"),
            ]),
        ])
        let onlyTheTab = Self.screen([
            AXNode(type: "TabBar", frame: Self.frame(y: 790, height: 84), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 200, y: 800, width: 80, height: 50), label: "Workouts"),
            ]),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Workouts", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.label == "Workouts, 18")
        #expect(RouteTarget.choose(labelled: "Workouts", in: onlyTheTab).reason(for: "Workouts") == "tapped a Button labelled 'Workouts' in the TabBar, and the screen did not change")
    }

    /// A bar's own control still outranks content (the review's second pass): a toolbar's `Edit` beats a StaticText `Edit`, where ranking it with the bar handed the tap to the text.
    @Test
    func atoolbarsEditButtonBeatsAStaticTextCarryingTheSameWord() {
        let tree = Self.screen([
            AXNode(type: "StaticText", frame: Self.frame(y: 300), label: "Edit"),
            AXNode(type: "Toolbar", frame: Self.frame(y: 740, height: 50), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 745, width: 60, height: 40), label: "Edit"),
            ]),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Edit", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.type == "Button")
        #expect(target.insideBar == "Toolbar")
    }

    /// A disabled control is no better than chrome: it cannot take the tap.
    @Test
    func adisabledControlRanksWithChrome() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 100), label: "Export", isEnabled: false),
            AXNode(type: "StaticText", frame: Self.frame(y: 300), label: "Export"),
        ])

        guard case let .chosen(target, _) = RouteTarget.choose(labelled: "Export", in: tree) else {
            Issue.record("expected a choice")
            return
        }

        #expect(target.node.type == "StaticText")
    }

    /// Nothing carrying the label is said as such.
    @Test
    func nothingCarryingTheLabelSaysSo() {
        let choice = RouteTarget.choose(labelled: "Power", in: Self.sleepLanding())

        #expect(choice == .none)
        #expect(choice.reason(for: "Power") == "nothing on screen is labelled or identified 'Power'")
    }

    /// The root is never a candidate, because the live query the runner binds against asks for the application's *descendants* — counting it would shift every index by one.
    @Test
    func theapplicationItselfIsNeverACandidate() {
        #expect(RouteTarget.choose(labelled: "RouteFixture", in: Self.sleepLanding()) == .none)
    }

    /// an app's Sleep landing as the snapshot reads it: bar, title, row, tab bar — in that tree order.
    private static func sleepLanding() -> AXNode {
        AXNode(type: "Application", frame: frame(y: 0, height: 874), label: "RouteFixture", children: [
            AXNode(type: "Window", frame: frame(y: 0, height: 874), children: [
                AXNode(type: "NavigationBar", frame: frame(y: 54, height: 96), identifier: "Sleep", children: [
                    AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 60, width: 80, height: 44), label: "Browse"),
                    AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 104, width: 120, height: 41), label: "Sleep"),
                ]),
                AXNode(type: "ScrollView", frame: frame(y: 150, height: 640), children: [
                    AXNode(type: "Button", frame: frame(y: 200, height: 80), label: "Sleep, Nothing earlier to compare with"),
                ]),
                AXNode(type: "TabBar", frame: frame(y: 790, height: 84), children: [
                    AXNode(type: "Button", frame: AXNode.Frame(x: 100, y: 800, width: 80, height: 50), label: "Browse"),
                ]),
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
