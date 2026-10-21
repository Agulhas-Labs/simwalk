//
// Copyright © Agulhas Labs
//

import Foundation

/// One `apple*` rule's part of the `bundle audit` answer: Apple's own findings of one issue type, grouped by screen.
///
/// Its own type beside ``LabelAuditSection`` because a finding here has no position to print: Apple's frame is read after the audit and is not used. A finding seen in several states is one row naming them, keyed by ``AppleAuditIdentity``.
struct AppleAuditSection {
    static var notRecordedReason: String {
        "the walk did not run Apple's accessibility audit (walkbook \"appleAudit\": true, or walk --apple-audit)"
    }

    let name: AuditRuleName
    let scan: AppleAuditScan
    /// Whether this section also lists the unreadable records' paths, so seven sections do not repeat them.
    let listsUnreadable: Bool

    var distinct: [Row] {
        var order: [AppleAuditIdentity] = []
        var collected: [AppleAuditIdentity: Row] = [:]
        for finding in scan.findings(ofType: name.appleIssueType ?? "") {
            if var existing = collected[finding.identity] {
                if !existing.states.contains(finding.stateSlug) {
                    existing.states.append(finding.stateSlug)
                    collected[finding.identity] = existing
                }
            } else {
                order.append(finding.identity)
                let element = finding.issue.element
                collected[finding.identity] = Row(screenID: finding.screenID, elementType: element?.type, label: element?.label, identifier: element?.identifier, compactDescription: finding.issue.compactDescription, states: [finding.stateSlug])
            }
        }
        return order.compactMap { collected[$0] }
    }

    var findingCount: Int {
        distinct.count
    }

    var verdictClause: String? {
        AnswerVerdict.qualification(findingCount, "\(name.rawValue) finding", "from Apple's audit")
    }

    var lines: [String] {
        let rows = distinct
        let total = scan.captureCount
        let audited = scan.recorded == total
            ? "\(scan.audited) capture\(scan.audited == 1 ? "" : "s") audited"
            : "\(scan.audited) of \(total) capture\(total == 1 ? "" : "s") audited"
        var tail = ""
        if scan.failed > 0 {
            tail += "; \(scan.failed) audit\(scan.failed == 1 ? "" : "s") failed, not checked there"
        }
        if !scan.unreadable.isEmpty {
            tail += "; \(scan.unreadable.count) unreadable, not checked there"
        }
        let heading = rows.isEmpty ? (scan.audited == 0 ? "not checked" : "clean") : "\(rows.count) found"
        var lines = ["[\(name.rawValue)] \(heading) — \(audited)\(tail)"]
        if listsUnreadable {
            lines += scan.unreadable.map { "  unreadable: \($0.path) (\($0.reason))" }
        }
        for (screen, screenRows) in AuditRowFormat.screensInOrder(rows, screen: { $0.screenID }) {
            lines.append("  \(screen):")
            lines += screenRows.map { "    \($0.text) [\($0.states.joined(separator: ", "))]" }
        }
        return lines
    }
}

extension AppleAuditSection {
    /// One distinct finding.
    struct Row {
        let screenID: String
        let elementType: String?
        let label: String?
        let identifier: String?
        let compactDescription: String
        var states: [String]

        /// What the row names: `Button 'Save'`, `Button #save`, `Button`, or `(no element)`.
        var subject: String {
            let type = elementType ?? "(no element)"
            if let label, !label.isEmpty {
                return "\(type) '\(AuditRowFormat.trim(label))'"
            }
            if let identifier, !identifier.isEmpty {
                return "\(type) #\(AuditRowFormat.trim(identifier))"
            }
            return type
        }

        var text: String {
            "\(subject) — \(AuditRowFormat.trim(compactDescription))"
        }
    }
}
