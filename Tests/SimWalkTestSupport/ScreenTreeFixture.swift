//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// Screen trees shaped the way the runner's real captures of a SwiftUI app are, with every name and line of text invented.
///
/// The shape is the part that matters and the part the earlier fixtures got backwards: the application root (labelled with the app's name, never identified) over a window; inside it the navigation bar **ahead of** the content in tree order; the content a full-screen wrapper over a scroll view, whose first descendant is an image the system identifies (`AdditionalDimmingOverlay`); and after all of it a tab bar with **no identifier of its own**, whose items are labelled buttons over images carrying their symbol names. The identifiers that are not the app's own — the dimming overlay, the symbol names, SwiftUI's hosting class on an untitled navigation bar — are spelled as the system spells them, because they are exactly what a lookup must not return.
public struct ScreenTreeFixture {
    /// The 402 × 874 pt frame every tree is rooted at — the viewport a 1206 × 2622 px screenshot shows.
    public static let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    /// SwiftUI's hosting class name, which a navigation bar carries as its identifier when the stack has no title.
    public static var hostingClassName: String {
        "_TtGC7SwiftUI32NavigationStackHosting"
    }

    /// The application root over one window: the screen stack (`bar`, then `content`, then any `overlays` such as a toolbar), then the tab bar's own region, then anything `presented` over the lot — and after that window, any further `windows` (the keyboard's, a toast's).
    public static func app(bar: AXNode? = nil, content: AXNode, overlays: [AXNode] = [], presented: [AXNode] = [], windows: [AXNode] = []) -> AXNode {
        application(
            window: [
                AXNode(type: "Other", frame: screenFrame, children: [bar].compactMap(\.self) + [content] + overlays),
                AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83), children: [tabBar()]),
            ] + presented,
            windows: windows
        )
    }

    /// The application root over the app's own window holding `window`, then any further `windows` — for a tree whose window holds something other than a tab-bar screen stack, such as a presentation that took the covered screen out of the tree.
    public static func application(window: [AXNode], windows: [AXNode] = []) -> AXNode {
        AXNode(type: "Application", frame: screenFrame, label: "Example", children: [AXNode(type: "Window", frame: screenFrame, children: window)] + windows)
    }

    /// A navigation bar as a real one sits: `identifier` its title or ``hostingClassName``, a back button, and — when `trailing` is given — a trailing button mirrored by an `Other` of the same label and symbol identifier around it.
    public static func navigationBar(identifier: String, back: String, trailing: String? = nil) -> AXNode {
        let backButton = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 62, width: 44, height: 44), label: back, identifier: "BackButton")
        let trailingButton = trailing.map { label in
            AXNode(
                type: "Other",
                frame: AXNode.Frame(x: 346, y: 66, width: 36, height: 36),
                label: label,
                identifier: "square.and.arrow.up",
                children: [
                    AXNode(type: "Button", frame: AXNode.Frame(x: 350, y: 66, width: 29, height: 36), label: label, identifier: "square.and.arrow.up"),
                ]
            )
        }
        return AXNode(
            type: "NavigationBar",
            frame: AXNode.Frame(x: 0, y: 62, width: 402, height: 54),
            identifier: identifier,
            children: [backButton] + [trailingButton].compactMap(\.self)
        )
    }

    /// A screen's content: a full-screen wrapper over a scroll view — identified `identifier` when the app sets one — whose first descendant is the system's dimming-overlay image, then one static text per entry of `texts` (40 pt apart from y 132), then a disclosure chevron image.
    public static func content(identifier: String?, texts: [String]) -> AXNode {
        AXNode(
            type: "Other",
            frame: screenFrame,
            children: [
                AXNode(
                    type: "ScrollView",
                    frame: screenFrame,
                    identifier: identifier,
                    children: [
                        AXNode(
                            type: "Other",
                            frame: screenFrame,
                            children: [AXNode(type: "Image", frame: AXNode.Frame(x: -120, y: 731, width: 642, height: 286), identifier: "AdditionalDimmingOverlay")]
                        ),
                        AXNode(
                            type: "Other",
                            frame: AXNode.Frame(x: 0, y: 116, width: 402, height: 700),
                            children: texts.enumerated().map { index, text in
                                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 132 + Double(index) * 40, width: 300, height: 16), label: text)
                            } + [
                                AXNode(type: "Image", frame: AXNode.Frame(x: 363, y: 132, width: 8, height: 14), label: "Forward", identifier: "chevron.right"),
                            ]
                        ),
                    ]
                ),
            ]
        )
    }

    /// A toolbar as a real one sits: full-screen, after the content, identified and labelled with the literal word `Toolbar` on every screen.
    public static func toolbar() -> AXNode {
        AXNode(type: "Toolbar", frame: screenFrame, label: "Toolbar", identifier: "Toolbar")
    }

    /// A tab bar as every real one is: no identifier of its own, labelled `Tab Bar`, its items labelled buttons over images carrying their symbol names (and labels of their own) — so every identifier under it is on an item, and the same on every screen.
    public static func tabBar() -> AXNode {
        AXNode(
            type: "TabBar",
            frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83),
            label: "Tab Bar",
            children: [
                AXNode(
                    type: "Other",
                    frame: AXNode.Frame(x: 21, y: 791, width: 360, height: 62),
                    children: [("Home", "house.fill", "house"), ("Log", "list.bullet", "List")].enumerated().map { index, item in
                        AXNode(
                            type: "Button",
                            frame: AXNode.Frame(x: 25 + Double(index) * 180, y: 795, width: 170, height: 54),
                            label: item.0,
                            children: [AXNode(type: "Image", frame: AXNode.Frame(x: 60 + Double(index) * 180, y: 802, width: 30, height: 26), label: item.2, identifier: item.1)]
                        )
                    }
                ),
            ]
        )
    }

    /// An alert over the screen, as XCUITest types one: `title` as its label and its text, one button, and `identifier` when the app set one.
    public static func alert(title: String, identifier: String? = nil) -> AXNode {
        AXNode(
            type: "Alert",
            frame: AXNode.Frame(x: 36, y: 340, width: 330, height: 190),
            label: title,
            identifier: identifier,
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 56, y: 360, width: 290, height: 22), label: title),
                AXNode(type: "Button", frame: AXNode.Frame(x: 36, y: 480, width: 330, height: 50), label: "OK"),
            ]
        )
    }
}
