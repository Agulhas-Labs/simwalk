//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds a screen state whose accessibility order runs against the visual one: VoiceOver reaches an element and its next stop is above it, or to its leading side on the same row.
///
/// The elements are the leaves that carry text and the controls, in tree order. Each adjacent pair is a step a VoiceOver user takes with one swipe, so an inversion is a step that goes backwards, reported once with both elements — a single misplaced element would otherwise be reported against every element it jumped.
///
/// **Conservative on purpose; four things are not inversions.**
/// - **Elements that overlap another element are dropped from the sequence.** A floating button over content, a badge on an icon, text laid over an image: their place in the reading order is a decision, and their frames say nothing about it.
/// - **A step to the upper right or upper left is not an inversion.** A backward step only counts in the same column (the frames share horizontal extent) or on the same row (they overlap vertically by half the shorter one). Two columns read one after the other end with a step up and across, and that is how columns are read.
/// - **The bars are left out**, as in the other rules, along with a `Toolbar` and the keyboard; they are read in their own place.
/// - **Right-to-left states are not judged.** "Leading" is the left edge only in a left-to-right layout, so a state whose slug carries a right-to-left locale (`loc_ar`, `loc_he`, `loc_fa`, `loc_ur` and the less common `iw`, `yi`, `ps`, `ckb`, `ug`) or the walkbook's own `layoutDirection: rtl` axis (a bare `rtl` segment, as in `light-rtl`) is skipped; the tree does not record the layout direction.
///
/// A control is one element whatever it contains: its children are what it says.
///
/// So is a labelled table cell with no enabled control below it (SimWalk#236): UIKit reads it as one element, so its children's order is never swiped, and it is not descended into. Its label need not carry the children's text.
///
/// "To its left" is judged only between elements on one row: their vertical overlap is at least half the taller one's height, or the taller is under three times the shorter (SimWalk#237). A paragraph with a picture beside it is not a line read out of order.
///
/// So is a labelled container that speaks for its text (SimWalk#105). A SwiftUI `.accessibilityElement(children: .combine)` is an `Other` labelled "Step 3 of 4, Setup" whose children are the StaticTexts "3" and "Setup": VoiceOver stops on the parent once and reads its label, so the order of the children inside it is never swiped. A non-control node with a non-blank label is one element, and is not descended into, when it has at least one text-carrying leaf, every such leaf's text (label, else value; trimmed) occurs in the node's own label, and no descendant is an enabled control. Anything short of that is collected child by child: text the label does not carry is a stop of its own, and a control inside is a stop of its own.
public struct ReadingOrderAudit: PerTreeLabelAuditRule {
    public static let name = AuditRuleName.readingOrder
    public static var findingNoun: String {
        "element"
    }

    public static var findingClause: String {
        "read before one that sits above or before it"
    }

    public static var examinedNoun: String {
        "element"
    }

    private static let skipped: Set<String> = ["TabBar", "NavigationBar", "Toolbar"]
    private static let controls = AuditedControl.types.union(["SecureTextField", "SearchField"])
    private static let rightToLeft: Set<String> = ["ar", "he", "fa", "ur", "iw", "yi", "ps", "ckb", "ug"]
    /// Points of slack when comparing edges, so two elements that touch are not ordered by rounding.
    private static let tolerance = 1.0

    public init() {}

    public func notApplicableReason(over captures: [BundleAuditScope.Capture], result _: LabelRuleResult) -> String {
        !captures.isEmpty && captures.allSatisfy { Self.isRightToLeft($0.stateSlug) } ? "only right-to-left states" : "no elements on any screen"
    }

    public func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult {
        guard !Self.isRightToLeft(stateSlug) else { return LabelRuleResult() }
        var found: [AXNode] = []
        collect(tree, screen: tree.screenBounds, into: &found)
        let sequence = found.enumerated().filter { index, element in
            !found.enumerated().contains { $0.offset != index && $0.element.frame.intersects(element.frame, tolerance: Self.tolerance) }
        }.map(\.element)

        var result = LabelRuleResult(examined: sequence.count)
        for (first, second) in zip(sequence, sequence.dropFirst()) {
            guard let position = Self.position(of: second, relativeTo: first) else { continue }
            let target = "\(second.type)\(second.label.map { " '\(AuditRowFormat.trim($0))'" } ?? "")"
            result.findings.append(LabelFinding(
                screenID: screenID,
                stateSlug: stateSlug,
                type: first.type,
                label: first.label,
                frame: first.frame,
                note: "read before \(target), which sits \(position)"
            ))
        }
        return result
    }

