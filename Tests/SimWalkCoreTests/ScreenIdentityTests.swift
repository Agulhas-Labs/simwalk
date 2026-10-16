//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import Testing

/// The guard the 26 Aug 2026 field round produced: a route step that navigates is landed only when the hierarchy has actually left the screen it was taken on.
///
/// The defect it answers is the only kind this tool cannot survive — a bundle whose manifest says one screen and whose artefacts are of another. `rowing-detail` and `cycle-detail` both came back `captured` at the default settle holding the Workouts list, in the screenshot *and* the tree, because the tap returned before the push and the list then held perfectly still for the quiet period (SimWalk#6).
struct ScreenIdentityTests {
    /// **The test that would have caught it.** A capture taken for the detail screen while the hierarchy is still the list it was tapped from is not an arrival, and the runner reports the step as not having landed rather than filing the list under the detail's id.
    @Test
    func thelistAtapWasTakenOnIsNotTheScreenThatTapWasReachingFor() {
        let departed = ScreenIdentity.of(Self.workoutsList())

        #expect(!departed.hasBeenLeft(by: Self.workoutsList()))
        #expect(departed.hasBeenLeft(by: Self.rowingDetail()))
    }

    /// A row lighting up under a finger is a change *within* a screen, and a guard it satisfied would pass on the very list this exists to refuse — which is why `isSelected` is not part of an identity.
    @Test
    func arowLightingUpUnderAfingerIsNotAnArrival() {
        let departed = ScreenIdentity.of(Self.workoutsList())

        #expect(!departed.hasBeenLeft(by: Self.workoutsList(selectedRow: "Rowing, 12 August")))
    }

    /// Nor is a figure ticking over, nor a control being offered as unavailable — same reasoning, the other two volatile fields.
    @Test
    func avalueTickingOrAcontrolDisablingIsNotAnArrival() {
        let departed = ScreenIdentity.of(Self.workoutsList())

        #expect(!departed.hasBeenLeft(by: Self.workoutsList(rowValue: "3.43 km")))
        #expect(!departed.hasBeenLeft(by: Self.workoutsList(rowEnabled: false)))
    }

    /// A screen that moved is still that screen: geometry is left out so a bounce, a jitter or a scroll that keeps the same rows cannot be mistaken for a push.
    @Test
    func aScreenThatOnlyMovedIsStillTheSameScreen() {
        let departed = ScreenIdentity.of(Self.workoutsList())

        #expect(!departed.hasBeenLeft(by: Self.workoutsList(offsetBy: 120)))
    }

    /// The nesting is part of the identity, not only the set of nodes.
    ///
    /// **The two trees here hold exactly the same three nodes and differ only in shape** — a card that was a sibling of the header becoming a child of it — which is what makes this a test of the nesting rather than of the nodes. A description that ran the subtrees together without recording where each one closes reduces both to the same text, and a re-parented subtree is one of the structural changes a push routinely makes.
    @Test
    func asubtreeRehousedUnderItsSiblingIsAdifferentScreen() {
        let card = AXNode(type: "StaticText", frame: Self.screenFrame, label: "Split")
        let header = AXNode(type: "Other", frame: Self.screenFrame, label: "Rowing")
        let siblings = AXNode(type: "Application", frame: Self.screenFrame, children: [header, card])
        let nested = AXNode(
            type: "Application",
            frame: Self.screenFrame,
            children: [AXNode(type: "Other", frame: Self.screenFrame, label: "Rowing", children: [card])]
        )

        #expect(siblings.flattened.map(\.label) == nested.flattened.map(\.label))
        #expect(ScreenIdentity.of(siblings).hasBeenLeft(by: nested))
    }

    /// Switching tabs is an arrival like any other — the guard is about the hierarchy, not about which step produced it.
    @Test
    func aTabWhoseContentSwappedIsAnArrival() {
        let departed = ScreenIdentity.of(Self.workoutsList())

        #expect(departed.hasBeenLeft(by: Self.browse()))
    }

    /// A pure function of the tree, so the identity of one screen cannot drift between two reads of it — the direction a wrong answer would file false evidence rather than refuse.
    @Test
    func theSameTreeAlwaysReducesToTheSameIdentity() {
        #expect(ScreenIdentity.of(Self.workoutsList()) == ScreenIdentity.of(Self.workoutsList()))
        #expect(ScreenIdentity.of(Self.workoutsList()).digest.count == 64)
    }

    private static let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    /// The Workouts list, in the shape a tap is taken on it.
    private static func workoutsList(
        selectedRow: String? = nil,
        rowValue: String? = nil,
        rowEnabled: Bool = true,
        offsetBy offset: Double = 0
    ) -> AXNode {
        AXNode(
            type: "Application",
            frame: screenFrame,
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "NavigationBar",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 96),
                    label: "Workouts"
                ),
                AXNode(
                    type: "ScrollView",
                    frame: screenFrame,
                    children: ["Rowing, 12 August", "Coastal Cruise, 19 August"].enumerated().map { index, label in
                        row(
                            label: label,
                            y: 120 + Double(index) * 72 - offset,
                            isSelected: label == selectedRow,
                            value: label == "Rowing, 12 August" ? rowValue : nil,
                            isEnabled: label == "Rowing, 12 August" ? rowEnabled : true
                        )
                    }
                ),
            ]
        )
    }

    /// The pushed record the tap was reaching for.
    private static func rowingDetail() -> AXNode {
        AXNode(
            type: "Application",
            frame: screenFrame,
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "NavigationBar",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 96),
                    label: "Rowing"
                ),
                AXNode(
                    type: "ScrollView",
                    frame: screenFrame,
                    children: [
                        AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 200, height: 30), label: "Split"),
                        AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 160, width: 200, height: 30), label: "Stroke rate"),
                    ]
                ),
            ]
        )
    }

    /// Another tab's screen, built from none of the list's parts so what separates them is not an accident of the fixture.
    private static func browse() -> AXNode {
        AXNode(
            type: "Application",
            frame: screenFrame,
            label: "RouteFixture",
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 200, height: 30), label: "Heart"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 180, width: 200, height: 30), label: "Activity"),
            ]
        )
    }

    private static func row(
        label: String,
        y: Double = 120,
        isSelected: Bool = false,
        value: String? = nil,
        isEnabled: Bool = true
    ) -> AXNode {
        AXNode(
            type: "Cell",
            frame: AXNode.Frame(x: 14, y: y, width: 374, height: 55),
            label: label,
            value: value,
            isSelected: isSelected,
            isEnabled: isEnabled
        )
    }
}
