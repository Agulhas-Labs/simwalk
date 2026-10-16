//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A `tab` step that finds its button covered says so instead of landing (SimWalk#95).
struct TabStepRefusalTests {
    /// **The reason names the tab, what was seen, and that nothing was tapped.**
    @Test
    func aCoveredTabIsRefusedNamingTheTabAndTheCover() {
        let reason = TabStepRefusal.notHittable(label: "Summary")

        #expect(reason.contains("'Summary'"))
        #expect(reason.contains("in the tree but not hittable"))
        #expect(reason.contains("modal sheet"))
        #expect(reason.contains("was not tapped"))
    }

    /// **A screen with no bar says what a bar would have been.**
    @Test
    func aMissingBarIsNamedAsMissing() {
        let reason = TabStepRefusal.notFound(label: "Menus", tabs: [], bar: nil)

        #expect(reason == "no tab bar on screen: neither a TabBar nor a floating tab bar (a row of buttons, one selected) holds 'Menus'")
    }

    /// **A bar without the tab lists the buttons it holds.**
    @Test
    func aMissingTabListsTheBarsButtons() {
        #expect(TabStepRefusal.notFound(label: "X", tabs: ["Hub", "Rows"], bar: .floating)
            == "no tab 'X' in the floating tab bar; its buttons: Hub, Rows")
        #expect(TabStepRefusal.notFound(label: "X", tabs: ["Hub"], bar: .tabBar)
            == "no tab 'X' in the tab bar; its buttons: Hub")
    }

    /// **A covered tab is refused even when it reports itself selected (#95), a selected hittable one is not tapped (#106), any other is.**
    @Test
    func theActionFollowsHittabilityThenSelection() {
        #expect(TabStepAction.decide(label: "Summary", hittable: false, selected: true) == .refuse(TabStepRefusal.notHittable(label: "Summary")))
        #expect(TabStepAction.decide(label: "Summary", hittable: false, selected: false) == .refuse(TabStepRefusal.notHittable(label: "Summary")))
        #expect(TabStepAction.decide(label: "Summary", hittable: true, selected: true) == .landUntouched)
        #expect(TabStepAction.decide(label: "Summary", hittable: true, selected: false) == .tap)
    }
}
