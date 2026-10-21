//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a `DisclosureAffordanceAudit` verdict in the contract's shape.
///
/// The shape of the answer is the point: the finding is stated as a minority against a named majority, because "this row is not a Button" is only meaningful beside "and these nine with the same shape are". A reader who is told only the former has to go and find the latter, which is the twenty minutes this exists to save.
///
/// **It opens with the bundle it audited, not with what it found.** An audit is a verdict *over* something, and the header naming the build, the plan, the device and how much of the bundle settled is what tells a reader whether this verdict is about the app they think it is. What the audit could and could not look at then leads the residue, where it is a caveat with names in it rather than a figure — the figure is in the verdict.
public struct DisclosureAuditSummary {
    private let findings: DisclosureAffordanceAudit.Findings
    private let bundle: CaptureBundle

    public init(_ findings: DisclosureAffordanceAudit.Findings, of bundle: CaptureBundle) {
        self.findings = findings
        self.bundle = bundle
    }

    /// The answer, ready for a face to print or a log to price.
    public func answer() -> Answer {
        let controls = Self.distinct(findings.controlRows)
        let uncontrolled = Self.distinct(findings.uncontrolledRows)
        return Answer(
            header: CaptureBundleHeader.line(of: bundle),
            verdict: verdict(controls: controls.count, uncontrolled: uncontrolled.count),
            residue: residue(controls: controls, uncontrolled: uncontrolled),
            weighing: ContextSaving.weighing(bundle)
        )
    }

    /// The whole answer as text.
    public func render() -> String {
        answer().text
    }

    /// The finding, then everything that keeps it from being read as a verdict over the whole walk.
    ///
    /// A verdict over a subset of a walk is a verdict about that subset. "No disclosure rows found" over a bundle holding eight of eleven screens is not a finding about the app; it is a finding about the eight, and a reader who meets that sentence on its own has been told something untrue about the other three — so the shortfall is named in the verdict line and the screens themselves in the residue beneath it.
    private func verdict(controls: Int, uncontrolled: Int) -> AnswerVerdict {
        let coverage = AuditCoverageStatement(findings.coverage)
        return AnswerVerdict.reporting(qualifications: [Self.finding(controls: controls, uncontrolled: uncontrolled, in: findings)].compactMap(\.self) + coverage.qualifications, detail: coverage.audited)
    }

    /// What the caller has to look at: which screens the caveat is about, what was found, and the rows themselves.
    private func residue(controls: [Row], uncontrolled: [Row]) -> [String] {
        [AuditCoverageStatement(findings.coverage).line].compactMap(\.self) + sectionLines(controls: controls, uncontrolled: uncontrolled)
    }

    /// The rule's own account — what was found and the rows — without the coverage, which belongs to the bundle.
    ///
    /// Separate from \`residue\` so the combined \`bundle audit\` answer can put it under the rule's heading and state the coverage once.
    func sectionLines() -> [String] {
        sectionLines(controls: Self.distinct(findings.controlRows), uncontrolled: Self.distinct(findings.uncontrolledRows))
    }

    /// The rows the finding objects to, one per distinct row — empty unless the bundle types its disclosure rows inconsistently, which is when `finding()` states a count.
    var failingRows: [Row] {
        findings.isInconsistent ? Self.distinct(findings.uncontrolledRows) : []
    }

    /// The clause the verdict carries for this rule, when there is a finding at all.
    func finding() -> String? {
        Self.finding(controls: Self.distinct(findings.controlRows).count, uncontrolled: Self.distinct(findings.uncontrolledRows).count, in: findings)
    }

    private static func finding(controls: Int, uncontrolled: Int, in findings: DisclosureAffordanceAudit.Findings) -> String? {
        findings.isInconsistent ? "\(uncontrolled) of \(controls + uncontrolled) disclosure rows not typed as controls" : nil
    }

