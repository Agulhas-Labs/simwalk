//
// Copyright © Agulhas Labs
//

import Foundation

public struct JUnitAuditCases {
    /// An audit as test cases, classname the rule's name.
    ///
    /// Each finding the text answer counts fails as `<screen> · <states> · <label or type>`, followed by ` at y=<y>` where the answer's line prints one (a repeated name is numbered by the renderer) — a control seen in several states is one finding, as in the answer, so the states are listed in the name rather than repeated as cases. The disclosure rule's findings are the rows not typed as controls; a budget rule's are its over-budget and unreachable checks; an `apple*` rule's are Apple's findings, and over a bundle with no audit record it is skipped as `not recorded`, over one where no capture's audit completed as `not checked`. Failed audits, unreadable records and issue types no rule reads are failing cases under classname `appleAudit`, once per report. A rule that ran and found nothing is one passing case named for the rule, provided it checked at least one capture; a label rule that could not read some captures' screenshots adds one skipped case, `<rule> not checked`, saying how many; a rule not applicable or not run is skipped with its reason.
    public static func report(_ report: BundleAudit.Report, of bundle: CaptureBundle, walkbookPassed: Bool = false, budgetsStated: Bool = false) -> JUnitReport {
        let summary = BundleAuditSummary(report, of: bundle, walkbookPassed: walkbookPassed, budgetsStated: budgetsStated)
        var cases: [JUnitCase] = []
        for name in report.rules {
            let rule = name.rawValue
            let passing = JUnitCase(classname: rule, name: rule, result: .passed)
            if name == .disclosureAffordance {
                guard let disclosure = report.disclosure else {
                    cases.append(JUnitCase(classname: rule, name: rule, result: .skipped("not run")))
                    continue
                }
                let rows = DisclosureAuditSummary(disclosure, of: bundle).failingRows
                cases += rows.isEmpty ? [passing] : rows.map {
                    JUnitCase(classname: rule, name: Self.findingName(screen: $0.screenID, states: $0.states, label: $0.label, type: $0.type), result: .failed("\($0.type) '\($0.label)' is not typed as a control"))
                }
            } else if name == .motionBudget || name == .performanceBudget {
                let result = name == .motionBudget ? report.motionBudget : report.performanceBudget
                guard let result else {
                    cases.append(JUnitCase(classname: rule, name: rule, result: .skipped(summary.budgetNotRunReason(name))))
                    continue
                }
                cases += result.found == 0 ? [passing] : result.over.map { JUnitCase(classname: rule, name: $0, result: .failed("over budget")) } + result.unreachable.map { JUnitCase(classname: rule, name: $0, result: .failed("unreachable")) }
            } else if name.isApple {
                if summary.notRecordedRules.contains(name) {
                    cases.append(JUnitCase(classname: rule, name: rule, result: .skipped("not recorded — \(AppleAuditSection.notRecordedReason)")))
                } else if let section = summary.appleSection(name) {
                    let unchecked = JUnitCase(classname: rule, name: rule, result: .skipped("not checked — no capture's audit completed"))
                    cases += section.findingCount == 0 ? [section.scan.audited == 0 ? unchecked : passing] : section.distinct.map {
                        JUnitCase(classname: rule, name: Self.findingName(screen: $0.screenID, states: $0.states, label: $0.label?.isEmpty == false ? $0.label : $0.identifier?.isEmpty == false ? $0.identifier : nil, type: $0.elementType ?? "(no element)"), result: .failed($0.text))
                    }
                }
            } else if let section = summary.labelSection(name) {
                if let notApplicable = section.notApplicable, section.findingCount == 0 {
                    cases.append(JUnitCase(classname: rule, name: rule, result: .skipped("not applicable — \(notApplicable)")))
                    if section.result.unchecked > 0 {
                        cases.append(Self.uncheckedCase(rule, section))
                    }
                } else {
                    cases += section.findingCount == 0 ? [passing] : section.distinct.map {
                        JUnitCase(classname: rule, name: Self.findingName(screen: $0.screenID, states: $0.states, label: $0.label, type: $0.type) + " at y=\(AuditRowFormat.round($0.y))", result: .failed(Self.label($0)))
                    }
                    if section.result.unchecked > 0 {
                        cases.append(Self.uncheckedCase(rule, section))
                    }
                }
            }
        }
        if let scan = report.appleAudit, scan.recorded > 0, report.rules.contains(where: \.isApple) {
            cases += Self.appleAuditCases(scan)
        }
        return JUnitReport(command: "bundle audit", cases: cases)
    }

    /// What Apple's audit could not say, once per report: a failing case per group of failed captures, per unreadable record and per issue type no rule reads.
    private static func appleAuditCases(_ scan: AppleAuditScan) -> [JUnitCase] {
        let classname = "appleAudit"
        var cases: [JUnitCase] = []
        var groups: [FailureGroup] = []
        for failure in scan.failures {
            if let index = groups.firstIndex(where: { $0.screenID == failure.screenID && $0.reason == failure.reason }) {
                groups[index].states.append(failure.stateSlug)
            } else {
                groups.append(FailureGroup(screenID: failure.screenID, reason: failure.reason, states: [failure.stateSlug]))
            }
        }
        cases += groups.map { JUnitCase(classname: classname, name: "\($0.screenID) · \($0.states.joined(separator: ", ")) · audit failed", result: .failed($0.reason)) }
        cases += scan.unreadable.map { JUnitCase(classname: classname, name: $0.path, result: .failed("unreadable — \($0.reason)")) }
        cases += scan.unread.map { JUnitCase(classname: classname, name: $0.type, result: .failed("\($0.count) issue\($0.count == 1 ? "" : "s") of a type no rule reads")) }
        return cases
    }

    /// The captures a rule could not read a screenshot of, as one skipped case.
    private static func uncheckedCase(_ rule: String, _ section: LabelAuditSection) -> JUnitCase {
        JUnitCase(classname: rule, name: "\(rule) not checked", result: .skipped("\(section.result.unchecked) of \(section.captureCount) captures not checked — no screenshot read"))
    }

    private static func findingName(screen: String, states: [String], label: String?, type: String) -> String {
        "\(screen) · \(states.joined(separator: ", ")) · \(label ?? type)"
    }

    private static func label(_ row: LabelAuditSection.Row) -> String {
        let label = row.label.map { " '\(AuditRowFormat.trim($0))'" } ?? ""
        let note = row.note.map { " \($0)" } ?? ""
        return "\(row.type)\(label)\(note) at y=\(AuditRowFormat.round(row.y))"
    }
}

private extension JUnitAuditCases {
    struct FailureGroup {
        let screenID: String
        let reason: String
        var states: [String]
    }
}
