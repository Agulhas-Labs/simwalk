//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// What the classifier reads from a screen: the rows a route can name and the controls it leaves, with a scroll bar neither.
struct DiscoverClassifierTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 400, height: 800)

    /// A scroll bar as the tree carries it: a labelled `Other` with a percentage for its value and a bare thin thumb.
    private static func scrollBar() -> AXNode {
        let thumb = AXNode(type: "Other", frame: AXNode.Frame(x: 395, y: 0, width: 3, height: 20))
        return AXNode(type: "Other", frame: AXNode.Frame(x: 390, y: 0, width: 10, height: 800), label: "Vertical scroll bar, 2 pages", value: "0%", children: [thumb])
    }

    @Test
    func scrollBarsAreNeitherRowsNorSkippedControls() {
        let glyph = AXNode(type: "Image", frame: AXNode.Frame(x: 370, y: 15, width: 10, height: 20))
        let row = AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 50), label: "Profile", children: [glyph])
        let table = AXNode(type: "Table", frame: Self.screen, children: [row, Self.scrollBar(), Self.scrollBar()])
        let tree = AXNode(type: "Application", frame: Self.screen, children: [table])

        let read = DiscoverClassifier.read(tree, screenID: "hub")

        #expect(read.rows.map(\.label) == ["Profile"])
        #expect(!read.skipped.contains { ($0.name).contains("scroll bar") })
    }
}
