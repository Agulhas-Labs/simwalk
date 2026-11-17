//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The AX tree is the differ's actual input (Brief §2.2), so its shape is a contract rather than a convenience — and it has to survive the trip through a bundle unchanged.
struct AXNodeTests {
    @Test
    func atreeRoundTripsThroughTheBundlesEncoding() throws {
        let tree = Self.screen()

        let encoded = try CaptureBundle.encoder().encode(tree)
        let decoded = try CaptureBundle.decoder().decode(AXNode.self, from: encoded)

        #expect(decoded == tree)
    }

    @Test
    func flatteningVisitsEveryNodeInTreeOrder() {
        #expect(Self.screen().flattened.map(\.type) == ["Window", "TabBar", "Button", "Button", "StaticText"])
    }

    /// "Every text run with its frame" is what the capture promises; an element with no label is structure, not text.
    @Test
    func textRunsAreTheLabelledNodesOnly() {
        let runs = Self.screen().textRuns

        #expect(runs.map(\.label) == ["Progress", "Workouts", "4 sessions"])
        #expect(runs.allSatisfy { $0.frame.width > 0 })
    }

    /// A differ asks "was this below the fold" constantly, and the answer is the bottom edge, not the top.
    @Test
    func aframeKnowsItsBottomEdge() {
        let frame = AXNode.Frame(x: 0, y: 800, width: 100, height: 120)

        #expect(frame.maxY == 920)
    }

    /// SimWalk#252: a SwiftUI pulse scales a button about 6% around its centre on every read, and the reads still name one steady frame; a spring sliding it in, or another size, does not.
    @Test
    func aframeScaledByAPulseIsSteadyAndOneThatSlidOrResizedIsNot() {
        let button = AXNode.Frame(x: 163, y: 294, width: 77, height: 81)
        let pulsed = AXNode.Frame(x: 160.7, y: 291.6, width: 81.6, height: 85.9)

        #expect(button.isSteady(with: AXNode.Frame(x: 162, y: 293, width: 78, height: 82)))
        #expect(button.isSteady(with: pulsed))
        #expect(pulsed.isSteady(with: button))
        #expect(!button.isSteady(with: AXNode.Frame(x: 163, y: 394, width: 77, height: 81)))
        #expect(!button.isSteady(with: AXNode.Frame(x: 163, y: 294, width: 90, height: 81)))
    }

    /// A small element is held to the floor, not to a fraction of a few points that whole-point rounding alone would break.
    @Test
    func asmallFrameMayMoveByTheFloor() {
        let dot = AXNode.Frame(x: 10, y: 10, width: 8, height: 8)

        #expect(dot.isSteady(with: AXNode.Frame(x: 11, y: 9, width: 9, height: 9)))
        #expect(!dot.isSteady(with: AXNode.Frame(x: 13, y: 10, width: 8, height: 8)))
    }

    /// SimWalk#252: the same screen under a pulse reports its largest shift; anything but a small frame move is not the same screen.
    @Test
    func steadyShiftIsTheLargestMoveOfTheSameElementsAndNilOtherwise() {
        func screen(_ button: AXNode.Frame, label: String = "Play", extra: Bool = false) -> AXNode {
            AXNode(
                type: "Application",
                frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                children: [AXNode(type: "Button", frame: button, label: label)]
                    + (extra ? [AXNode(type: "StaticText", frame: button, label: "New")] : [])
            )
        }
        let button = AXNode.Frame(x: 163, y: 294, width: 77, height: 81)

        #expect(screen(button).steadyShift(to: screen(button)) == 0)
        #expect(screen(button).steadyShift(to: screen(AXNode.Frame(x: 162, y: 293, width: 78, height: 82))) == 1)
        #expect(screen(button).steadyShift(to: screen(AXNode.Frame(x: 263, y: 294, width: 77, height: 81))) == nil)
        #expect(screen(button).steadyShift(to: screen(button, label: "Pause")) == nil)
        #expect(screen(button).steadyShift(to: screen(button, extra: true)) == nil)
    }

