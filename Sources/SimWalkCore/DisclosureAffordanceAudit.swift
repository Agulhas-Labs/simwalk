//
// Copyright © Agulhas Labs
//

import Foundation

/// Finds rows that draw a disclosure chevron and asks, of one bundle, whether they are consistently typed as controls.
///
/// This is **not** the structural differ, and the distinction is worth keeping. The differ compares a capture against a reference frame or against another run; this compares a screen against its own peers, inside a single bundle, and needs neither. The question it answers — "this row looks tappable and is not typed as one, unlike the nine that are" — came out of a real review where answering it by hand took twenty minutes of walking every `ax-tree.json` with a one-liner.
///
/// It reports a **minority against a majority** rather than an absolute rule, because "a chevron implies a control" is a convention, not a law, and a codebase that genuinely draws decorative chevrons everywhere should not be nagged on every screen. What is suspicious is the same shape being typed two different ways in the same app.
public struct DisclosureAffordanceAudit {
    private let scope: BundleAuditScope

    public init(_ bundle: CaptureBundle) {
        scope = BundleAuditScope(bundle)
    }

    /// Every disclosure row in the bundle, in screen then state then tree order.
    ///
    /// Reads through `BundleAuditScope`, so a screen recorded as `unexpectedScreen` contributes nothing here and is named by `coverage()` instead.
    public func rows() throws -> [DisclosureRow] {
        try rows(in: scope.captures())
    }

    /// The rows whose typing disagrees with how the rest of the bundle types the same shape.
    ///
    /// Returns nothing when the bundle is consistent either way — all controls, or all not.
    ///
    /// Carries its own `Coverage`, and that is not decoration: `rows()` reads captures, so a screen the walk never captured contributes nothing and is indistinguishable from a screen with no chevrons on it. A bundle of eleven screens where eight were captured used to produce "no disclosure rows found" and exit 0 — a clean bill of health over three screens nothing had opened.
    public func findings() throws -> Findings {
        try findings(over: scope.captures())
    }

    /// The same verdict over captures the caller has already read, so a run of several rules decodes each tree once.
    func findings(over captures: [BundleAuditScope.Capture]) -> Findings {
        let all = rows(in: captures)
        let controls = all.filter(\.isControl)
        let others = all.filter { !$0.isControl }
        return Findings(controlRows: controls, uncontrolledRows: others, coverage: coverage())
    }

    /// Which of the walk's screens this audit could actually read, and which it could not.
    public func coverage() -> Coverage {
        scope.coverage()
    }

    private func rows(in captures: [BundleAuditScope.Capture]) -> [DisclosureRow] {
        captures.flatMap { Self.disclosureRows(in: $0.tree, screenID: $0.screenID, stateSlug: $0.stateSlug) }
    }

    /// Rows in one tree that draw a trailing disclosure glyph.
    ///
    /// A row qualifies when it carries a label of its own — so it is a row a user reads, not a layout box — and holds a descendant that is small, unlabelled, and pressed against the row's trailing edge. The thresholds are generous relative to the real glyph (7.7 × 13.7, its right edge 8pt inside its row's) because they are describing a class of symbol rather than one asset, and a check that only ever matches the exact chevron this app ships is a check that silently stops working when the design does.
    static func disclosureRows(in tree: AXNode, screenID: String, stateSlug: String) -> [DisclosureRow] {
        tree.flattened.compactMap { node in
            guard isDisclosureRow(node), let label = node.label else { return nil }
            return DisclosureRow(
                screenID: screenID,
                stateSlug: stateSlug,
                type: node.type,
                label: label,
                frame: node.frame
            )
        }
    }

    /// Whether `node` is a disclosure row: it carries a label of its own and a trailing glyph among its children — the one test `discover` taps a row by as well (`DiscoverClassifier`).
    static func isDisclosureRow(_ node: AXNode) -> Bool {
        guard let label = node.label, !label.isEmpty else { return false }
        return node.children.contains { isTrailingGlyph($0, within: node) }
    }

    /// Whether a child reads as a disclosure glyph drawn at the end of its row.
    private static func isTrailingGlyph(_ child: AXNode, within row: AXNode) -> Bool {
        guard child.label == nil || child.label?.isEmpty == true else { return false }
        guard child.frame.width > 0, child.frame.width <= maximumGlyphWidth else { return false }
        guard child.frame.height > 0, child.frame.height <= maximumGlyphHeight else { return false }
        // Measured from the trailing edge inwards, so it holds at any screen width — an absolute x would
        // describe this device and no other.
        let inset = (row.frame.x + row.frame.width) - (child.frame.x + child.frame.width)
        return inset >= 0 && inset <= maximumTrailingInset
    }

    private static let maximumGlyphWidth = 16.0
    private static let maximumGlyphHeight = 24.0
    private static let maximumTrailingInset = 24.0
}

public extension DisclosureAffordanceAudit {
    /// What the audit was able to look at — the bundle's, shared by every rule of `bundle audit`.
    typealias Coverage = BundleAuditScope.Coverage

    /// The audit's verdict for one bundle.
    struct Findings: Equatable, Sendable {
        /// Disclosure rows typed as something operable.
        public let controlRows: [DisclosureRow]
        /// Disclosure rows that are not — the finding, when the bundle also contains rows that are.
        public let uncontrolledRows: [DisclosureRow]
        /// What the verdict is a verdict *over* — required rather than defaulted, because a finding with no stated coverage is the overclaim this carries it to prevent.
        public let coverage: Coverage

        public init(controlRows: [DisclosureRow], uncontrolledRows: [DisclosureRow], coverage: Coverage) {
            self.controlRows = controlRows
            self.uncontrolledRows = uncontrolledRows
            self.coverage = coverage
        }

        /// Whether this is a finding at all.
        ///
        /// Both sides must be non-empty: rows typed inconsistently is a defect, rows typed uniformly is a convention, and the audit has no standing to call a whole app's convention wrong.
        public var isInconsistent: Bool {
            !controlRows.isEmpty && !uncontrolledRows.isEmpty
        }
    }
}
