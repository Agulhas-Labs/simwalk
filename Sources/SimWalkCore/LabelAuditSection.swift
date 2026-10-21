//
// Copyright © Agulhas Labs
//

import Foundation

/// One label rule's part of the `bundle audit` answer: how many distinct findings, over how much, and the controls themselves grouped by screen.
///
/// A control seen in light, dark and a Dynamic Type state is one finding, named with the states it was seen in — the count of instances would read three times the truth. Two findings are the same when they share screen, type, label and their place in the tree order among the findings alike in those three in that capture; position on screen is left out so a control that moves under Dynamic Type still collapses, and the tree-order place is what keeps two unlabelled switches on one screen two findings rather than one.
struct LabelAuditSection {
    let name: AuditRuleName
    let noun: String
    let examinedNoun: String
    let clause: String
    let result: LabelRuleResult
    let captureCount: Int
    /// Why the rule examined nothing, when it did not: its heading then says so instead of `clean`.
    var notApplicable: String?

    /// How many distinct controls the rule objects to.
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
        }
        return lines
    }

    var distinct: [Row] {
        var order: [Key] = []
        var collected: [Key: Row] = [:]
        var seenInCapture: [CaptureKey: Int] = [:]
        for finding in result.findings {
            let capture = CaptureKey(screenID: finding.screenID, stateSlug: finding.stateSlug, type: finding.type, label: finding.label)
            let place = seenInCapture[capture, default: 0]
            seenInCapture[capture] = place + 1
            let key = Key(screenID: finding.screenID, type: finding.type, label: finding.label, place: place)
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
