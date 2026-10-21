//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds text drawn cut short with an ellipsis: a `StaticText` labelled `Notifications` that the screenshot shows as `Notific…`.
///
/// **Why SimWalk has its own rule.** Apple's `textClipped` is not reliable for this: on a specimen whose titles read `Notific…` and `Langu…` at an accessibility size it flagged one of the two, flagged that one again where it is whole, and fired issues with no element on a clean screen. The tree cannot say either, because the label is the full string whatever is drawn. The only evidence is the pixels.
///
/// **What it does.** One recognition per capture, never per element. For each `StaticText` with a label whose frame lies wholly on screen, the recognised lines whose box centre falls inside the frame are joined in reading order with single spaces. It is a finding only when that text ends in `…` or `...`, has something before the ellipsis, and what precedes the ellipsis is a strict prefix of the label (runs of whitespace collapsed on both sides, case-sensitive). Recognition noise cannot fake a prefix followed by an ellipsis, so text that was merely misread is not a finding.
///
/// **What it cannot tell.** A label that is deliberately fuller than the text drawn, such as a `Loading…` placeholder over the label `Loading your library` or a message preview cut by design, reads as truncation at every size, so it says nothing about what a larger type size did. Text drawn in a different case from its label, such as an uppercased section header, is not matched, so it is never a finding.
///
/// **Not every capture is checked.** Without a recogniser the rule examined nothing and its heading says so (never `clean`); a capture whose screenshot is missing or unreadable is counted as not checked.
public struct TruncatedTextAudit: LabelAuditRule {
    public static let name = AuditRuleName.truncatedText

    public static var findingNoun: String {
        "text run"
    }

    public static var findingClause: String {
        "drawn truncated with an ellipsis"
    }

    public static var examinedNoun: String {
        "text run"
    }

    private let recognizer: (any ScreenTextRecognizing)?

    public init(recognizer: (any ScreenTextRecognizing)?) {
        self.recognizer = recognizer
    }

    public func notApplicableReason(over captures: [BundleAuditScope.Capture], result: LabelRuleResult) -> String {
        if recognizer == nil {
            return "no text recognizer on this face, so the rule did not run"
        }
        return !captures.isEmpty && result.unchecked == captures.count ? "no capture's screenshot could be read" : "no text runs on any screen"
    }

    public func evaluate(_ captures: [BundleAuditScope.Capture]) -> LabelRuleResult {
        var result = LabelRuleResult()
        for capture in captures {
            guard let recognizer, let url = capture.screenshotURL, let lines = try? recognizer.lines(inPNGAt: url) else {
                if recognizer != nil {
                    result.unchecked += 1
                }
                continue
            }
            result.absorb(evaluate(capture.tree, lines: lines, screenID: capture.screenID, stateSlug: capture.stateSlug))
        }
        return result
    }

    /// The rule over one tree and the lines recognised in its screenshot.
    func evaluate(_ tree: AXNode, lines: [MirrorTextLine], screenID: String, stateSlug: String) -> LabelRuleResult {
        let screen = tree.screenBounds
        var result = LabelRuleResult()
        for run in tree.flattened where Self.isTextRun(run, within: screen) {
            result.examined += 1
            let drawn = Self.text(drawnIn: run.frame, of: lines, screen: screen)
            guard Self.isTruncation(drawn, of: run.label ?? "") else { continue }
            result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: run.type, label: run.label, frame: run.frame, note: "reads \"\(drawn)\""))
        }
        return result
    }

    private static func isTextRun(_ node: AXNode, within screen: AXNode.Frame) -> Bool {
        let frame = node.frame
        return node.type == "StaticText" && !AuditedControl.isBlank(node.label) && frame.hasArea
            && frame.minX >= screen.minX && frame.maxX <= screen.maxX && frame.y >= screen.y && frame.maxY <= screen.maxY
    }

    /// The recognised lines centred inside `frame`, in reading order, as one string.
    private static func text(drawnIn frame: AXNode.Frame, of lines: [MirrorTextLine], screen: AXNode.Frame) -> String {
        let inside = lines.filter { line in
            let x = screen.x + line.centreX * screen.width
            let y = screen.y + line.centreY * screen.height
            return x >= frame.minX && x <= frame.maxX && y >= frame.y && y <= frame.maxY
        }
        return MirrorRead.readingOrder(inside).map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `drawn` is a strict prefix of `label` followed by an ellipsis.
    static func isTruncation(_ drawn: String, of label: String) -> Bool {
        guard let stem = withoutEllipsis(drawn) else { return false }
        let head = collapsed(stem)
        // A label that ends in an ellipsis of its own (`Learn more…`) drawn whole reads the same, so the comparison is against the label without it.
        let full = collapsed(withoutEllipsis(label) ?? label)
        return !head.isEmpty && full.count > head.count && full.hasPrefix(head)
    }

    /// The text before a trailing `…` or `...`, or nothing when it does not end in one.
    private static func withoutEllipsis(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("…") {
            return String(trimmed.dropLast())
        }
        return trimmed.hasSuffix("...") ? String(trimmed.dropLast(3)) : nil
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
