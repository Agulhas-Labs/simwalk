//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// An identifier every element of one container carries is SwiftUI's propagation of a container's modifier — or a shared row identifier, which has the same shape — so it is its own ``ScreenIdentifier/Source/propagated``: never the stable answer, below every container's own identifier anywhere in scope, and reported only when a fallback is asked for (SimWalk#20 round 5, ruling 2; round 4 read it as the container's own, at the same priority, in tree order).
struct ScreenPropagationTests {
    /// `.accessibilityIdentifier` on a plain SwiftUI stack lands on every element inside it instead of on a node of its own: reported as propagated when asked, and never by the string `expect:` reads.
    @Test
    func anidentifierEveryElementOfOneContainerCarriesIsPropagatedNeverStable() {
        let tree = ScreenTreeFixture.app(content: Self.stack([
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 132, width: 300, height: 16), label: "Notifications", identifier: "App.SettingsScreen"),
            AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 172, width: 300, height: 44), label: "Sign out", identifier: "App.SettingsScreen"),
        ]))

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == ScreenIdentifier(value: "App.SettingsScreen", source: .propagated))
        #expect(ScreenIdentifier(of: tree) == nil)
        #expect(tree.screenIdentifier == nil)
    }

    /// Rows that are buttons in a plain stack, every one tagged `workoutRow`, share an identifier that names the rows, not the screen: propagated when asked, never stable (SimWalk#20 round 4, finding 2 — this answered `workoutRow` as the screen's).
    @Test
    func sharedRowIdentifiersArePropagatedNeverTheScreens() {
        let rows = ["Morning run", "Evening ride", "Swim"].enumerated().map { index, label in
            AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 132 + Double(index) * 52, width: 358, height: 48), label: label, identifier: "workoutRow")
        }
        let tree = ScreenTreeFixture.app(content: Self.stack(rows))

        #expect(tree.screenIdentifier == nil)
        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true)?.source == .propagated)
    }

    /// A container's own identifier anywhere in scope wins over a propagated one earlier in tree order: a label and value sharing `metric` ahead of an identified scroll view gave `metric` (SimWalk#20 round 4, finding 2).
    @Test
    func acontainersIdentifierAnywhereInScopeWinsOverAPropagatedOneBeforeIt() {
        let pair = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 116, width: 402, height: 40), children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 124, width: 180, height: 16), label: "Resting heart rate", identifier: "metric"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 250, y: 124, width: 130, height: 16), label: "58 bpm", identifier: "metric"),
        ])
        let tree = ScreenTreeFixture.app(content: AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
            pair, ScreenTreeFixture.content(identifier: "App.HeartScreen", texts: ["Today"]),
        ]))

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == ScreenIdentifier(value: "App.HeartScreen", source: .content))
    }

    /// Of the two unstable identifiers, the navigation bar's title comes first: a title is always the screen's own, where a shared identifier may be its rows'.
    @Test
    func anavigationBarsTitleComesBeforeAPropagatedIdentifier() {
        let tree = ScreenTreeFixture.app(
            bar: ScreenTreeFixture.navigationBar(identifier: "Workouts", back: "Back"),
            content: Self.stack([
                AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 132, width: 358, height: 48), label: "Morning run", identifier: "workoutRow"),
                AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 184, width: 358, height: 48), label: "Swim", identifier: "workoutRow"),
            ])
        )

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == ScreenIdentifier(value: "Workouts", source: .navigationBar))
    }

    /// Propagation needs every element of the container, at least two, not all images, and no cells: one element's own identifier, two elements' differing ones, a row of one symbol, and an identifier on every row cell each name elements, and are nothing even as a fallback.
    @Test(arguments: [
        [AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 172, width: 300, height: 44), label: "Save", identifier: "App.SettingsScreen")],
        [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 132, width: 300, height: 16), label: "Name", identifier: "nameLabel"),
            AXNode(type: "Button", frame: AXNode.Frame(x: 22, y: 172, width: 300, height: 44), label: "Save", identifier: "saveButton"),
        ],
        [
            AXNode(type: "Image", frame: AXNode.Frame(x: 22, y: 132, width: 20, height: 20), label: "star", identifier: "star.fill"),
            AXNode(type: "Image", frame: AXNode.Frame(x: 46, y: 132, width: 20, height: 20), label: "star", identifier: "star.fill"),
        ],
        [
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 132, width: 402, height: 44), label: "One", identifier: "row"),
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 176, width: 402, height: 44), label: "Two", identifier: "row"),
        ],
    ])
    func elementIdentifiersThatAreNotAPropagationNeverAnswer(elements: [AXNode]) {
        let tree = ScreenTreeFixture.app(content: Self.stack(elements))

        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == nil)
    }

    /// A screen whose content is one plain container of `elements`, inside an unidentified scroll view.
    private static func stack(_ elements: [AXNode]) -> AXNode {
        AXNode(type: "Other", frame: ScreenTreeFixture.screenFrame, children: [
            AXNode(type: "ScrollView", frame: ScreenTreeFixture.screenFrame, children: [
                AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 116, width: 402, height: 700), children: elements),
            ]),
        ])
    }
}
