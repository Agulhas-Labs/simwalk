//
// Copyright © Agulhas Labs
//

import Foundation

/// The back control a screen offers, or `nil` when it has none — the one place `discover` decides whether a `back` step returns from a screen.
///
/// **What the runner taps, held to being a back control.** A `back` step taps the first button in the app's navigation bars (`app.navigationBars.buttons.firstMatch`), so a screen has a back control only when that button is the system's back button, which carries the identifier `BackButton` in UIKit and SwiftUI alike. A root screen's first bar button is something else — `Edit`, `Add` — and a `back` sent there would tap it, so such a screen is returned to by a relaunch and the route replayed instead.
public struct DiscoverBackButton {
    /// The identifier the system gives a navigation bar's back button.
    static var identifier: String {
        "BackButton"
    }

    /// The tree's back control: the first `Button` of its first `NavigationBar`, when that button is the system back button.
    public static func of(_ tree: AXNode) -> AXNode? {
        guard let bar = tree.flattened.first(where: { $0.type == "NavigationBar" }) else { return nil }
        guard let first = bar.flattened.dropFirst().first(where: { $0.type == "Button" }) else { return nil }
        return first.identifier == identifier ? first : nil
    }
}
