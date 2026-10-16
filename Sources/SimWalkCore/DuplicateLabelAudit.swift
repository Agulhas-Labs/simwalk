//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds two distinct enabled controls on one screen state that answer to the same label.
///
/// VoiceOver lands on `Connect` and `Connect` and the user cannot tell which service either one connects; a test that queries by label gets the first and never the second. It is a finding about the app, not the screen's design, so it wants a differentiating label (`Connect Strava`) or an identifier.
///
/// **Two calibrations, both from real bundles.**
/// - **Distinct means a different frame.** Apple's Settings lists its `Dictate` button twice in one hierarchy at the same frame and identifier — one element reached by two paths, not two controls, and the search field's dictation button is not a defect. Controls sharing a label *and* a frame are counted once.
/// - **Controls inside a `TabBar` or `NavigationBar` are left out.** A tab named `Browse` and a back button named `Browse` on a detail screen are how a navigation stack reads, and a tab bar repeats on every screen by construction; including them fired on every detail screen of a real app's walks. Two same-named buttons in the bar of one screen would be missed, which is the price of not flagging every push.
public struct DuplicateLabelAudit: LabelAuditRule {
    public static let name = AuditRuleName.duplicateLabel
    public static var findingNoun: String {
        "label"
    }

    public static var findingClause: String {
        "shared by distinct controls on one screen"
    }

    public init() {}

    public func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult {
        var result = LabelRuleResult()
        var order: [String] = []
        var byLabel: [String: [AXNode]] = [:]
        let screen = tree.screenBounds
        for control in AuditedControl.all(in: tree) where control.isEnabledControl && !control.insideBar && control.node.frame.isOnScreen(screen) {
            guard let label = control.node.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else { continue }
            if byLabel[label]?.contains(where: { $0.frame == control.node.frame }) == true {
                continue
            }
            if byLabel[label] == nil {
                order.append(label)
            }
            byLabel[label, default: []].append(control.node)
            result.examined += 1
        }
        for label in order {
            guard let nodes = byLabel[label], let first = nodes.first, nodes.count > 1 else { continue }
            result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: first.type, label: label, frame: first.frame, note: "×\(nodes.count)"))
        }
        return result
    }
}
