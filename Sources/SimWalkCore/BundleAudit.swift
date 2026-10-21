//
// Copyright © Agulhas Labs
//

import Foundation

/// Runs the rules of `bundle audit` over one bundle: reads its captures once, hands them to each rule, and states the coverage once.
///
/// The rules are separate types with their own tests; what they share is here and in `BundleAuditScope`. A run that reads the trees once per rule would decode a walk's several megabytes four times to answer one question.
public struct BundleAudit {
    private let bundle: CaptureBundle
    private let rules: [AuditRuleName]
    private let budgets: [String: Walkbook.Budgets]
    private let recognizer: (any ScreenTextRecognizing)?

    /// - Parameter rules: The rules to run; every rule when empty. Ordered and de-duplicated by `AuditRuleName.selection`.
    /// - Parameter budgets: Each screen's budgets by screen id, from a walkbook; `motionBudget` runs only over the screens with a motion budget and `performanceBudget` only over those with a performance budget, each only when there are some (SimWalk#67).
    /// - Parameter recognizer: What `truncatedText` reads a screenshot's text with; `nil` on a face that has none, where the rule says so rather than passing.
    public init(_ bundle: CaptureBundle, rules: [AuditRuleName] = [], budgets: [String: Walkbook.Budgets] = [:], recognizer: (any ScreenTextRecognizing)? = nil) {
        self.bundle = bundle
        self.recognizer = recognizer
        self.budgets = budgets
        self.rules = AuditRuleName.selection(rules)
    }

    public func run() throws -> Report {
        let scope = BundleAuditScope(bundle)
        let captures = try scope.captures()
        var labelResults: [AuditRuleName: LabelRuleResult] = [:]
        for name in rules {
            labelResults[name] = name.labelRule(recognizer: recognizer)?.evaluate(captures)
        }
        var notApplicable: [AuditRuleName: String] = [:]
        for (name, result) in labelResults where result.examined == 0 && result.findings.isEmpty {
            notApplicable[name] = name.labelRule(recognizer: recognizer)?.notApplicableReason(over: captures, result: result)
        }
        let motionBudgets = budgets.filter(\.value.hasMotionBudget)
        let performanceBudgets = budgets.filter(\.value.hasPerformanceBudget)
        return Report(
            rules: rules,
            disclosure: rules.contains(.disclosureAffordance) ? DisclosureAffordanceAudit(bundle).findings(over: captures) : nil,
            labelResults: labelResults,
            motionBudget: rules.contains(.motionBudget) && !motionBudgets.isEmpty ? MotionBudgetAudit(bundle.manifest, budgets: motionBudgets).evaluate() : nil,
            performanceBudget: rules.contains(.performanceBudget) && !performanceBudgets.isEmpty ? PerformanceBudgetAudit(bundle.manifest, budgets: performanceBudgets).evaluate() : nil,
            notApplicable: notApplicable,
            appleAudit: rules.contains(where: \.isApple) ? AppleAuditScan(bundle) : nil,
            coverage: scope.coverage(),
            captureCount: captures.count
        )
    }
}

public extension BundleAudit {
    /// What every rule that ran found, and what all of them were able to look at.
    struct Report: Sendable {
        /// The rules that ran, in print order.
        public let rules: [AuditRuleName]
        /// The disclosure rule's verdict, when it ran.
        public let disclosure: DisclosureAffordanceAudit.Findings?
        /// Each label rule's result, by name.
        public let labelResults: [AuditRuleName: LabelRuleResult]
        /// The `motionBudget` rule's result; `nil` when it was selected but not run, for want of budgets.
        let motionBudget: BudgetAuditResult?
        /// The `performanceBudget` rule's result; `nil` when it was selected but not run, for want of performance budgets.
        let performanceBudget: BudgetAuditResult?
        /// The label rules that examined nothing, with why: they ran, but they are not a pass.
        public let notApplicable: [AuditRuleName: String]
        /// Every capture's Apple audit record, read once; `nil` when no `apple*` rule was selected.
        public let appleAudit: AppleAuditScan?
        /// The bundle's coverage, stated once for all of them.
        public let coverage: BundleAuditScope.Coverage
        /// How many captures the rules read — the denominator of every rule's count.
        public let captureCount: Int
    }
}
