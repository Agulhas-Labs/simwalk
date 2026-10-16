//
// Copyright © Agulhas Labs
//

import Foundation

/// A section on one side only: a card, a bar or a group that one capture has and the other does not.
///
/// A content section whose body is a list carries ``FormFlag/Finding/onlyInList`` instead, which the reader is told may be data. Bars count as well as content — a tab bar gone missing is a finding about form. Each flag names the crop of the side the section is on; the other side has nothing to show.
public struct PresenceRule: FormRule {
    public init() {}

    /// Sections only in the reference, in its order, then sections only in the run, in its order.
    public func flags(reference: SegmentedCapture, run: SegmentedCapture) -> [FormFlag] {
        Self.missing(from: run, in: reference, side: .reference) + Self.missing(from: reference, in: run, side: .run)
    }

    /// The sections of `capture` that `other` has no section keyed alike for, as flags on `side`.
    static func missing(from other: SegmentedCapture, in capture: SegmentedCapture, side: BundleDiff.Side) -> [FormFlag] {
        let keys = Set(other.sections.map(\.key))
        return capture.sections.filter { !keys.contains($0.key) }.map { section in
            FormFlag(key: section.key, finding: isList(section) ? .onlyInList(side) : .onlyIn(side), crops: [capture.crop(of: section, side: side)])
        }
    }

    /// The fewest single-run lines that read as stacked rows: a title, its subtitle and its figure.
    ///
    /// A heading over one or two lines is a note, not a list.
    static var minimumStackedLines: Int {
        3
    }

    /// Whether `section`'s body — everything after its heading line — is rows sharing one row template (``RowTemplateRule``), with no axis row (``DegenerateChartRule``) in the section.
    ///
    /// Such a card the app may draw only when it has rows; a chart card is not a list, so a vanished chart is never excused. A row is a line of two runs or more, or, at the accessibility text sizes where a row's runs wrap onto lines of their own, one of at least ``minimumStackedLines`` lines of one run each.
    static func isList(_ section: ScreenSection) -> Bool {
        guard section.role == .content, !DegenerateChartRule.hasAxisRow(in: section) else { return false }
        let body = TextRunLines.lines(of: section.textRuns).dropFirst()
        guard body.contains(where: { $0.count >= 2 }) || body.count >= minimumStackedLines else { return false }
        let rowTemplate = RowTemplateRule()
        return Set(body.map(rowTemplate.template(of:))).count == 1
    }
}
