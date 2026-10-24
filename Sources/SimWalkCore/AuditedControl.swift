//
// Copyright © Agulhas Labs
//

import Foundation

/// A node the label rules may judge, with the two facts about its surroundings they need.
struct AuditedControl {
    let node: AXNode
    /// The nearest enclosing `Button`, if any — an image inside one is that button's glyph.
    let enclosingButton: AXNode?
    /// The nearest enclosing enabled control of any of `types` — SwiftUI nests the platform's own control inside the one it labels (SimWalk#112, SimWalk#102).
    let enclosingControl: AXNode?
    /// Whether it sits inside a tab bar or navigation bar, which repeat from screen to screen.
    let insideBar: Bool

    /// The types whose label a user hears when they land on them.
    static let types: Set<String> = ["Button", "Link", "Switch", "Slider", "TextField"]

    /// Every node in the tree, in tree order, with the context it was found in.
    static func all(in tree: AXNode) -> [AuditedControl] {
        var found: [AuditedControl] = []
        collect(tree, button: nil, control: nil, insideBar: false, into: &found)
        return found
    }

    /// Whether the node is an enabled control of one of `types`.
    ///
    /// A disabled one is a control the app is deliberately offering as unavailable, and is not what these rules are about.
    var isEnabledControl: Bool {
        node.isEnabled && Self.types.contains(node.type)
    }

    /// Whether there is nothing here a screen reader could say.
    static func isBlank(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private static let bars: Set<String> = ["TabBar", "NavigationBar"]

    private static func collect(_ node: AXNode, button: AXNode?, control: AXNode?, insideBar: Bool, into found: inout [AuditedControl]) {
        // The keyboard is input laid over the screen, not the screen being judged (SimWalk#215): its keys and suggestion words are not the app's labels.
        guard !ScreenIdentifier.isKeyboard(node) else { return }
        found.append(AuditedControl(node: node, enclosingButton: button, enclosingControl: control, insideBar: insideBar))
        let childButton = node.type == "Button" ? node : button
        let childControl = node.isEnabled && types.contains(node.type) ? node : control
        let childInsideBar = insideBar || bars.contains(node.type)
        for child in node.children {
            collect(child, button: childButton, control: childControl, insideBar: childInsideBar, into: &found)
        }
    }
}
