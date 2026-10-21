//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a `BundleAudit` report in the contract's shape: one verdict over the whole run, the coverage stated once, then one heading per rule that ran.
///
/// **A rule that found nothing still has its heading**, with the count of what it examined under it. The contract keeps an empty section off the page, but this is not an empty section: "unlabelledControl: clean — 41 controls examined" is the evidence the rule ran, and its absence would be indistinguishable from a rule that was never asked for.
///
/// **A rule that examined nothing is not a pass.** Its heading reads `not applicable — <why>` (no accessibility type-size state; only right-to-left states), and the verdict's rule count leaves it out and counts it apart.
///
/// The disclosure rule's section is `DisclosureAuditSummary`'s own lines, unchanged; only the coverage moved out, because it is the bundle's.
public struct BundleAuditSummary {
    private let report: BundleAudit.Report
    private let bundle: CaptureBundle
    private let qualifications: [String]
    private let walkbookPassed: Bool
    private let budgetsStated: Bool

    /// - Parameter qualifications: Clauses the caller adds to the verdict, ahead of the rules' own — the walkbook the budgets came from not being the one the bundle was walked from. `walkbookPassed` says a walkbook was given, so a rule not run for want of budgets blames the walkbook rather than its absence; `budgetsStated` says it states budgets of some rule, so the motion rule names its kind rather than saying it states none.
    public init(_ report: BundleAudit.Report, of bundle: CaptureBundle, qualifiedBy qualifications: [String] = [], walkbookPassed: Bool = false, budgetsStated: Bool = false) {
        self.report = report
        self.bundle = bundle
        self.qualifications = qualifications
        self.walkbookPassed = walkbookPassed
        self.budgetsStated = budgetsStated
    }

    public func answer() -> Answer {
        let coverage = AuditCoverageStatement(report.coverage)
        let disclosure = report.disclosure.map { DisclosureAuditSummary($0, of: bundle) }
        let sections = labelSections
        let clauses = qualifications + [disclosure?.finding()].compactMap(\.self) + sections.flatMap(\.verdictClauses) + appleSections.compactMap(\.verdictClause) + appleClauses + budgetClauses
        let rules = report.rules.count - report.notApplicable.count - ([AuditRuleName.motionBudget, .performanceBudget].filter(budgetRuleNotRun).count) - notRecordedRules.count
        let skipped = report.notApplicable.isEmpty ? "" : ", \(report.notApplicable.count) not applicable"
        return Answer(
            header: CaptureBundleHeader.line(of: bundle),
            verdict: AnswerVerdict.reporting(qualifications: clauses + coverage.qualifications, detail: "\(coverage.audited) by \(rules) rule\(rules == 1 ? "" : "s")\(skipped)"),
            residue: residue(coverage: coverage, disclosure: disclosure, sections: sections),
            weighing: ContextSaving.weighing(bundle)
        )
    }

    /// The whole answer as text.
    public func render() -> String {
        answer().text
    }

    /// The `apple*` rules selected over a bundle in which no capture has an audit record: printed as `not recorded`, and left out of the rule count.
    var notRecordedRules: [AuditRuleName] {
        guard let scan = report.appleAudit, scan.recorded == 0 else { return [] }
        return report.rules.filter(\.isApple)
    }

    /// The `apple*` rules that have a record to read, each with its section.
    private var appleSections: [AppleAuditSection] {
        guard let scan = report.appleAudit, scan.recorded > 0 else { return [] }
        return report.rules.filter(\.isApple).enumerated().map { AppleAuditSection(name: $1, scan: scan, listsUnreadable: $0 == 0) }
    }

    /// What the whole of Apple's audit could not say: calls that threw, records that could not be read, issues of a type no rule reads. Stated once, not per rule.
    private var appleClauses: [String] {
        guard let scan = report.appleAudit, scan.recorded > 0 else { return [] }
        return [
            AnswerVerdict.qualification(scan.failed, "Apple audit", "failed, not checked there"),
            AnswerVerdict.qualification(scan.unreadable.count, "Apple audit record", "unreadable, not checked there"),
            AnswerVerdict.qualification(scan.unread.reduce(0) { $0 + $1.count }, "Apple audit issue", "of a type no rule reads"),
        ].compactMap(\.self)
    }

    /// The line naming every selected `apple*` rule when the bundle has no record to read.
    var notRecordedLine: String? {
        notRecordedRules.isEmpty ? nil : "[\(notRecordedRules.map(\.rawValue).joined(separator: ", "))] not recorded — \(AppleAuditSection.notRecordedReason)"
    }

