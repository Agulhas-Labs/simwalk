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
///
/// **Runs inside a web view are not compared with each other** (SimWalk#229): a page's run reports the bounding box of a run that wraps over several lines, starting mid-line after the words before it, so frames overlap where no glyphs do. They are still checked against the screen's width. **The price is a miss:** a real overlap of web text is not reported.
///
/// Two further pairs are not overlaps (SimWalk#238): a run whose label contains a sibling's and whose frame contains that sibling's is the combined label of an element and its own part; and a vertical overlap no deeper than a third of the shorter run's height is line-box slack between stacked lines.
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

    /// The most a vertical overlap may be and still count as line-box slack, in points: about a quarter of one line at accessibility sizes (SimWalk#238).
    private static let slackLimit = 12.0

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
        visit(CellsNotLaidOut.removed(from: tree), screen: tree.screenBounds, screenID: screenID, stateSlug: stateSlug, insideWebView: false, into: &result)
        return result
    }

    private func visit(_ node: AXNode, screen: AXNode.Frame, screenID: String, stateSlug: String, insideWebView: Bool, into result: inout LabelRuleResult) {
        // The keyboard is input laid over the screen, not the screen being judged (an input view the app draws itself included): its suggestion words are not the app's text (SimWalk#215).
        guard !ScreenIdentifier.isKeyboard(node) else { return }
        let runs = node.children.filter(Self.isTextRun)
        result.examined += runs.count
        var notes: [[String]] = Array(repeating: [], count: runs.count)
        for (index, run) in runs.enumerated() where run.frame.maxX > screen.maxX + Self.tolerance || run.frame.minX < screen.minX - Self.tolerance {
            notes[index].append("extends past the screen's width")
        }
        let inWebView = insideWebView || node.type == Self.webViewType
        let comparable = runs.map { !inWebView && !Self.reportsContainerFrame($0, in: node) }
        for (index, run) in runs.enumerated() where comparable[index] {
            var overlaps: [String] = []
            for otherIndex in (index + 1) ..< runs.count where comparable[otherIndex] {
                let other = runs[otherIndex]
                guard other.frame != run.frame, Self.collide(run, other) else { continue }
                overlaps.append("overlaps '\(AuditRowFormat.trim(other.label ?? ""))' \(Self.extent(of: other.frame))")
            }
            // The run's own extent leads, once, so the two heights say which of a pair is the tall one (SimWalk#142).
            if let first = overlaps.first {
                overlaps[0] = "\(Self.extent(of: run.frame)) \(first)"
                notes[index].append(contentsOf: overlaps)
            }
        }
        // One finding per run, so a run that overflows and overlaps, or overlaps two siblings, is counted once.
        for (run, runNotes) in zip(runs, notes) where !runNotes.isEmpty {
            result.findings.append(finding(run, screenID: screenID, stateSlug: stateSlug, note: runNotes.joined(separator: "; ")))
        }
        for child in node.children {
            visit(child, screen: screen, screenID: screenID, stateSlug: stateSlug, insideWebView: inWebView, into: &result)
        }
    }

    /// The marker in a note that names an overlap, which the audit's text answer reads to point at the frames (SimWalk#142).
    static var overlapMarker: String {
        " overlaps '"
    }

    /// A frame's vertical extent as the note prints it: `y 2735–3232 (497 pt)`.
    private static func extent(of frame: AXNode.Frame) -> String {
        "y \(AuditRowFormat.round(frame.y))–\(AuditRowFormat.round(frame.y + frame.height)) (\(AuditRowFormat.round(frame.height)) pt)"
    }

    /// Whether a run's frame is its parent's, so it reports the container rather than its glyphs.
    private static func reportsContainerFrame(_ run: AXNode, in parent: AXNode) -> Bool {
        let a = run.frame
        let b = parent.frame
        return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// The type of a web view, whose page text the tree lists as runs (as `ScrollSearch` also reads it).
    private static var webViewType: String {
        "WebView"
    }

    /// Whether two runs' frames collide (SimWalk#238).
    ///
    /// They overlap by more than a point across and by more than a third of the shorter run's height down (at most 12 pt, so tall wrapped runs still collide), since a shallower overlap is line-box slack between stacked lines. Not when one is the combined label of an element and its own part.
    private static func collide(_ run: AXNode, _ other: AXNode) -> Bool {
        let shorter = min(run.frame.height, other.frame.height)
        guard run.frame.horizontalOverlap(with: other.frame) > tolerance,
              run.frame.verticalOverlap(with: other.frame) > max(tolerance, min(shorter / 3, slackLimit)) else { return false }
        return !isCombinedLabel(run, other) && !isCombinedLabel(other, run)
    }

    /// Whether `whole` carries `part`'s label in a frame that contains `part`'s: the label of an element and one of its own parts, laid out together (SimWalk#238).
    private static func isCombinedLabel(_ whole: AXNode, _ part: AXNode) -> Bool {
        guard let wholeLabel = whole.label, let partLabel = part.label else { return false }
        return wholeLabel.contains(partLabel) && whole.frame.contains(part.frame, tolerance: tolerance)
    }

    private static func isTextRun(_ node: AXNode) -> Bool {
        node.type == "StaticText" && node.frame.hasArea && !AuditedControl.isBlank(node.label)
    }

    private func finding(_ run: AXNode, screenID: String, stateSlug: String, note: String) -> LabelFinding {
        LabelFinding(screenID: screenID, stateSlug: stateSlug, type: run.type, label: run.label, frame: run.frame, note: note)
    }
}
