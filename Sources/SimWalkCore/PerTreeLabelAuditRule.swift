//
// Copyright © Agulhas Labs
//

import Foundation

/// A label rule that judges one capture's tree on its own and needs no peers and no pixels.
public protocol PerTreeLabelAuditRule: LabelAuditRule {
    /// The rule's findings in one tree, and how many controls it looked at to find them.
    func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult
}

public extension PerTreeLabelAuditRule {
    func evaluate(_ captures: [BundleAuditScope.Capture]) -> LabelRuleResult {
        var result = LabelRuleResult()
        for capture in captures {
            result.absorb(evaluate(capture.tree, screenID: capture.screenID, stateSlug: capture.stateSlug))
        }
        return result
    }
}
