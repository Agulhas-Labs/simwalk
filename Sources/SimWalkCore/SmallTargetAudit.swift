//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds enabled controls whose frame is under 44×44 points, Apple's minimum for a touch target (Human Interface Guidelines).
///
/// **What counts as a target, decided from real bundles.**
/// - **The types are `Button`, `Link`, `Slider`, `TextField` and `SecureTextField`.** A `Switch` is left out: the system's own switch is a fixed 51×31 that Apple ships everywhere, a real app's 61×28 switches all sat in full-width rows, and flagging the platform control on every screen that has a toggle is noise no app can act on.
/// - **A control inside a `TabBar` or `NavigationBar` is left out**, as in the label rules: the bars are the system's, and repeat on every screen.
/// - **A control whose tappable area is its enclosing cell is left out.** Apple's Settings lists `About`, `Fonts` and `Keyboard` as 28-point-high buttons inside 53-point cells; the row is what the finger lands on. It holds only when the cell is at least 44×44, the control is the only target in it, and the control *is* the row: it shares the cell's label or identifier, or spans at least 80% of the cell's width. A 24×24 trailing Info button in a row of text, or a small button beside a `Switch`, is a small target in a big cell, and still fires; two small controls sharing a cell each need their own room.
/// - **A control nested inside another control, or inside a text field, is part of that one.** The `Dictate` button in Settings' search field is 17×22 and is the field's accessory; the field is the target.
/// - **An inline link is left out.** A `Link` sitting in a run of text (inside a `StaticText` or `TextView`, or overlapping one beside it) is as tall as a line of type by construction; padding a sentence is not the fix.
/// - **A disabled, zero-sized or off-screen control never fires.** Off-screen is judged against the root frame.
public struct SmallTargetAudit: PerTreeLabelAuditRule {
    public static let name = AuditRuleName.smallTarget
    public static var findingNoun: String {
        "control"
    }

    public static var findingClause: String {
        "smaller than 44×44 points"
    }

    /// Apple's minimum touch target edge, in points.
    static let minimumEdge = 44.0

    /// How far under `minimumEdge` an edge may fall and still count as 44.
    ///
    /// SwiftUI reports frames with float noise (`43.999999999999986`), which the audit would print as `44` under "smaller than 44×44" (SimWalk#115); no real layout is a hundredth of a point short.
    static let edgeTolerance = 0.01

    /// Whether an edge is genuinely under the minimum, past the float noise `edgeTolerance` allows for.
    static func isBelowMinimum(_ edge: Double) -> Bool {
        edge < minimumEdge - edgeTolerance
    }

    /// How much of its cell's width a control must span to be the row itself.
    private static let rowWidthFraction = 0.8
    private static let targetTypes: Set<String> = ["Button", "Link", "Slider", "TextField", "SecureTextField"]
    private static let bars: Set<String> = ["TabBar", "NavigationBar"]
    private static let fields: Set<String> = ["TextField", "SecureTextField", "SearchField"]
    private static let textTypes: Set<String> = ["StaticText", "TextView"]

    public init() {}

    public func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult {
        var result = LabelRuleResult()
        var seen: Set<String> = []
        var found: Set<String> = []
        visit(tree, ancestors: [], siblings: [], index: 0, screen: tree.screenBounds) { node, ancestors, identity in
            // iOS reports one element under two parents (the Apple Account sheet's table lists its button both inside a group and beside it); one element is
            // one target, examined once, and a finding when any copy of it is one — the copy inside a cell can be tapped through it where the copy beside it
            // cannot, and tree order says nothing about which the finger meets (SimWalk#75).
            if seen.insert(identity).inserted {
                result.examined += 1
            }
            guard Self.isBelowMinimum(node.frame.width) || Self.isBelowMinimum(node.frame.height),
                  !Self.isTappedThroughCell(node, ancestors: ancestors),
                  found.insert(identity).inserted else { return }
            let size = "\(AuditRowFormat.round(node.frame.width))×\(AuditRowFormat.round(node.frame.height)) pt"
            result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: node.type, label: node.label, frame: node.frame, note: size))
        }
        return result
    }

    /// Calls `examine` on every control that stands as a target of its own, whatever its size, with the identity that tells it from every other element.
    ///
    /// The identity is what the element shows — type, label, identifier, frame — and which of its look-alikes it is among its siblings: the copies of one element under two parents share it, and two elements that look the same side by side in one parent (two unlabelled buttons on one frame) do not (SimWalk#75). The parent itself is left out because it is what differs between the copies; look-alikes that are each also listed under a second parent pair up by that order.
    private func visit(_ node: AXNode, ancestors: [AXNode], siblings: [AXNode], index: Int, screen: AXNode.Frame, examine: (AXNode, [AXNode], String) -> Void) {
        if Self.bars.contains(node.type) {
            return
        }
        if isCandidate(node, ancestors: ancestors, siblings: siblings, screen: screen) {
            let shown = Self.shown(node)
            let ordinal = siblings[..<index].count { Self.shown($0) == shown }
            examine(node, ancestors, "\(shown)|\(ordinal)")
        }
        for (position, child) in node.children.enumerated() {
            visit(child, ancestors: ancestors + [node], siblings: node.children, index: position, screen: screen, examine: examine)
        }
    }

    /// What an element shows of itself, which the copies of one element reported under two parents share.
    private static func shown(_ node: AXNode) -> String {
        let frame = node.frame
        return "\(node.type)|\(node.label ?? "")|\(node.identifier ?? "")|\(frame.x)|\(frame.y)|\(frame.width)|\(frame.height)"
    }

    private func isCandidate(_ node: AXNode, ancestors: [AXNode], siblings: [AXNode], screen: AXNode.Frame) -> Bool {
        guard Self.targetTypes.contains(node.type), node.isEnabled, node.frame.isOnScreen(screen) else { return false }
        if ancestors.contains(where: { Self.targetTypes.contains($0.type) || Self.fields.contains($0.type) }) {
            return false
        }
        if node.type == "Link", isInline(node, ancestors: ancestors, siblings: siblings) {
            return false
        }
        return true
    }

    /// Whether the nearest enclosing cell is a full-size target with this control as the only one in it.
    private static func isTappedThroughCell(_ node: AXNode, ancestors: [AXNode]) -> Bool {
        guard let cell = ancestors.last(where: { $0.type == "Cell" }),
              !isBelowMinimum(cell.frame.width), !isBelowMinimum(cell.frame.height),
              cell.flattened.filter({ $0.isEnabled && targetTypes.contains($0.type) }).count == 1 else { return false }
        return isTheRow(node, cell: cell)
    }

    /// Whether the control is the row itself: it shares the cell's label or identifier, or spans most of the cell's width.
    private static func isTheRow(_ node: AXNode, cell: AXNode) -> Bool {
        if shares(node.label, cell.label) || shares(node.identifier, cell.identifier) {
            return true
        }
        return node.frame.width >= rowWidthFraction * cell.frame.width
    }

    private static func shares(_ first: String?, _ second: String?) -> Bool {
        guard !AuditedControl.isBlank(first), !AuditedControl.isBlank(second) else { return false }
        return first?.trimmingCharacters(in: .whitespacesAndNewlines) == second?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isInline(_ link: AXNode, ancestors: [AXNode], siblings: [AXNode]) -> Bool {
        if ancestors.contains(where: { Self.textTypes.contains($0.type) }) {
            return true
        }
        return siblings.contains { Self.textTypes.contains($0.type) && $0.frame.intersects(link.frame) }
    }
}
