//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds text that does not fit at an accessibility Dynamic Type size: a run reaching past the screen's width, or two sibling runs whose frames overlap.
///
/// **Judged only in states whose slug carries an accessibility size** (`dt_uictcontentsizecategoryaccessibility…`). At a default size a run past the edge is a deliberate marquee or a horizontally scrolling row; at 200% type that same run is text nobody can read, which is the failure this rule exists for. A state at any other size is not examined, so the same overflow there is not a finding.
///
/// A text run is a `StaticText` with a label. Two runs overlap when they share more than a point in both directions; runs with identical frames are one element listed twice and are left alone, as in `duplicateLabel`. Only siblings are compared: a label inside a card and the card's title are laid out by different containers.
///
/// **A run whose frame is its parent's is left out of the overlap comparison, on both sides** (SimWalk#100). SwiftUI reports a `.frame(maxWidth: .infinity)` text, and a Button's `StaticText` children, by the container's frame rather than the glyphs', so such a run's frame says nothing about where its text is: it would "overlap" the chevron that sits inside the row by design, or the sibling stacked above it. It is still examined and still checked against the screen's width. Frames match within the same one-point tolerance on x, y, width and height. **The price is a miss** (SimWalk#118 item 5): a badge drawn by `.overlay` on such a text has nothing left to be compared against, so a badge covering its text at large type is not flagged.
public struct LargeTypeOverflowAudit: PerTreeLabelAuditRule {
    public static let name = AuditRuleName.largeTypeOverflow
    public static var findingNoun: String {
        "text run"
    }

    public static var findingClause: String {
        "overflowing the screen or another run at an accessibility type size"
    }

    public static var examinedNoun: String {
        "text run"
    }

    /// Points of slack, so an edge that lands on the boundary by rounding is not an overflow.
    private static let tolerance = 1.0

    public init() {}

    /// Whether a state slug names an accessibility Dynamic Type size.
    static func isAccessibilitySize(_ stateSlug: String) -> Bool {
        stateSlug.split(separator: "-").contains { $0.hasPrefix("dt_") && $0.contains("accessibility") }
    }

    /// Whether a state slug names no Dynamic Type size, so the capture was taken at the default one.
    static func isDefaultSize(_ stateSlug: String) -> Bool {
        !stateSlug.split(separator: "-").contains { $0.hasPrefix("dt_") }
    }

    public func notApplicableReason(over captures: [BundleAuditScope.Capture], result _: LabelRuleResult) -> String {
        captures.contains { Self.isAccessibilitySize($0.stateSlug) } ? "no text runs on any screen" : "no accessibility type-size state"
    }

    public func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult {
        guard Self.isAccessibilitySize(stateSlug) else { return LabelRuleResult() }
        var result = LabelRuleResult()
        visit(tree, screen: tree.screenBounds, screenID: screenID, stateSlug: stateSlug, into: &result)
        return result
    }

    private func visit(_ node: AXNode, screen: AXNode.Frame, screenID: String, stateSlug: String, into result: inout LabelRuleResult) {
        let runs = node.children.filter(Self.isTextRun)
        result.examined += runs.count
        var notes: [[String]] = Array(repeating: [], count: runs.count)
        for (index, run) in runs.enumerated() where run.frame.maxX > screen.maxX + Self.tolerance || run.frame.minX < screen.minX - Self.tolerance {
            notes[index].append("extends past the screen's width")
        }
        let comparable = runs.map { !Self.reportsContainerFrame($0, in: node) }
        for (index, run) in runs.enumerated() where comparable[index] {
            for otherIndex in (index + 1) ..< runs.count where comparable[otherIndex] {
                let other = runs[otherIndex]
                guard other.frame != run.frame, other.frame.intersects(run.frame, tolerance: Self.tolerance) else { continue }
                notes[index].append("overlaps '\(AuditRowFormat.trim(other.label ?? ""))'")
            }
        }
        // One finding per run, so a run that overflows and overlaps, or overlaps two siblings, is counted once.
        for (run, runNotes) in zip(runs, notes) where !runNotes.isEmpty {
            result.findings.append(finding(run, screenID: screenID, stateSlug: stateSlug, note: runNotes.joined(separator: "; ")))
        }
        for child in node.children {
            visit(child, screen: screen, screenID: screenID, stateSlug: stateSlug, into: &result)
        }
    }

    /// Whether a run's frame is its parent's, so it reports the container rather than its glyphs.
    private static func reportsContainerFrame(_ run: AXNode, in parent: AXNode) -> Bool {
        let a = run.frame
        let b = parent.frame
        return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func isTextRun(_ node: AXNode) -> Bool {
        node.type == "StaticText" && node.frame.hasArea && !AuditedControl.isBlank(node.label)
    }

    private func finding(_ run: AXNode, screenID: String, stateSlug: String, note: String) -> LabelFinding {
        LabelFinding(screenID: screenID, stateSlug: stateSlug, type: run.type, label: run.label, frame: run.frame, note: note)
    }
}