    private func sectionLines(controls: [Row], uncontrolled: [Row]) -> [String] {
        let all = controls.count + uncontrolled.count
        guard all > 0 else {
            return ["no disclosure rows found — no row in the screens this bundle holds draws a trailing chevron"]
        }
        guard findings.isInconsistent else {
            return [consistentLine(total: all)]
        }
        var lines = [
            "\(Self.rowCount(all)): \(controls.count) typed as controls, \(uncontrolled.count) not",
            "",
            "not typed as controls — reachable by sight, not by VoiceOver, Full Keyboard Access or a control query:",
        ]
        lines += Self.group(uncontrolled)
        lines += ["", "the same shape, typed as controls, in this bundle:"]
        lines += Self.group(controls, limit: 4)
        return lines
    }

    /// A uniform bundle is reported, not silently passed — "nothing found" and "nothing to compare against" are different answers, and only one of them means the check ran meaningfully.
    private func consistentLine(total: Int) -> String {
        findings.uncontrolledRows.isEmpty
            ? "\(Self.rowCount(total)), every one typed as a control — consistent"
            : "\(Self.rowCount(total)), none typed as a control — consistent, but nothing in this bundle establishes the convention, so this is not evidence they are correct"
    }

    /// Rows are counted as rows now that several captures of one collapse into it, so a bundle can honestly report one.
    private static func rowCount(_ count: Int) -> String {
        "\(count) disclosure row\(count == 1 ? "" : "s")"
    }

    /// One row per line, grouped under its screen, longest-serving order preserved.
    private static func group(_ rows: [Row], limit: Int? = nil) -> [String] {
        var lines: [String] = []
        for (screen, screenRows) in AuditRowFormat.screensInOrder(rows, screen: { $0.screenID }) {
            let shown = limit.map { Array(screenRows.prefix($0)) } ?? screenRows
            lines.append("  \(screen):")
            for row in shown {
                lines.append("    \(row.type) '\(AuditRowFormat.trim(row.label))' [\(row.states.joined(separator: ", "))] at y=\(AuditRowFormat.round(row.y))")
            }
            if shown.count < screenRows.count {
                lines.append("    … and \(screenRows.count - shown.count) more on this screen")
            }
        }
        return lines
    }

    /// Collapses one row captured in several states into the one row it is, naming the states it was seen in.
    ///
    /// The headline counted capture *instances*: a row present in light, dark and accessibility3 arrived three times, so a walk of three states reported "17 not typed as controls" over 8 rows and a reader had no way to tell which number they were looking at. A finding is a row, and a row does not become three findings by being photographed three times.
    ///
    /// Keyed on screen, type and label — deliberately not on position, so a row that shifts a few points under Dynamic Type still collapses. The cost is that two genuinely different rows sharing a screen, a type and a label count once; they are the same finding stated twice, which is the direction to be wrong in for a check whose output a human reads.
    private static func distinct(_ rows: [DisclosureRow]) -> [Row] {
        var order: [Key] = []
        var collected: [Key: Row] = [:]
        for row in rows {
            let key = Key(screenID: row.screenID, type: row.type, label: row.label)
            if var existing = collected[key] {
                if !existing.states.contains(row.stateSlug) {
                    existing.states.append(row.stateSlug)
                    collected[key] = existing
                }
            } else {
                order.append(key)
                collected[key] = Row(screenID: row.screenID, type: row.type, label: row.label, y: row.frame.y, states: [row.stateSlug])
            }
        }
        return order.compactMap { collected[$0] }
    }
}

extension DisclosureAuditSummary {
    /// What makes two captures of a row the same row.
    struct Key: Hashable {
        let screenID: String
        let type: String
        let label: String
    }

    /// One row, however many states it was captured in.
    struct Row {
        let screenID: String
        let type: String
        let label: String
        /// The position it was first seen at, which is what a reader crops to.
        let y: Double
        var states: [String]
    }
}
