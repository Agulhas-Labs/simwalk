//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle screen --tree` and `--bars`: which nodes are listed, what a line carries, and the ancestor chain (SimWalk#121).
struct ScreenTreeListingTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 1032, height: 1376)

    /// A tab button under a Window and eight anonymous Others, the innermost a bar's strip at 0,32 1032x44 — the issue's own example.
    private static var tabTree: AXNode {
        var node = AXNode(type: "Button", frame: AXNode.Frame(x: 453, y: 36, width: 74, height: 36), label: "Rows", identifier: "list.bullet", isSelected: true)
        for index in 0 ..< 8 {
            let frame = index == 0 ? AXNode.Frame(x: 0, y: 32, width: 1032, height: 44) : screen
            node = AXNode(type: "Other", frame: frame, children: [node])
        }
        return AXNode(type: "Application", frame: screen, children: [AXNode(type: "Window", frame: screen, children: [node])])
    }

    private static func listing(_ tree: AXNode, match: String? = nil, bars: Bool = false, all: Bool = false) -> (residue: [String], clause: String) {
        ScreenTreeListing.listing(of: tree, match: match, bars: bars, listingOffScreen: all)
    }

    @Test
    func theIssuesWorkedExampleListsTheNodeAndItsCollapsedChain() {
        let result = Self.listing(Self.tabTree, match: "list.bullet")

        #expect(result.residue == [
            "Button 'Rows' [list.bullet] 453,36 74×36 selected",
            "    in: Window > Other×7 > Other 0,32 1032×44",
        ])
        #expect(result.clause == "1 node matches 'list.bullet'")
    }

    @Test
    func aNodeUnderTheRootHasNoChainLine() {
        let tree = AXNode(type: "Application", frame: Self.screen, children: [AXNode(type: "Window", frame: Self.screen, identifier: "Main")])

        #expect(Self.listing(tree, match: "main").residue == ["Window [Main] 0,0 1032×1376"])
    }

    @Test
    func matchReadsLabelValueIdentifierAndWholeType() {
        let tree = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "Button", frame: Self.screen, label: "Save Now"),
            AXNode(type: "StaticText", frame: Self.screen, label: "x", value: "SAVED"),
            AXNode(type: "Other", frame: Self.screen, identifier: "save.row"),
            AXNode(type: "TabBar", frame: Self.screen),
        ])

        #expect(Self.listing(tree, match: "save").residue.count == 3)
        #expect(Self.listing(tree, match: "tabbar").residue == ["TabBar 0,0 1032×1376"])
        #expect(Self.listing(tree, match: "Tab").residue.isEmpty, "a type matches whole, not as a substring")
    }

    @Test
    func barsListsEveryBarAndTheUnionAddsMatches() {
        let tree = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "NavigationBar", frame: Self.screen, identifier: "nav"),
            AXNode(type: "Toolbar", frame: Self.screen),
            AXNode(type: "TabBar", frame: Self.screen),
            AXNode(type: "Button", frame: Self.screen, label: "Go"),
            AXNode(type: "Button", frame: Self.screen, label: "Stop"),
        ])

        let bars = Self.listing(tree, bars: true)
        let union = Self.listing(tree, match: "go", bars: true)

        #expect(bars.residue.count == 3)
        #expect(bars.clause == "3 bars")
        #expect(union.residue.count == 4)
        #expect(union.clause == "4 nodes match 'go' or are bars")
    }

    @Test
    func theRootIsNeverACandidate() {
        let root = AXNode.Frame(x: 0, y: 0, width: 0, height: 0)
        let tree = AXNode(type: "Application", frame: root, label: "RouteFixture", children: [
            AXNode(type: "Window", frame: Self.screen, children: [AXNode(type: "Button", frame: Self.screen, label: "Gains log")]),
        ])

        let result = Self.listing(tree, match: "Gains")

        #expect(result.residue.count == 2)
        #expect(!result.residue.contains { $0.hasPrefix("Application") })
        #expect(result.clause == "1 node matches 'Gains'")
    }

    @Test
    func theUnionClauseAtCountOneIsGrammatical() {
        let tree = AXNode(type: "Application", frame: Self.screen, children: [AXNode(type: "TabBar", frame: Self.screen), AXNode(type: "Button", frame: Self.screen, label: "Stop")])

        #expect(Self.listing(tree, match: "go", bars: true).clause == "1 node matches 'go' or is a bar")
    }

    @Test
    func valueAndDisabledSuffixesFollowTheFrame() {
        let tree = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "Switch", frame: AXNode.Frame(x: 1, y: 2, width: 3, height: 4), label: "Wi-Fi", value: "1", isEnabled: false),
        ])

        #expect(Self.listing(tree, match: "wi-fi").residue == ["Switch 'Wi-Fi' 1,2 3×4 = '1' disabled"])
    }

    @Test
    func offScreenMatchesAreCountedUnlessAllListsThemMarked() {
        let below = AXNode.Frame(x: 0, y: 2000, width: 100, height: 20)
        let tree = AXNode(type: "Application", frame: Self.screen, children: [
            AXNode(type: "Button", frame: Self.screen, label: "Row on"),
            AXNode(type: "Button", frame: below, label: "Row off"),
        ])

        let counted = Self.listing(tree, match: "row")
        let listed = Self.listing(tree, match: "row", all: true)

        #expect(counted.residue == ["Button 'Row on' 0,0 1032×1376"])
        #expect(counted.clause == "1 node matches 'row'; 1 more off screen; --all lists them")
        #expect(listed.residue.last == "Button 'Row off' 0,2000 100×20 (off screen)")
        #expect(listed.clause == "1 node matches 'row'; 1 more off screen (listed)")
    }

    /// The query dispatches to the listing and keeps the verdict's step prefix.
    @Test
    func theQueryAnswersWithTheListingWhenTreeOrBarsIsSet() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "screen", captures: [CaptureBundleFixture.Capture(screenID: "screen", state: Walkbook.CaptureState(theme: .light), tree: Self.tabTree)]),
        ])

        let tree = try BundleScreenQuery(bundle).answer(step: "1", match: "rows", tree: true)
        let bars = try BundleScreenQuery(bundle).answer(step: "1", bars: true)

        #expect(tree.text.contains("step 1 'screen' [light] — 1 node matches 'rows'"))
        #expect(tree.text.contains("Button 'Rows' [list.bullet] 453,36 74×36 selected"))
        #expect(bars.text.contains("0 bars"))
    }
}
