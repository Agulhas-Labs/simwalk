//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a walkbook could not be turned into an executable plan, at whichever of the three stages failed: reading the bytes, decoding them, or validating the result.
///
/// The stages stay distinct because they mean different things to the author — a missing file is a path mistake, bytes that are not a walkbook at all (torn JSON, the wrong shape, a value its field cannot take with nothing else to report) are `malformed`, and a walkbook that names what is wrong with it — a misspelled or missing key, a step naming no step, a screen that could not be walked — is `invalid`, with every such problem listed. Collapsing them into one "invalid" would lose exactly the part worth reading.
public enum WalkbookLoadError: Error, Equatable, CustomStringConvertible {
    /// The bytes could not be read at all (no such file, no permission).
    case unreadable(source: String, reason: String)
    /// The bytes are not a walkbook: malformed JSON, JSON of the wrong shape, or a value its field cannot take — a decode that stopped with no other problem collected before it.
    case malformed(source: String, reason: String)
    /// The walkbook cannot be executed as written; every problem found is listed, not just the first — including, as the last, a decode that stopped after problems had already been collected (`WalkbookProblem.undecodable`).
    ///
    /// When a placeholder stood in for a missing key or step (`WalkbookProblem.placeholderScope`), the checks it stood in for were not run, and the description names exactly which — one screen, or the walkbook's own fields — after the list, rather than one blanket line that used to say the whole walkbook went unchecked when only the placeholder's own corner of it did (round 5, finding 1).
    case invalid(source: String, problems: [WalkbookProblem])

    public var description: String {
        switch self {
        case let .unreadable(source, reason):
            "cannot read walkbook at \(source): \(reason)"
        case let .malformed(source, reason):
            "walkbook at \(source) is not a walkbook: \(reason)"
        case let .invalid(source, problems):
            ([
                "walkbook at \(source) is not executable — \(problems.count) problem\(problems.count == 1 ? "" : "s"):",
            ] + problems.map { "  - \($0)" } + Self.skippedCheckLines(problems)).joined(separator: "\n")
        }
    }

    /// One line per placeholder's effect on validation, naming exactly what did not run and why the description reads as complete otherwise — "once the problems above are fixed", not "once it decodes", since an author staring at a listed problem and no decode error would read the old wording as a mismatch between what happened and what is claimed.
    ///
    /// A decode that stopped entirely (`WalkbookProblem.undecodable`) keeps the one line it always had: there is no walkbook, so nothing scopes to one screen or the other — every check anywhere in it was skipped, not a named part.
    private static func skippedCheckLines(_ problems: [WalkbookProblem]) -> [String] {
        guard !problems.contains(where: isUndecodable) else {
            return ["the checks that need a whole walkbook were not run — they run once it decodes"]
        }
        var lines: [String] = []
        if problems.contains(where: { $0.placeholderScope == .walkbook }) {
            lines.append("the checks for the walkbook's own name, appBundleID and screens were not run — they run once the problems above are fixed")
        }
        for index in Set(problems.compactMap { $0.placeholderScope?.screenIndex }).sorted() {
            lines.append("the checks for screen at index \(index) were not run — they run once the problems above are fixed")
        }
        return lines
    }

    private static func isUndecodable(_ problem: WalkbookProblem) -> Bool {
        guard case .undecodable = problem else { return false }
        return true
    }
}

extension WalkbookLoadError: UsageFailureClassifiable {
    /// Every case is about the walkbook argument itself — unreadable, malformed, or structurally invalid — never about the tool that tried to read it.
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
