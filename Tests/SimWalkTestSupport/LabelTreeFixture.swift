//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Small trees for the label rules: a screen, and controls placed on it one under another.
public struct LabelTreeFixture {
    /// An application holding the given children.
    public static func screen(_ children: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: children)
    }

    /// One element at `y`, 44 points tall, so two at different `y` are different frames.
    public static func element(
        _ type: String,
        label: String? = nil,
        identifier: String? = nil,
        y: Double,
        enabled: Bool = true,
        children: [AXNode] = []
    ) -> AXNode {
        AXNode(
            type: type,
            frame: AXNode.Frame(x: 16, y: y, width: 370, height: 44),
            label: label,
            identifier: identifier,
            isEnabled: enabled,
            children: children
        )
    }

    /// A bar of the given type (`TabBar`, `NavigationBar`) holding controls.
    public static func bar(_ type: String, _ children: [AXNode]) -> AXNode {
        AXNode(type: type, frame: AXNode.Frame(x: 0, y: 780, width: 402, height: 94), children: children)
    }
}
