//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds enabled controls a screen reader has nothing to say for: no label, and no identifier either.
///
/// A `Button`, `Link`, `Switch`, `Slider` or `TextField` that is enabled and carries neither is reachable and mute. The identifier counts as an escape on purpose — it is what a UI test addresses the control by, so a control that has one is a deliberately-built element with a label problem that a test can see, where a control with neither is an element nobody named at all.
///
/// **An `Image` counts only inside a `Button` that has no label of its own.** The first cut flagged every unlabelled image inside a button, and Apple's own Settings — a screen with no accessibility defect to find — drew ten findings on its root list, one per row: each row's icon is a decorative `Image` inside a `Button` labelled `General`, `Camera`, `Screen Time`, and the button's label is what is read. An image is the button's only voice exactly when the button has none, so that is when its being unlabelled is a finding.
///
/// **A button that is itself a finding is counted once.** A `Button` with no label and no identifier, holding an unlabelled `Image`, is one defective control; the image is a finding only under a button that has an identifier (so is not one), where the glyph is the part a user cannot hear.
///
/// **The inner control SwiftUI nests inside a labelled one is not examined.** A `Menu` row is a labelled `Button` with an unlabelled, unidentified `Button` of the same frame inside it (SimWalk#112); a `Toggle` is a labelled `Switch` with the platform's own unlabelled `Switch` inside it (SimWalk#102). No SwiftUI modifier reaches the inner one, and VoiceOver stops on the outer, so the inner is that control's part, not a second control. It is excused only when the enclosing control has a label (an identifier alone is no voice) and its frame contains the inner one's within a point; a control that merely sits somewhere inside a labelled one, outside its frame, is still examined.
///
/// **The bars are examined.** A `TabBar` or `NavigationBar` control with no label is a real defect (an unlabelled toolbar or back button), so this rule does not skip them, unlike the geometry rules.
public struct UnlabelledControlAudit: PerTreeLabelAuditRule {
    public static let name = AuditRuleName.unlabelledControl
    public static var findingNoun: String {
        "control"
    }

    public static var findingClause: String {
        "with neither a label nor an identifier"
    }

    public init() {}

    public func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult {
        var result = LabelRuleResult()
        for control in AuditedControl.all(in: tree) where Self.isCandidate(control) {
            result.examined += 1
            guard AuditedControl.isBlank(control.node.label), AuditedControl.isBlank(control.node.identifier) else { continue }
            result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: control.node.type, label: nil, frame: control.node.frame))
        }
        return result
    }

    private static func isCandidate(_ control: AuditedControl) -> Bool {
        if control.isEnabledControl {
            return !isPartOfLabelledControl(control)
        }
        guard control.node.type == "Image", control.node.isEnabled, let button = control.enclosingButton else { return false }
        return AuditedControl.isBlank(button.label) && !AuditedControl.isBlank(button.identifier)
    }

    /// Whether the control is the part SwiftUI nests inside an enclosing control that has a label and the same footprint.
    private static func isPartOfLabelledControl(_ control: AuditedControl) -> Bool {
        guard let outer = control.enclosingControl, !AuditedControl.isBlank(outer.label) else { return false }
        return outer.frame.contains(control.node.frame, tolerance: 1)
    }
}
