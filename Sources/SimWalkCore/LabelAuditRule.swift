//
// Copyright © Agulhas Labs
//

import Foundation

/// A `bundle audit` rule that is answered over a bundle's readable captures, one capture at a time.
///
/// The disclosure rule compares a screen's rows against the rest of the bundle, so it is not one of these. Most of these ask a question of a single tree (`PerTreeLabelAuditRule`); `truncatedText` needs the capture's screenshot as well, so it answers over the captures itself. Bundle reading and coverage are `BundleAuditScope`'s, so a rule is only the question.
public protocol LabelAuditRule: Sendable {
    /// The name the rule is selected and headed by.
    static var name: AuditRuleName { get }

    /// What one finding is, singular — `control`, `label` — for the verdict's clause.
    static var findingNoun: String { get }

    /// What is wrong with it, for the same clause — `with neither a label nor an identifier`.
    static var findingClause: String { get }

    /// What one examined thing is, singular — `control` unless the rule looks at something else (`text run`).
    static var examinedNoun: String { get }

    /// The rule over every readable capture of a bundle.
    func evaluate(_ captures: [BundleAuditScope.Capture]) -> LabelRuleResult

    /// Why the rule examined nothing over these captures, for a `not applicable` heading; `result` is what `evaluate` returned, for a rule whose reason depends on how many captures it could check.
    func notApplicableReason(over captures: [BundleAuditScope.Capture], result: LabelRuleResult) -> String
}

public extension LabelAuditRule {
    static var examinedNoun: String {
        "control"
    }

    func notApplicableReason(over _: [BundleAuditScope.Capture], result _: LabelRuleResult) -> String {
        "no \(Self.examinedNoun)s on any screen"
    }
}