    /// The section an `apple*` rule printed, for a structured report of the same findings.
    func appleSection(_ name: AuditRuleName) -> AppleAuditSection? {
        appleSections.first { $0.name == name }
    }

    /// A budget rule was selected and had no budgets to run over: printed as such, and left out of the rule count.
    private func budgetRuleNotRun(_ name: AuditRuleName) -> Bool {
        report.rules.contains(name) && result(of: name) == nil
    }

    private func result(of name: AuditRuleName) -> BudgetAuditResult? {
        name == .motionBudget ? report.motionBudget : report.performanceBudget
    }

    private var budgetClauses: [String] {
        [(AuditRuleName.motionBudget, "motion budget"), (.performanceBudget, "performance budget")].flatMap { name, noun in
            result(of: name).map { result in
                [
                    AnswerVerdict.qualification(result.over.count, noun, "over budget"),
                    AnswerVerdict.qualification(result.unreachable.count, noun, "unreachable"),
                ].compactMap(\.self)
            } ?? []
        }
    }

    /// The rule's section: its heading with the count of what held, then the lines of what did not.
    private func budgetLines(_ rule: AuditRuleName) -> [String] {
        let name = rule.rawValue
        guard let result = result(of: rule) else {
            // The performance rule always names its kind. The motion rule says "budgets" only when the walkbook states none at all; a walkbook with performance budgets alone is not one that "states no budgets".
            let lacking = rule == .motionBudget ? (budgetsStated ? "motion budgets" : "budgets") : "performance budgets"
            return ["[\(name)] not run — no walkbook \(lacking) (\(walkbookPassed ? "the walkbook states no \(lacking)" : "pass --walkbook"))"]
        }
        let held = "\(result.within) check\(result.within == 1 ? "" : "s") within budget across \(result.screens) screen\(result.screens == 1 ? "" : "s")"
        guard result.found > 0 else {
            return ["[\(name)] clean — \(held)"]
        }
        let found = [
            result.over.isEmpty ? nil : "\(result.over.count) over budget",
            result.unreachable.isEmpty ? nil : "\(result.unreachable.count) unreachable",
        ].compactMap(\.self).joined(separator: ", ")
        return ["[\(name)] \(found) — \(held)"] + (result.over + result.unreachable).map { "  \($0)" }
    }

    /// Why a budget rule that was selected did not run, in the words its heading uses.
    func budgetNotRunReason(_ rule: AuditRuleName) -> String {
        budgetLines(rule).first ?? "not run"
    }

    /// The section a label rule printed, for a structured report of the same findings.
    func labelSection(_ name: AuditRuleName) -> LabelAuditSection? {
        labelSections.first { $0.name == name }
    }

    private var labelSections: [LabelAuditSection] {
        report.rules.compactMap { name in
            guard let rule = name.labelRule, let result = report.labelResults[name] else { return nil }
            return LabelAuditSection(name: name, noun: type(of: rule).findingNoun, examinedNoun: type(of: rule).examinedNoun, clause: type(of: rule).findingClause, result: result, captureCount: report.captureCount, notApplicable: report.notApplicable[name])
        }
    }

    private func residue(coverage: AuditCoverageStatement, disclosure: DisclosureAuditSummary?, sections: [LabelAuditSection]) -> [String] {
        var lines = [coverage.line].compactMap(\.self)
        for name in report.rules where !notRecordedRules.contains(name) {
            if !lines.isEmpty {
                lines.append("")
            }
            if name == .disclosureAffordance, let disclosure {
                lines.append("[\(name.rawValue)]")
                lines += disclosure.sectionLines()
            } else if name == .motionBudget || name == .performanceBudget {
                lines += budgetLines(name)
            } else if let section = sections.first(where: { $0.name == name }) {
                lines += section.lines
            } else if let section = appleSection(name) {
                lines += section.lines
            }
        }
        if let notRecorded = notRecordedLine {
            lines += (lines.isEmpty ? [] : [""]) + [notRecorded]
        }
        if let scan = report.appleAudit, scan.recorded > 0, let failed = scan.failureLine {
            lines += (lines.isEmpty ? [] : [""]) + [failed]
        }
        if let scan = report.appleAudit, scan.recorded > 0, !scan.unread.isEmpty {
            let total = scan.unread.reduce(0) { $0 + $1.count }
            lines += (lines.isEmpty ? [] : [""]) + ["apple audit: \(total) issue\(total == 1 ? "" : "s") of a type no rule reads — \(scan.unread.map { "\($0.type) ×\($0.count)" }.joined(separator: ", "))"]
        }
        return lines
    }
}
