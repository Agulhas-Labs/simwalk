//
// Copyright © Agulhas Labs
//

import Foundation

/// One label rule's part of the `bundle audit` answer: how many distinct findings, over how much, and the controls themselves grouped by screen.
///
/// A control seen in light, dark and a Dynamic Type state is one finding, named with the states it was seen in — the count of instances would read three times the truth. The one exception is `largeTypeOverflow`, whose run is one finding per distinct piece of evidence: extents that differ by size are a row each (SimWalk#219). Two findings are the same when they share screen, type, label and their place in the tree order among the findings alike in those three in that capture; position on screen is left out so a control that moves under Dynamic Type still collapses, and the tree-order place is what keeps two unlabelled switches on one screen two findings rather than one.
struct LabelAuditSection {
    let name: AuditRuleName
    let noun: String
    let examinedNoun: String
    let clause: String
    let result: LabelRuleResult
    let captureCount: Int
    /// Why the rule examined nothing, when it did not: its heading then says so instead of `clean`.
    var notApplicable: String?
    /// The bundle's path, for the follow-up line under a screen whose `largeTypeOverflow` findings are overlaps (SimWalk#142); none, no line.
    var bundlePath: String?
    /// Each screen's 1-based position in the walk, which `bundle screen` reads as its step unambiguously; a screen with none known gets no follow-up line (SimWalk#219).
    var screenPositions: [String: Int] = [:]

    /// How many distinct findings the rule objects to: controls, or for `largeTypeOverflow` the distinct runs of evidence.
    var findingCount: Int {
        distinct.count
    }

    /// The verdict's clauses for this rule: what it found, then the captures it could not check; nothing for either that is zero.
    var verdictClauses: [String] {
        [
            AnswerVerdict.qualification(findingCount, noun, clause),
            AnswerVerdict.qualification(result.unchecked, "capture", "not checked by \(name.rawValue) (no screenshot read)"),
        ].compactMap(\.self)
    }

    /// The heading, its arithmetic, and the findings grouped under their screens.
    var lines: [String] {
        let examined = "\(result.examined) \(examinedNoun)\(result.examined == 1 ? "" : "s") examined across \(captureCount) capture\(captureCount == 1 ? "" : "s")"
        let unchecked = result.unchecked == 0 ? "" : "; \(result.unchecked) capture\(result.unchecked == 1 ? "" : "s") not checked (no screenshot read)"
        if let notApplicable, findingCount == 0 {
            return ["[\(name.rawValue)] not applicable — \(notApplicable)\(unchecked)"]
        }
        guard findingCount > 0 else {
            return ["[\(name.rawValue)] clean — \(examined)\(unchecked)"]
        }
        var lines = ["[\(name.rawValue)] \(findingCount) found — \(examined)\(unchecked)"]
        for (screen, rows) in AuditRowFormat.screensInOrder(distinct, screen: { $0.screenID }) {
            lines.append("  \(screen):")
            for row in rows {
                let label = row.label.map { " '\(AuditRowFormat.trim($0))'" } ?? ""
                let note = row.note.map { " \($0)" } ?? ""
                lines.append("    \(row.type)\(label)\(note) [\(row.states.joined(separator: ", "))] at y=\(AuditRowFormat.round(row.y))")
            }
            if let followUp = overlapFollowUp(screen: screen, rows: rows) {
                lines.append(followUp)
            }
        }
        return lines
    }

    /// The command that shows the frames behind a screen's first overlap finding: the state it was seen in and the start of the run's label, with the off-screen elements the audit also reads (SimWalk#142).
    private func overlapFollowUp(screen: String, rows: [Row]) -> String? {
        guard name == .largeTypeOverflow, let bundlePath, let position = screenPositions[screen],
              !otherScreenIsNamed(String(position), than: screen),
              let row = rows.first(where: { $0.note?.contains(LargeTypeOverflowAudit.overlapMarker) == true }),
              let state = row.states.first else { return nil }
        var command = "    → simwalk bundle screen \(Self.shellQuoted(bundlePath)) \(position) --state \(Self.shellQuoted(state)) --tree --all"
        // The label's first line only, so the command stays one line, and single-quoted, where an interactive shell expands nothing (`!` included).
        let firstLine = row.label?.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let start = String(firstLine.prefix(20)).trimmingCharacters(in: .whitespaces)
        if !start.isEmpty {
            command += " --match \(Self.shellQuoted(start))"
        }
        return command
    }

    /// Whether a screen other than `screen` has `step` for its id, which `bundle screen` refuses as ambiguous: no position, no line (SimWalk#219).
    private func otherScreenIsNamed(_ step: String, than screen: String) -> Bool {
        step != screen && screenPositions[step] != nil
    }

    /// The word bare when the shell would read it as one, else single-quoted.
    private static func shellQuoted(_ word: String) -> String {
        let plain = word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/._-+:=@%,".contains($0)) }
        return plain && !word.isEmpty ? word : "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The findings as rows: one per control, with the states it was seen in.
    ///
    /// For `largeTypeOverflow`, findings that differ in their note are different rows, so a run overlapping at two sizes with different extents is two rows, each with its own extents and `y`, and a later state's overlap is not hidden behind an earlier state's "extends past…"; the finding count follows the rows (SimWalk#219).
    var distinct: [Row] {
        var order: [Key] = []
        var collected: [Key: Row] = [:]
        var seenInCapture: [CaptureKey: Int] = [:]
        for finding in result.findings {
            let capture = CaptureKey(screenID: finding.screenID, stateSlug: finding.stateSlug, type: finding.type, label: finding.label)
            let place = seenInCapture[capture, default: 0]
            seenInCapture[capture] = place + 1
            let key = Key(screenID: finding.screenID, type: finding.type, label: finding.label, note: name == .largeTypeOverflow ? finding.note : nil, place: place)
            if var existing = collected[key] {
                if !existing.states.contains(finding.stateSlug) {
                    existing.states.append(finding.stateSlug)
                    collected[key] = existing
                }
            } else {
                order.append(key)
                collected[key] = Row(screenID: finding.screenID, type: finding.type, label: finding.label, note: finding.note, y: finding.frame.y, states: [finding.stateSlug])
            }
        }
        return order.compactMap { collected[$0] }
    }
}

extension LabelAuditSection {
    struct CaptureKey: Hashable {
        let screenID: String
        let stateSlug: String
        let type: String
        let label: String?
    }

    struct Key: Hashable {
        let screenID: String
        let type: String
        let label: String?
        let note: String?
        let place: Int
    }

    struct Row {
        let screenID: String
        let type: String
        let label: String?
        let note: String?
        let y: Double
        var states: [String]
    }
}
