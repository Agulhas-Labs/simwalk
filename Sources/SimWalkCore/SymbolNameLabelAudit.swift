//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds enabled controls whose label is an SF Symbol name — `gearshape.fill`, `chevron.right` — which VoiceOver reads aloud letter for letter.
///
/// **What counts as a symbol name, and why so little.** A label is taken for one in exactly two cases:
/// - **Dotted lowercase words**, every segment starting with a letter (`gearshape.fill`, `chevron.right`, `person.crop.circle`). Nobody writes a label that way for a person, and the shape is how the symbol catalogue spells nearly everything with a modifier. Domain-like endings (`example.com`, `apple.id`) are not symbol names and are left alone, as are version-like strings (`v1.2`), whose segments do not start with a letter. A last segment that is a common file extension (`jpg`, `png`, `pdf`, `txt`, `md`, `csv`, `json` and the like, listed in `fileExtensions`) makes it a file name (`photo.jpg`), and a label with a one-letter segment (`e.g`) is an abbreviation; neither is a symbol name.
/// - **A short list of undotted names that are not English words** (`questionmark`, `xmark`, `checkmark`, `magnifyingglass`, `ellipsis`, `gearshape`). Real bundles do carry `questionmark`: a real app's help button whose label is the symbol.
///
/// Single words that are also real labels — `plus`, `minus`, `heart`, `star`, `camera`, `trash`, `pencil`, `gear` — are **deliberately not matched**. `pounds` and `kilograms` sit on a real app's buttons and are correct, and the same shape as `plus`; a rule that read them as symbols would be wrong on a screen that is right, which is the failure a conservative rule exists to avoid. The cost is a missed `plus`; the choice is that a finding from this rule should be true.
///
/// Disabled controls are not examined, like the other label rules: Apple's Settings labels its disabled disclosure buttons `chevron`, and it is the reference for a screen with nothing to find.
public struct SymbolNameLabelAudit: PerTreeLabelAuditRule {
    public static let name = AuditRuleName.symbolNameLabel
    public static var findingNoun: String {
        "control"
    }

    public static var findingClause: String {
        "labelled with an SF Symbol name"
    }

    public init() {}

    public func evaluate(_ tree: AXNode, screenID: String, stateSlug: String) -> LabelRuleResult {
        var result = LabelRuleResult()
        for control in AuditedControl.all(in: tree) where control.isEnabledControl {
            result.examined += 1
            guard let label = control.node.label, Self.isSymbolName(label) else { continue }
            result.findings.append(LabelFinding(screenID: screenID, stateSlug: stateSlug, type: control.node.type, label: label, frame: control.node.frame))
        }
        return result
    }

    /// Whether a label reads as a symbol's name rather than as words.
    static func isSymbolName(_ label: String) -> Bool {
        guard !label.contains(".") else { return isDottedSymbolName(label) }
        return undottedNames.contains(label)
    }

    private static func isDottedSymbolName(_ label: String) -> Bool {
        let segments = label.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, let last = segments.last, !domainEndings.contains(String(last)), !fileExtensions.contains(String(last)) else { return false }
        guard segments.allSatisfy({ $0.count > 1 }) else { return false }
        return segments.allSatisfy { segment in
            guard let first = segment.unicodeScalars.first, ("a" ... "z").contains(first) else { return false }
            return segment.unicodeScalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) }
        }
    }

    private static let undottedNames: Set<String> = [
        "questionmark", "xmark", "checkmark", "magnifyingglass", "ellipsis", "gearshape",
    ]

    /// Common file extensions: `photo.jpg` is a file name, not a symbol.
    private static let fileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "svg", "pdf", "txt", "md", "csv", "json", "xml", "html", "zip", "doc", "docx", "xls", "xlsx",
        "ppt", "pptx", "mp3", "mp4", "mov", "wav", "swift", "js", "py", "log",
    ]

    private static let domainEndings: Set<String> = [
        "com", "org", "net", "io", "app", "dev", "id", "co", "uk", "edu", "gov", "me", "ai",
    ]
}
