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
    /// SimWalk's own truncation rule: text drawn as a prefix and an ellipsis (`Notific…`) over a longer label, read from the screenshot; it runs only where a text recognizer is supplied.
    case truncatedText
    /// Apple's own contrast finding, read from the per-state audit record (`apple-audit.json`); not recorded unless the walk ran Apple's audit.
    case appleContrast
    /// Apple's own clipped-text finding, from the per-state audit record.
    case appleTextClipped
    /// Apple's own Dynamic Type finding, from the per-state audit record.
    case appleDynamicType
    /// Apple's own hit-region finding, from the per-state audit record.
    case appleHitRegion
    /// Apple's own element-detection finding, from the per-state audit record.
    case appleElementDetection
    /// Apple's own trait finding, from the per-state audit record.
    case appleTrait
    /// Apple's own element-description finding, from the per-state audit record.
    case appleDescription
    /// Opt-in: runs only over a walkbook's `budgets` (`MotionBudgetAudit`); named without any it prints a `not run` heading.
    case motionBudget
    /// Opt-in: runs only over a walkbook's performance budgets (`PerformanceBudgetAudit`); named without any it prints a `not run` heading.
    case performanceBudget

    /// The rules a run covers: every one when none was asked for, otherwise the ones named, each once, in the order the answer prints them.
    public static func selection(_ requested: [AuditRuleName]) -> [AuditRuleName] {
        requested.isEmpty ? allCases : allCases.filter(requested.contains)
    }

    /// The record's issue type this rule reads, or nothing for a rule that does not read Apple's audit record.
    public var appleIssueType: String? {
        switch self {
        case .appleContrast: "contrast"
        case .appleTextClipped: "textClipped"
        case .appleDynamicType: "dynamicType"
        case .appleHitRegion: "hitRegion"
        case .appleElementDetection: "elementDetection"
        case .appleTrait: "trait"
        case .appleDescription: "sufficientElementDescription"
        default: nil
        }
    }

    /// Whether the rule reads Apple's accessibility-audit record rather than the trees.
    public var isApple: Bool {
        appleIssueType != nil
    }

    /// The label rule behind a name, or nothing for the disclosure rule, which compares rows across the bundle and is not a per-tree rule; nor are `motionBudget` and `performanceBudget`, which read the manifest, nor the `apple*` rules, which read Apple's audit record.
    var labelRule: (any LabelAuditRule)? {
        labelRule(recognizer: nil)
    }

    /// The label rule behind a name, given the recognizer `truncatedText` reads the screenshots with (`nil` where the face has none).
    func labelRule(recognizer: (any ScreenTextRecognizing)?) -> (any LabelAuditRule)? {
        switch self {
        case .disclosureAffordance, .motionBudget, .performanceBudget: nil
        case .appleContrast, .appleTextClipped, .appleDynamicType, .appleHitRegion, .appleElementDetection, .appleTrait, .appleDescription: nil
        case .unlabelledControl: UnlabelledControlAudit()
        case .symbolNameLabel: SymbolNameLabelAudit()
        case .duplicateLabel: DuplicateLabelAudit()
        case .smallTarget: SmallTargetAudit()
        case .readingOrder: ReadingOrderAudit()
        case .largeTypeOverflow: LargeTypeOverflowAudit()
        case .truncatedText: TruncatedTextAudit(recognizer: recognizer)
        }
    }
}
