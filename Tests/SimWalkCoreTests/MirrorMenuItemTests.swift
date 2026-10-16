//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The View menu items a mirror call may click are exactly two, named by the menu's own titles.
struct MirrorMenuItemTests {
    /// Home Screen and App Switcher, spelled `home` and `switcher`, and nothing else.
    @Test
    func theMenuHasExactlyTheTwoItems() {
        let items = MirrorMenuItem.allCases

        #expect(items == [.homeScreen, .appSwitcher])
        #expect(items.map(\.title) == ["Home Screen", "App Switcher"])
        #expect(items.map(\.spelling) == ["home", "switcher"])
    }
}
