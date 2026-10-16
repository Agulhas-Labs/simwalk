//
// Copyright © Agulhas Labs
//

import Foundation

/// A new kind of row in a list: a row template one side of a paired list-like section has and the other does not.
///
/// How many rows of each kind there are is never a flag — a longer list is fixture data.
///
/// **A row is a line** (``TextRunLines``): a title, the subtitle under it and the figure beside both. **Its template is where its runs sit, not what they say.** In the real pair (two walks of one build, 2026-09-29) the text of a row is itself data — a session's sport (`Walk`), a weekday, a sport's filter chip — so a template written from the runs' shapes flags the day's workouts. The template is each run, in tree order, written by the edge it sits on within its row: `leading` at the row's leading edge, `trailing` at its trailing edge, and a run between the two left out, so a row of filter chips or axis ticks reads alike however many it holds. A row that loses its subtitle, gains a line of error text or moves its figure under its title is a new template.
///
/// **List-like** means some template of two runs or more is shared by two rows on either side: a heading over a paragraph is not a list.
public struct RowTemplateRule: FormRule {
    /// How far, in points, a run may sit from its row's edge and still be on it.
    public var tolerance: Double

    public init(tolerance: Double = BoxRule.defaultTolerance) {
        self.tolerance = tolerance
    }

    /// Row templates only in the reference, section by section in its order, then those only in the run, in its order.
    public func flags(reference: SegmentedCapture, run: SegmentedCapture) -> [FormFlag] {
        let paired = reference.contentSections.compactMap { referenceSection in
            run.section(keyed: referenceSection.key).map { (reference: referenceSection, run: $0) }
        }
        let listLike = paired.filter { isListLike($0.reference) || isListLike($0.run) }
        let referenceOnly = listLike.flatMap { pair in
            only(in: pair.reference, against: pair.run).map { row in
                flag(row, section: pair.reference, side: .reference, capture: reference)
            }
        }
        let runOnly = listLike.flatMap { pair in
            only(in: pair.run, against: pair.reference).map { row in
                flag(row, section: pair.run, side: .run, capture: run)
            }
        }
        return referenceOnly + runOnly
    }

    func flag(_ row: [ScreenSection.TextRun], section: ScreenSection, side: BundleDiff.Side, capture: SegmentedCapture) -> FormFlag {
        FormFlag(
            key: section.key,
            finding: .rowTemplate(side: side, template: template(of: row), row: row.map(\.shape)),
            crops: [capture.crop(of: section, side: side)]
        )
    }

    /// The first row of each template `section` has and `other` does not, in order.
    func only(in section: ScreenSection, against other: ScreenSection) -> [[ScreenSection.TextRun]] {
        let otherTemplates = Set(TextRunLines.lines(of: other.textRuns).map(template(of:)))
        var seen: Set<[FormFlag.RowEdge]> = []
        return TextRunLines.lines(of: section.textRuns).filter { row in
            let rowTemplate = template(of: row)
            return !otherTemplates.contains(rowTemplate) && seen.insert(rowTemplate).inserted
        }
    }

    /// Whether some template of two runs or more is shared by two rows of `section`.
    func isListLike(_ section: ScreenSection) -> Bool {
        let templates = TextRunLines.lines(of: section.textRuns).filter { $0.count >= 2 }.map(template(of:))
        return Set(templates).count < templates.count
    }

    /// The row's runs, in tree order, by the edge each sits on; a run on neither edge is left out.
    func template(of row: [ScreenSection.TextRun]) -> [FormFlag.RowEdge] {
        let span = TextRunLines.span(of: row)
        return row.compactMap { run in
            if abs(run.frame.minX - span.minX) <= tolerance {
                return .leading
            }
            if abs(run.frame.maxX - span.maxX) <= tolerance {
                return .trailing
            }
            return nil
        }
    }
}