    private func collect(_ node: AXNode, screen: AXNode.Frame, into found: inout [AXNode]) {
        if Self.skipped.contains(node.type) || ScreenIdentifier.isKeyboard(node) {
            return
        }
        let isControl = Self.controls.contains(node.type)
        let carriesText = node.children.isEmpty && (!AuditedControl.isBlank(node.label) || !AuditedControl.isBlank(node.value))
        let isOneStop = !isControl && (Self.speaksForItsText(node) || Self.isLabelledCellWithoutControl(node))
        if isControl && node.isEnabled || carriesText || isOneStop, node.frame.isOnScreen(screen) {
            found.append(node)
        }
        if !isControl {
            if isOneStop {
                return
            }
            for child in node.children {
                collect(child, screen: screen, into: &found)
            }
        }
    }

    /// Whether a labelled container is one VoiceOver stop that reads all the text inside it (SimWalk#105): its label carries every text leaf below, and nothing below is an enabled control.
    private static func speaksForItsText(_ node: AXNode) -> Bool {
        guard !node.children.isEmpty, !AuditedControl.isBlank(node.label), let label = node.label else { return false }
        var leafTexts: [String] = []
        guard gatherLeafTexts(node.children, into: &leafTexts) else { return false }
        return !leafTexts.isEmpty && leafTexts.allSatisfy { label.contains($0) }
    }

    /// Whether a labelled table cell is one VoiceOver stop (SimWalk#236): UIKit reads a cell with a label as a single element unless it holds a control, so the order of its children is never swiped. Unlike `speaksForItsText`, the label need not carry the children's text (an icon's symbol name is not in it).
    private static func isLabelledCellWithoutControl(_ node: AXNode) -> Bool {
        var leafTexts: [String] = []
        return node.type == "Cell" && !node.children.isEmpty && !AuditedControl.isBlank(node.label) && gatherLeafTexts(node.children, into: &leafTexts)
    }

    /// Collects the trimmed text of each text-carrying leaf below, or reports `false` at the first enabled control.
    private static func gatherLeafTexts(_ nodes: [AXNode], into texts: inout [String]) -> Bool {
        for node in nodes {
            if controls.contains(node.type), node.isEnabled {
                return false
            }
            if node.children.isEmpty {
                let source = AuditedControl.isBlank(node.label) ? node.value : node.label
                if let source, !AuditedControl.isBlank(source) {
                    texts.append(source.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else if !gatherLeafTexts(node.children, into: &texts) {
                return false
            }
        }
        return true
    }

    /// Where `later` sits relative to `earlier` when it is visually before it, or nothing when the step is not backwards.
    private static func position(of later: AXNode, relativeTo earlier: AXNode) -> String? {
        let a = earlier.frame
        let b = later.frame
        // "To its left" is judged only on one row: a picture beside a paragraph three or more times its height is not a line read out of order (SimWalk#237), while a title beside a taller button still is.
        if b.verticalOverlap(with: a) >= 0.5 * min(a.height, b.height) {
            let isOneRow = b.verticalOverlap(with: a) >= 0.5 * max(a.height, b.height) || max(a.height, b.height) < 3 * min(a.height, b.height)
            return isOneRow && b.maxX <= a.minX + tolerance ? "to its left" : nil
        }
        if b.maxY <= a.minY + tolerance, b.horizontalOverlap(with: a) > 0 {
            return "above it"
        }
        return nil
    }

    private static func isRightToLeft(_ stateSlug: String) -> Bool {
        stateSlug.split(separator: "-").contains { segment in
            if segment == "rtl" {
                return true
            }
            guard segment.hasPrefix("loc_") else { return false }
            let language = segment.dropFirst(4).prefix { $0 != "_" }
            return rightToLeft.contains(String(language))
        }
    }
}
