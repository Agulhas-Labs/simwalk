//
// Copyright © Agulhas Labs
//

import Foundation

/// The rules `bundle audit` runs, by the name a caller selects one with (`--only`, the MCP tool's `only`) and the heading its section carries.
///
/// Declared in the order the answer prints them. The raw value is the spelling on both faces, so the CLI and the MCP tool cannot come to name a rule two ways.
public enum AuditRuleName: String, CaseIterable, Sendable {
    case disclosureAffordance
    case unlabelledControl
    case symbolNameLabel
    case duplicateLabel
    case smallTarget
    case readingOrder
    case largeTypeOverflow
    /// Opt-in: runs only over a walkbook's `budgets` (`MotionBudgetAudit`); named without any it prints a `not run` heading.
    case motionBudget
    /// Opt-in: runs only over a walkbook's performance budgets (`PerformanceBudgetAudit`); named without any it prints a `not run` heading.
    case performanceBudget

    /// The rules a run covers: every one when none was asked for, otherwise the ones named, each once, in the order the answer prints them.
    public static func selection(_ requested: [AuditRuleName]) -> [AuditRuleName] {
        requested.isEmpty ? allCases : allCases.filter(requested.contains)
    }

    /// The label rule behind a name, or nothing for the disclosure rule, which compares rows across the bundle and is not a per-tree rule; nor are `motionBudget` and `performanceBudget`, which read the manifest.
    var labelRule: (any LabelAuditRule)? {
        switch self {
        case .disclosureAffordance, .motionBudget, .performanceBudget: nil
        case .unlabelledControl: UnlabelledControlAudit()
        case .symbolNameLabel: SymbolNameLabelAudit()
        case .duplicateLabel: DuplicateLabelAudit()
        case .smallTarget: SmallTargetAudit()
        case .readingOrder: ReadingOrderAudit()
        case .largeTypeOverflow: LargeTypeOverflowAudit()
        }
    }
}
