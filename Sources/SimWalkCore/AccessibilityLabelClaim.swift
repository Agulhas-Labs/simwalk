//
// Copyright © Agulhas Labs
//

import Foundation

/// One of the App Store Accessibility Nutrition Label claims `bundle labels` reports on, named as the command's `--claim` selects it.
public enum AccessibilityLabelClaim: String, CaseIterable, Sendable {
    case largerText = "larger-text"
    case darkInterface = "dark-interface"
    case sufficientContrast = "sufficient-contrast"
    case differentiateWithoutColor = "differentiate-without-color"

    /// The claims a run covers: all four when none was asked for, otherwise the ones named, each once, in the order the answer prints them.
    public static func selection(_ requested: [AccessibilityLabelClaim]) -> [AccessibilityLabelClaim] {
        requested.isEmpty ? allCases : allCases.filter(requested.contains)
    }

    /// The names a caller may pass, comma-separated, for a refusal and a help text.
    public static var names: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// Whether SimWalk can check nothing of the claim, so its report is what a person must check by hand and never a verdict.
    public var isManualOnly: Bool {
        self == .differentiateWithoutColor
    }
}
