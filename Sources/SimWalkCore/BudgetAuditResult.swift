//
// Copyright © Agulhas Labs
//

import Foundation

/// What a budget rule of `bundle audit` found (`motionBudget`, `performanceBudget`), one line each, and how many budget checks held.
struct BudgetAuditResult: Equatable, Sendable {
    /// How many (capture, budget) checks came in under budget; counted, not listed.
    var within = 0
    /// One line per check that came in over.
    var over: [String] = []
    /// One line per check no measurement answers.
    var unreachable: [String] = []
    /// How many screens carried budgets.
    var screens = 0

    /// Whether any check qualifies the verdict.
    var found: Int {
        over.count + unreachable.count
    }
}
