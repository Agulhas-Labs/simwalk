//
// Copyright © Agulhas Labs
//

import Foundation

/// One `apple*` rule's part of the `bundle audit` answer: Apple's own findings of one issue type, grouped by screen.
///
/// Its own type beside ``LabelAuditSection`` because a finding here has no position to print: Apple's frame is read after the audit and is not used. A finding seen in several states is one row naming them, keyed by ``AppleAuditIdentity``, whether its element was named, none named or unreadable, and Apple's description. A finding with no element is never paired across states: it is one row per state, counted.
struct AppleAuditSection {
    static var notRecordedReason: String {
        "the walk did not run Apple's accessibility audit (walkbook \"appleAudit\": true, or walk --apple-audit)"
    }

    let name: AuditRuleName
    let scan: AppleAuditScan
    /// Whether this section also lists the unreadable records' paths, so seven sections do not repeat them.
    let listsUnreadable: Bool

    var distinct: [Row] {
        var order: [RowKey] = []
        var collected: [RowKey: Row] = [:]
        for finding in scan.findings(ofType: name.appleIssueType ?? "") {
            let key = RowKey(finding)
            if var existing = collected[key] {
                if key.state != nil {
                    existing.count += 1
                } else if !existing.states.contains(finding.stateSlug) {
                    existing.states.append(finding.stateSlug)
                }
                collected[key] = existing
            } else {
                order.append(key)
                let element = finding.issue.element
                collected[key] = Row(screenID: finding.screenID, elementType: element?.type, elementUnreadable: finding.issue.elementUnreadable, elementsRead: finding.elementsRead, label: element?.label, identifier: element?.identifier, compactDescription: finding.issue.compactDescription, count: 1, states: [finding.stateSlug])
            }
        }
        return order.compactMap { collected[$0] }
    }

    var findingCount: Int {
        distinct.reduce(0) { $0 + $1.count }
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
        let heading = rows.isEmpty ? (scan.audited == 0 ? "not checked" : "clean") : "\(findingCount) found"
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
    /// A row's key.
    ///
    /// A named element's findings are one row across states when Apple's description agrees, so states that disagree on the identity, the element case or the description are rows of their own. A finding with no named element has nothing identifying it across states, so its key holds its state and the row counts the findings alike in it.
    private struct RowKey: Hashable {
        let screenID: String
        let issueType: String
        let identity: AppleAuditIdentity?
        let elementCase: AppleElementCase
        let description: String
        let unreadable: String?
        let state: String?

        init(_ finding: AppleAuditScan.Finding) {
            let elementCase = finding.elementCase
            screenID = finding.screenID
            issueType = finding.identity.issueType
            self.elementCase = elementCase
            description = finding.issue.compactDescription
            if elementCase == .named {
                identity = finding.identity
                unreadable = nil
                state = nil
            } else {
                identity = nil
                unreadable = finding.issue.elementUnreadable
                state = finding.stateSlug
            }
        }
    }

    /// One distinct finding.
    struct Row {
        let screenID: String
        let elementType: String?
        /// Why the element Apple named could not be read after the audit, when that is why there is none.
        let elementUnreadable: String?
        /// Whether the record says the element was read after the audit.
        let elementsRead: Bool
        let label: String?
        let identifier: String?
        let compactDescription: String
        /// How many findings alike this row stands for in its one state; above 1 only for a finding with no named element.
        var count: Int
        var states: [String]

        /// What the row names: `Button 'Save'`, `Button #save`, `Button`, `Apple named no element`, `the element could not be read after the audit (<error>)`, or `(no element)` for an old record.
        var subject: String {
            let type = elementType ?? AppleElementCase.absentText(unreadable: elementUnreadable, elementsRead: elementsRead)
            if let label, !label.isEmpty {
                return "\(type) '\(AuditRowFormat.trim(label))'"
            }
            if let identifier, !identifier.isEmpty {
                return "\(type) #\(AuditRowFormat.trim(identifier))"
            }
            return type
        }

        var text: String {
            "\(subject) — \(AuditRowFormat.trim(compactDescription))\(count > 1 ? " ×\(count)" : "")"
        }
    }
}
