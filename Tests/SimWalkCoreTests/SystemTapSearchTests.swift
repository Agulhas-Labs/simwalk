//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A `systemTap`'s search of the app's window, poll by poll (SimWalk#48, #55): what it admits, and a refusal that names the snapshot's blindness when the control was live and the tree did not hold it.
struct SystemTapSearchTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private static let allow = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 700, width: 361, height: 50), label: "Allow", identifier: "UIA.Health.Allow.Button")

    /// **A live match the tree does not hold is refused as the snapshot's blindness, by name** (SimWalk#48, #55): the poll notes it without the runner saying so.
    @Test
    func aLiveMatchTheTreeLacksIsRefusedAsSnapshotBlind() {
        let home = Self.window([])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: home))

        let found: Int? = search.poll(home, springBoardShowedSheet: false) { accepts in accepts(Self.allow) ? 1 : nil }

        #expect(found == nil)
        #expect(search.refusal(bootAge: nil).cause == .snapshotBlind)
        #expect(search.refusal(bootAge: nil).reason.contains("the app's snapshot does not hold it"))
    }

    /// A control the tree holds where the baseline already had it is passed over, and refused as ambiguous with no cause to name: the snapshot saw it.
    @Test
    func theAppsOwnControlIsRefusedWithNoCause() {
        let home = Self.window([Self.allow])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: home))

        let found: Int? = search.poll(home, springBoardShowedSheet: false) { accepts in accepts(Self.allow) ? 1 : nil }

        #expect(found == nil)
        #expect(search.refusal(bootAge: nil).cause == nil)
        #expect(search.refusal(bootAge: nil).reason.contains("ambiguous"))
    }

    /// A control in a subtree the baseline did not have is admitted and returned.
    @Test
    func aSheetsControlIsAdmitted() {
        let sheetUp = Self.window([AXNode(type: "Other", frame: Self.screen, identifier: "UIA.Health.AuthSheet", children: [Self.allow])])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: Self.window([])))

        let found: Int? = search.poll(sheetUp, springBoardShowedSheet: false) { accepts in accepts(Self.allow) ? 1 : nil }

        #expect(found == 1)
    }

    /// A sheet seen in the app's window whose controls lack the label is not "no sheet in the app's window": the refusal must not claim neither place showed one (SimWalk#92 item 7).
    @Test
    func aSheetSeenInTheAppsWindowIsNotRefusedAsNoSheet() {
        let sheetUp = Self.window([AXNode(type: "Other", frame: Self.screen, identifier: "UIA.Health.AuthSheet", children: [])])
        var search = SystemTapSearch(label: "Allow", scope: SystemSheetScope(baseline: Self.window([])))

        let found: Int? = search.poll(sheetUp, springBoardShowedSheet: false) { _ in nil }
        let reason = search.refusal(bootAge: nil).reason

        #expect(found == nil)
        #expect(reason.contains("SpringBoard showed no alert SimWalk could read, and the sheet in the app's window held none"))
        #expect(!reason.contains("neither SpringBoard nor"))
    }

    private static func window(_ content: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: screen, label: "RouteFixture", children: [AXNode(type: "Window", frame: screen, children: content)])
    }
}
