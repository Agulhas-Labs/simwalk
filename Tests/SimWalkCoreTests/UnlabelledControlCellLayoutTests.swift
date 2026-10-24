//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import Testing

/// `unlabelledControl` over the elements of table cells UIKit has not laid out (SimWalk#230).
///
/// Does not pin the rule's other behaviour.
struct UnlabelledControlCellLayoutTests {
    private static func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> AXNode.Frame {
        AXNode.Frame(x: x, y: y, width: width, height: height)
    }

    private static func evaluate(cell: AXNode) -> LabelRuleResult {
        let table = AXNode(type: "Table", frame: frame(0, 0, 420, 912), children: [cell])
        let app = AXNode(type: "Application", frame: frame(0, 0, 420, 912), children: [table])
        return UnlabelledControlAudit().evaluate(app, screenID: "settings", stateSlug: "light")
    }

    private static func cell(y: Double, holding child: AXNode) -> AXNode {
        AXNode(type: "Cell", frame: frame(20, y, 380, 51.3), children: [child])
    }

    @Test
    func aSwitchAtAPlaceholderFrameInACellBelowTheFoldIsNotJudged() {
        let placeholder = AXNode(type: "Switch", frame: Self.frame(0, 142, 63, 28), value: "1")

        let result = Self.evaluate(cell: Self.cell(y: 986, holding: placeholder))

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    @Test
    func aSwitchInsideItsOffScreenCellIsStillJudged() {
        let laidOut = AXNode(type: "Switch", frame: Self.frame(319, 995, 51, 31), value: "1")

        let result = Self.evaluate(cell: Self.cell(y: 986, holding: laidOut))

        #expect(result.findings.count == 1)
        #expect(result.examined == 1)
    }

    @Test
    func anUnlabelledFieldInAnOnScreenCellIsStillJudged() {
        let field = AXNode(type: "TextField", frame: Self.frame(40, 244.67, 340, 22), value: "NetNewsWire Blog")

        let result = Self.evaluate(cell: Self.cell(y: 230, holding: field))

        #expect(result.findings.count == 1)
        #expect(result.examined == 1)
    }
}
