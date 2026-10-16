//
// Copyright © Agulhas Labs
//

import Foundation

/// What a `tab` step says when it will not tap (SimWalk#95).
public struct TabStepRefusal {
    /// The reason for a tab whose button is in the tree but cannot be hit: something covers the tab bar, such as a modal sheet over the app.
    ///
    /// Said in the core so the runner builds no string, and so a test holds the wording.
    public static func notHittable(label: String) -> String {
        "the tab bar's '\(label)' button is in the tree but not hittable: something is over it, such as a modal sheet, so the tab was not tapped"
    }

    /// The reason for a tab no bar on screen holds (SimWalk#109): it names the bar that was seen and the buttons it held, so a misspelt label or a screen with no bar reads differently.
    public static func notFound(label: String, tabs: [String], bar: TabTarget.Bar?) -> String {
        switch bar {
        case nil:
            "no tab bar on screen: neither a TabBar nor a floating tab bar (a row of buttons, one selected) holds '\(label)'"
        case .tabBar?:
            "no tab '\(label)' in the tab bar; its buttons: \(tabs.joined(separator: ", "))"
        case .floating?:
            "no tab '\(label)' in the floating tab bar; its buttons: \(tabs.joined(separator: ", "))"
        }
    }
}