    /// The size half lets the frame sit anywhere, as a scroll moves it.
    @Test
    func asteadySizeIgnoresWhereTheFrameSits() {
        let row = AXNode.Frame(x: 0, y: 1400, width: 402, height: 60)

        #expect(row.hasSteadySize(with: AXNode.Frame(x: 32, y: 700, width: 420, height: 63)))
        #expect(!row.hasSteadySize(with: AXNode.Frame(x: 0, y: 1400, width: 402, height: 44)))
    }

    /// An unlabelled element must decode as having no label rather than as carrying an empty string, or every consumer has to special-case `""` alongside `nil`.
    @Test
    func anAbsentLabelIsAbsentRatherThanEmpty() throws {
        let json = #"{"type":"Other","frame":{"x":0,"y":0,"width":10,"height":10},"children":[]}"#

        let decoded = try JSONDecoder().decode(AXNode.self, from: Data(json.utf8))

        #expect(decoded.label == nil)
        #expect(decoded.textRuns.isEmpty)
    }

    /// The traits SimWalk#2 was filed about: a selected pill and a disabled one have to survive the trip through a real bundle, or an audit reading the tree back cannot tell them from their siblings.
    @Test
    func aselectedAndAdisabledElementSurviveTheTripThroughABundle() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "heart-detail", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.segmentedControl()),
        ])

        let pills = try CaptureBundle.read(at: bundle.url)
            .axTree(for: #require(bundle.manifest.screens.first?.captures.first))
            .flattened
            .filter { $0.type == "Button" }

        #expect(pills.filter(\.isSelected).map(\.label) == ["W"])
        #expect(pills.filter { !$0.isEnabled }.map(\.label) == ["Y"])
    }

    /// Written only when they are the unusual answer, so the 154 ordinary nodes of a real screen cost nothing and a tree captured before they existed decodes to the tree it always was.
    @Test
    func theTraitsAreWrittenOnlyWhenTheyAreTheUnusualAnswer() throws {
        let ordinary = AXNode(type: "Button", frame: AXNode.Frame(x: 0, y: 0, width: 10, height: 10))
        let unusual = AXNode(type: "Button", frame: AXNode.Frame(x: 0, y: 0, width: 10, height: 10), isSelected: true, isEnabled: false)

        let ordinaryJSON = try #require(String(bytes: JSONEncoder().encode(ordinary), encoding: .utf8))
        let unusualJSON = try #require(String(bytes: JSONEncoder().encode(unusual), encoding: .utf8))

        #expect(!ordinaryJSON.contains("isSelected"))
        #expect(!ordinaryJSON.contains("isEnabled"))
        #expect(unusualJSON.contains("\"isSelected\":true"))
        #expect(unusualJSON.contains("\"isEnabled\":false"))
    }

    /// A tree written before the traits existed is not a tree asserting nothing was selected and everything disabled — the defaults are the ordinary answer, both directions.
    @Test
    func atreeWrittenWithoutTheTraitsDecodesAsOrdinary() throws {
        let json = #"{"type":"Button","frame":{"x":0,"y":0,"width":10,"height":10}}"#

        let decoded = try JSONDecoder().decode(AXNode.self, from: Data(json.utf8))

        #expect(!decoded.isSelected)
        #expect(decoded.isEnabled)
    }

    /// `screenIdentifier` is the shared lookup `bundle screen` and walkbook `expect:` both need: the runner roots every tree at the application element, which XCUITest never gives an identifier, so the real one — when the app sets one at all — sits somewhere below it (SimWalk#20 round 2, finding 1).
    @Test
    func screenIdentifierFindsTheFirstOneBelowTheAppRoot() {
        let tree = Self.realShapedScreen(content: AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 44, width: 402, height: 830), identifier: "ProgressScreen.Identifiers_screen"))

        #expect(tree.screenIdentifier == "ProgressScreen.Identifiers_screen")
    }

    /// A tab bar never says which screen this is, so an unidentified screen with a real tab bar is *no identifier*, never a tab item's.
    ///
    /// Every real tab bar carries no identifier of its own, and its items' images carry their symbol names — the same on every screen. The fixture's tab bar used to carry an identifier and no children, the reverse of every real capture; `ScreenIdentifierTests` pins the rest of the rule.
    @Test
    func screenIdentifierSkipsATabBarsOwnSubtreeEntirely() {
        let tree = Self.realShapedScreen(content: AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 44, width: 402, height: 830)))

        #expect(tree.screenIdentifier == nil)
    }

    /// A navigation bar's title is never `screenIdentifier`, even when the content carries nothing — the real shape a detail screen took in review, the bar identified with the screen's title and first in tree order.
    ///
    /// A title is localised, so the string `expect:` compares against would change with the language a walk captures in; ``ScreenIdentifier`` reports it only when asked (SimWalk#20 round 4, finding 5 — this test asserted the title until then).
    @Test
    func screenIdentifierIsNeverANavigationBarsTitle() {
        let tree = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    children: [
                        AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 44), identifier: "Heart"),
                        AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 44, width: 402, height: 830)),
                        ScreenTreeFixture.tabBar(),
                    ]
                ),
            ]
        )

        #expect(tree.screenIdentifier == nil)
        #expect(ScreenIdentifier(of: tree, fallingBackToUnstable: true) == ScreenIdentifier(value: "Heart", source: .navigationBar))
    }

    /// Nothing below the root carries one either — the honest absence, not a guess at the app's own name.
    @Test
    func screenIdentifierIsNilWhenNothingBelowTheRootCarriesOne() {
        let tree = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            label: "RouteFixture",
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 200, height: 30), label: "Heart"),
            ]
        )

        #expect(tree.screenIdentifier == nil)
    }

    /// A screen shaped like a real capture: the app root (labelled, never identified) rooting `Window → [content, tab bar]`, the tab bar as every real one is — no identifier of its own, its items' images identified.
    private static func realShapedScreen(content: AXNode) -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    children: [
                        content,
                        ScreenTreeFixture.tabBar(),
                    ]
                ),
            ]
        )
    }

    private static func screen() -> AXNode {
        AXNode(
            type: "Window",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [
                AXNode(
                    type: "TabBar",
                    frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83),
                    children: [
                        AXNode(type: "Button", frame: AXNode.Frame(x: 25, y: 795, width: 95, height: 54), label: "Progress", isSelected: true),
                        AXNode(type: "Button", frame: AXNode.Frame(x: 110, y: 795, width: 95, height: 54), label: "Workouts", identifier: "tab.workouts", isEnabled: false),
                    ]
                ),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 200, width: 300, height: 30), label: "4 sessions", value: "4"),
            ]
        )
    }

    /// The placeholder is the only name a filled text field has (SimWalk#212); it survives the trip, and is written only where there is one.
    @Test
    func aPlaceholderRoundTripsAndIsOmittedWhenAbsent() throws {
        let field = AXNode(type: "TextField", frame: AXNode.Frame(x: 0, y: 0, width: 10, height: 10), value: "Draft", placeholder: "Nickname")
        let plain = AXNode(type: "TextField", frame: AXNode.Frame(x: 0, y: 0, width: 10, height: 10))

        let data = try JSONEncoder().encode(field)
        let plainJSON = try #require(String(bytes: JSONEncoder().encode(plain), encoding: .utf8))

        #expect(try JSONDecoder().decode(AXNode.self, from: data) == field)
        #expect(!plainJSON.contains("placeholder"))
    }

    /// A tree written before the key existed decodes with no placeholder, and no format bump was needed to say so.
    @Test
    func atreeWrittenWithoutAPlaceholderDecodesWithNone() throws {
        let json = #"{"type":"TextField","frame":{"x":0,"y":0,"width":10,"height":10},"value":"Draft"}"#

        let decoded = try JSONDecoder().decode(AXNode.self, from: Data(json.utf8))

        #expect(decoded.placeholder == nil)
    }
}
