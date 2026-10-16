//
// Copyright © Agulhas Labs
//

import Foundation

/// The iPhone Mirroring View menu items SimWalk may click, and no others (Brief §8 "Never keystrokes").
///
/// **An enum, never a free string,** so no other menu item can be clicked: navigation goes through this menu because a keystroke sent to the wrong window does damage, and a free title would reopen the door the ban on keystrokes shut. The raw values are the menu's own English titles; a Mac in another language names them differently, and the click refuses rather than guessing a translation.
public enum MirrorMenuItem: String, CaseIterable, Sendable {
    /// "Home Screen".
    ///
    /// From the App Switcher it first lands in the last app, so it takes a second press, which the caller makes, not SimWalk.
    case homeScreen = "Home Screen"
    /// "App Switcher".
    case appSwitcher = "App Switcher"

    /// The menu's own title, which the System Events click names.
    public var title: String {
        rawValue
    }

    /// How the command line and the MCP tool spell it (`menu home|switcher`): short, and free of the space a shell would split on.
    public var spelling: String {
        switch self {
        case .homeScreen:
            "home"
        case .appSwitcher:
            "switcher"
        }
    }
}
