//
// Copyright © Agulhas Labs
//

import Foundation

/// What one label rule found in one capture or across a bundle, with the count it looked at.
///
/// The count is the rule's arithmetic: "none found" beside "41 controls examined" is a check that ran, where "none found" alone could equally be a rule that matched nothing because nothing of its kind was there to match.
public struct LabelRuleResult: Equatable, Sendable {
    /// How many controls the rule examined.
    public var examined: Int
    /// What it objected to.
    public var findings: [LabelFinding]
    /// How many captures the rule could not check, for a rule that needs more than the tree (a screenshot it could not read); the answer says so beside the count.
    public var unchecked: Int

    public init(examined: Int = 0, findings: [LabelFinding] = [], unchecked: Int = 0) {
        self.examined = examined
        self.findings = findings
        self.unchecked = unchecked
    }

    /// Two results as one, in order.
    mutating func absorb(_ other: LabelRuleResult) {
        examined += other.examined
        findings += other.findings
        unchecked += other.unchecked
    }
}
