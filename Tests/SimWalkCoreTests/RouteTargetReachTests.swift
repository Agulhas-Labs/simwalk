//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// What a route step reaches for — a `tap` a control, a `scrollTo` anywhere it can arrive, a `type` a field that takes text — and when each may take what it found (`RouteTarget.Reach`).
///
/// The label matches the same way for all three; what differs is which elements count as controls, whether a bar's control is worth reaching, and whether the first read is enough.
struct RouteTargetReachTests {
    /// A `type` step considers only fields that take text — never the container a search field is drawn inside — and a search field in a navigation bar, as `.searchable` draws it, is a bar control: taken once the screen holds still.
    @Test
    func atypeStepConsidersOnlyFieldsAndTakesASearchBarFieldOnceStill() {
        let tree = Self.screen([
            AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 110), children: [
                AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 110, width: 370, height: 44), label: "Search boats, crew, harbours…", children: [
                    AXNode(type: "SearchField", frame: AXNode.Frame(x: 24, y: 114, width: 350, height: 36), label: "Search boats, crew, harbours…"),
                ]),
            ]),
        ])

        let choice = RouteTarget.choose(labelled: "Search boats, crew, harbours…", in: tree, reaching: .textEntry)

        guard case let .chosen(target, all) = choice else {
            Issue.record("expected the field, got \(choice)")
            return
        }

        #expect(target.node.type == "SearchField")
        #expect(all.count == 1)
        #expect(target.index == nil)
        #expect(!choice.isSettled)
        #expect(choice.acceptsOnceStill)
    }

    /// A field in the screen itself is the control a `type` step waits for, and settles at once.
    @Test
    func atypeStepSettlesOnAFieldInTheScreen() {
        let tree = Self.screen([AXNode(type: "TextField", frame: Self.frame(y: 200, height: 44), label: "Name")])

        #expect(RouteTarget.choose(labelled: "Name", in: tree, reaching: .textEntry).isSettled)
    }

    /// Content is somewhere a `scrollTo` arrives as soon as it exists, as a scroll always did, where a `tap` keeps waiting for a control that may still load.
    @Test
    func contentIsWhereAScrollArrivesAtOnceAndATapKeepsWaiting() {
        let tree = Self.screen([AXNode(type: "StaticText", frame: Self.frame(y: 1200, height: 20), label: "By sport")])

        #expect(RouteTarget.choose(labelled: "By sport", in: tree, reaching: .anything).isSettled)
        #expect(!RouteTarget.choose(labelled: "By sport", in: tree, reaching: .control).isSettled)
        #expect(!RouteTarget.choose(labelled: "By sport", in: tree, reaching: .control).acceptsOnceStill)
    }

    /// A `scrollTo` whose best match is a bar's control or chrome does not settle on it: a scroll can only "arrive" at a bar by not scrolling, so it waits for the screen to hold still in case the content of that name is still loading.
    @Test
    func ascrollDoesNotSettleOnABarControlOrChrome() {
        let tabItem = Self.screen([
            AXNode(type: "TabBar", frame: Self.frame(y: 791, height: 83), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 110, y: 795, width: 95, height: 54), label: "Workouts"),
            ]),
        ])
        let titleBar = Self.screen([AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 96), identifier: "Workouts")])

        for tree in [tabItem, titleBar] {
            let choice = RouteTarget.choose(labelled: "Workouts", in: tree, reaching: .anything)
            #expect(!choice.isSettled)
            #expect(choice.acceptsOnceStill)
        }
    }

    /// A `scrollTo` naming a word a tab item also carries scrolls to the card of that name, not to the tab item — which is always on screen, and would land without scrolling at all.
    ///
    /// The shape of the worked-example walkbook's `today-lower`: `tab 'Today'` then `scrollTo 'Workouts'`, beside the tab bar's own `Workouts`. A `tap` still prefers the tab item to text, as it did.
    @Test
    func ascrollNamingATabsWordArrivesAtTheCardNotTheTabItem() {
        let tree = Self.screen([
            AXNode(type: "ScrollView", frame: Self.frame(y: 0, height: 874), children: [
                AXNode(type: "StaticText", frame: Self.frame(y: 1400, height: 24), label: "Workouts"),
            ]),
            AXNode(type: "TabBar", frame: Self.frame(y: 791, height: 83), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 110, y: 795, width: 95, height: 54), label: "Workouts"),
            ]),
        ])

        guard case let .chosen(scrolled, _) = RouteTarget.choose(labelled: "Workouts", in: tree, reaching: .anything),
              case let .chosen(tapped, _) = RouteTarget.choose(labelled: "Workouts", in: tree, reaching: .control)
        else {
            Issue.record("expected both to choose")
            return
        }

        #expect(scrolled.node.type == "StaticText")
        #expect(tapped.insideBar == "TabBar")
    }

    /// A `type` step whose label names a search field and a text field refuses and names both, rather than ranking one above the other.
    ///
    /// The lookup it replaced took a search field first, whatever else carried the label; ranking takes an in-screen text field over a search field in the navigation bar. Either would be a guess, and one of them a different field than before, typed into and reported as landed.
    @Test
    func atypeStepNamingASearchFieldAndATextFieldRefusesAndNamesBoth() {
        let tree = Self.screen([
            AXNode(type: "NavigationBar", frame: Self.frame(y: 54, height: 110), children: [
                AXNode(type: "SearchField", frame: AXNode.Frame(x: 24, y: 114, width: 350, height: 36), label: "Search"),
            ]),
            AXNode(type: "TextField", frame: Self.frame(y: 300, height: 44), label: "Search"),
        ])

        let choice = RouteTarget.choose(labelled: "Search", in: tree, reaching: .textEntry)

        guard case let .ambiguous(fields) = choice else {
            Issue.record("expected a refusal, got \(choice)")
            return
        }

        #expect(Set(fields.map(\.node.type)) == ["SearchField", "TextField"])
        #expect(choice.reason(for: "Search").contains("a SearchField labelled 'Search' in the NavigationBar"))
        #expect(choice.reason(for: "Search").contains("a TextField labelled 'Search'"))
        #expect(choice.reason(for: "Search").hasPrefix("'Search' names fields of more than one type"))
    }

    /// The same for any two types of field, and whichever the ranking would have preferred — a disabled field of one type beside an enabled one of another included.
    ///
    /// Fields of one type are not refused: the first of them is taken, as the first always was.
    @Test
    func atypeStepRefusesFieldsOfTwoTypesButNotTwoOfOne() {
        let mixed = Self.screen([
            AXNode(type: "TextField", frame: Self.frame(y: 200, height: 44), label: "Password", isEnabled: false),
            AXNode(type: "SecureTextField", frame: Self.frame(y: 260, height: 44), label: "Password"),
        ])
        let alike = Self.screen([
            AXNode(type: "TextField", frame: Self.frame(y: 200, height: 44), label: "Name"),
            AXNode(type: "TextField", frame: Self.frame(y: 260, height: 44), label: "Name"),
        ])

        guard case .ambiguous = RouteTarget.choose(labelled: "Password", in: mixed, reaching: .textEntry),
              case let .chosen(first, _) = RouteTarget.choose(labelled: "Name", in: alike, reaching: .textEntry)
        else {
            Issue.record("expected a refusal and a choice")
            return
        }

        #expect(first.node.frame.y == 200)
    }

    /// A lead-in's tie keeps its own wording, which says what a lead-in is; only fields of more than one type are refused as fields.
    @Test
    func atieBetweenLeadInsIsNotDescribedAsFields() {
        let tree = Self.screen([
            AXNode(type: "Button", frame: Self.frame(y: 200), label: "Sail, 12 August 07:10 · 5.10 km"),
            AXNode(type: "Button", frame: Self.frame(y: 260), label: "Sail, 12 August 18:30 · 3.20 km"),
        ])

        #expect(RouteTarget.choose(labelled: "Sail, 12 August", in: tree).reason(for: "Sail, 12 August").hasPrefix("'Sail, 12 August' only begins the labels of 2 elements"))
    }

    /// Not a lead-in, though — not for a `scrollTo` either, and not in a bar: a lead-in waits out the lookup whatever it lands on.
    @Test
    func aleadInIsNeverTakenOnceStillWhateverItLandsOn() {
        let heading = Self.screen([AXNode(type: "StaticText", frame: Self.frame(y: 1200, height: 20), label: "By sport 3")])
        let bar = Self.screen([
            AXNode(type: "Toolbar", frame: Self.frame(y: 740, height: 50), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 745, width: 60, height: 40), label: "Edit 3"),
            ]),
        ])

        #expect(!RouteTarget.choose(labelled: "By sport", in: heading, reaching: .anything).acceptsOnceStill)
        #expect(!RouteTarget.choose(labelled: "Edit", in: bar).acceptsOnceStill)
    }

    /// A `tap` swipes towards a label the tree does not hold yet, as a `scrollTo` does, and a `type` does not (SimWalk#104).
    @Test
    func atapAndAScrollToSeekAnAbsentLabelAndATypeDoesNot() {
        #expect(RouteTarget.Reach.control.seeksWhenAbsent)
        #expect(RouteTarget.Reach.anything.seeksWhenAbsent)
        #expect(!RouteTarget.Reach.textEntry.seeksWhenAbsent)
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
