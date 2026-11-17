//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// What a `tap` that must change nothing counts as the screen changing (SimWalk#268 follow-up): an element appearing or going, never an identifier filling in, and the refusal names the element.
struct ScreenStructureChangeTests {
    /// **A tab bar's buttons gaining their identifiers after a tab switch is no change, and the tap lands** (seen live on RouteFixture: `tap 'Press row' unchanged` after `tab 'Hub'` was refused in half its walks).
    ///
    /// The diagnosed nodes exactly: up to half a second after the switch the four tab buttons are read with no identifier, then with their symbols' names. `ScreenIdentity` agrees that the screen was not left (SimWalk#279).
    @Test
    func aTabBarsButtonsGainingTheirIdentifiersIsNoChangeAndTheTapLands() {
        let before = Self.hub(tabIdentifiers: [nil, nil, nil, nil])
        let after = Self.hub(tabIdentifiers: ["house", "list.bullet", "filemenu.and.selection", "square.stack"])

        #expect(!ScreenIdentity.of(before).hasBeenLeft(by: after))
        #expect(ScreenStructureChange.between(before, after) == nil)
        #expect(TapLanding.decideUnchanged(screenChange: ScreenStructureChange.between(before, after), tappedTraitChange: nil, tapped: "a Button labelled 'Press row'") == .landed)
    }

    /// **A menu that opens is a change, named by the first labelled element it brought**, its unlabelled container and the rest counted.
    @Test
    func aMenuThatOpensNamesTheFirstLabelledElementItBrought() {
        let before = Self.hub(tabIdentifiers: [nil, nil, nil, nil])
        var after = before
        after.children.append(AXNode(type: "Other", frame: Self.frame, children: [Self.button("Open details"), Self.button("Copy")]))

        let change = ScreenStructureChange.between(before, after)

        #expect(change?.appeared.map(\.type) == ["Other", "Button", "Button"])
        #expect(change?.went == [])
        #expect(change?.clause == "'Open details' and 2 more appeared")
    }

    /// **An element that went is named when nothing appeared.**
    @Test
    func anElementThatWentIsNamedWhenNothingAppeared() {
        let before = Self.screen([Self.button("Press row"), Self.button("Open form")])
        let after = Self.screen([Self.button("Open form")])

        #expect(ScreenStructureChange.between(before, after)?.clause == "'Press row' went")
    }

    /// **An element that only moved to another parent is not the news**: it goes and comes under one label, so the label new to the screen is named.
    @Test
    func anElementThatOnlyMovedIsPassedOverForTheOneNewToTheScreen() {
        let before = Self.screen([Self.button("Press row")])
        let after = Self.screen([
            AXNode(type: "Other", frame: Self.frame, children: [Self.button("Press row")]),
            AXNode(type: "StaticText", frame: Self.frame, label: "Form"),
        ])

        let change = ScreenStructureChange.between(before, after)

        #expect(change?.went.map(\.label) == ["Press row"])
        #expect(change?.clause == "'Form' and 2 more appeared")
    }

    /// **An element with no label is named by its type.**
    @Test
    func anUnlabelledElementIsNamedByItsType() {
        let before = Self.screen([Self.button("Press row")])
        let after = Self.screen([Self.button("Press row"), AXNode(type: "Other", frame: Self.frame)])

        #expect(ScreenStructureChange.between(before, after)?.clause == "an unlabelled Other appeared")
    }

    /// **Frames, traits and values are not structure**, as for `ScreenIdentity`: a row highlighted, moved or given a value is no change.
    @Test
    func framesTraitsAndValuesAreNoChange() {
        let before = Self.screen([Self.button("Press row")])
        let after = Self.screen([AXNode(type: "Button", frame: AXNode.Frame(x: 0, y: 80, width: 300, height: 44), label: "Press row", value: "1", isSelected: true)])

        #expect(ScreenStructureChange.between(before, after) == nil)
    }

    // MARK: - Fixtures

    private static let frame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    private static func screen(_ children: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: frame, label: "RouteFixture", children: children)
    }

    private static func button(_ label: String, identifier: String? = nil) -> AXNode {
        AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 200, width: 370, height: 44), label: label, identifier: identifier)
    }

    /// RouteFixture's Hub tab: a row with a context menu, and the tab bar with each tab's identifier as given.
    private static func hub(tabIdentifiers: [String?]) -> AXNode {
        let tabs = zip(["Hub", "Rows", "Menus", "Nested"], tabIdentifiers).map { button($0, identifier: $1) }
        return screen([
            AXNode(type: "Other", frame: frame, children: [button("Press row"), button("Open form")]),
            AXNode(type: "TabBar", frame: frame, label: "Tab Bar", children: tabs),
        ])
    }
}
