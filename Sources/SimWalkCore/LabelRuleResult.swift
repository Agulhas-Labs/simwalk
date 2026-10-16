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

    public init(examined: Int = 0, findings: [LabelFinding] = []) {
        self.examined = examined
        self.findings = findings
    }

    /// Two results as one, in order.
    mutating func absorb(_ other: LabelRuleResult) {
        examined += other.examined
        findings += other.findings
    }
}
