//
// Copyright © Agulhas Labs
//

import Foundation

/// A `bundle audit` rule that judges one capture's tree on its own.
///
/// The disclosure rule compares a screen's rows against the rest of the bundle, so it is not one of these; these three ask a question of a single tree and need no peers. Bundle reading and coverage are `BundleAuditScope`'s, so a rule is only the question.
public protocol LabelAuditRule: Sendable {
    /// The name the rule is selected and headed by.
    static var name: AuditRuleName { get }

    /// What one finding is, singular — `control`, `label` — for the verdict's clause.
    static var findingNoun: String { get }

    /// What is wrong with it, for the same clause — `with neither a label nor an identifier`.
    static var findingClause: String { get }

    /// What one examined thing is, singular — `control` unless the rule looks at something else (`text run`).
    static var examinedNoun: String { get }

    /// The rule's findings in one tree, and how many controls it looked at to find them.
    func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult

    /// Why the rule examined nothing over these captures, for a `not applicable` heading.
    func notApplicableReason(over captures: [BundleAuditScope.Capture]) -> String
}

public extension LabelAuditRule {
    static var examinedNoun: String {
        "control"
    }

    func notApplicableReason(over _: [BundleAuditScope.Capture]) -> String {
        "no \(Self.examinedNoun)s on any screen"
    }

    /// The rule over every readable capture of a bundle.
    func evaluate(_ captures: [BundleAuditScope.Capture]) -> LabelRuleResult {
        var result = LabelRuleResult()
        for capture in captures {
            result.absorb(evaluate(capture.tree, screenID: capture.screenID, stateSlug: capture.stateSlug))
        }
        return result
    }
}
