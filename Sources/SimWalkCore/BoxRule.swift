//
// Copyright © Agulhas Labs
//

import Foundation

/// A paired section whose box changed beyond a tolerance — measured only in the ways a change of value cannot move it.
///
/// **What a value change does to a box, and so what is not measured.** A list that holds another row grows its section; a longer figure widens the text that holds it, and a section whose edge is that text's edge with it (the workout detail's lead card, `2.51 km in 10:28` → `112.51 km in 110:28`: 340 → 348 pt, same shape); a sentence that wraps makes its section taller; and every section below a growing one moves down with it. None of that is form. So a content section is measured only by extents no text run's content sets:
/// - its **container** (``ScreenSection/containerFrame``) — the rows, cards and callouts the layout sizes: their **leading edge** and **width** always, their **height** only where the section holds the same text runs by shape, as many of each, each shape's runs as tall as before — a row more of the same shape is a longer list, and a taller run is a line that wrapped;
/// - a section with no container, whose edges are wherever its words end, is not measured by its edges at all;
/// - the **top** is compared as the gap to the content section above, and only where that is the same section on both sides — a card pushed down by a longer list keeps its gap — or, for the first content section, as the top itself — except on a screen the walk reached by a `scrollTo` (``SegmentedCapture/scrolled``), where how far it scrolled follows from how many rows sit above the target, so the top is not measured on either side;
/// - **bars** are pinned by the system, so their whole frame is compared as it is.
public struct BoxRule: FormRule {
    /// The largest change, in points, that is not a flag.
    public var tolerance: Double

    public init(tolerance: Double = BoxRule.defaultTolerance) {
        self.tolerance = tolerance
    }

    /// Set from the real pair — two walks of one build a day apart (2026-09-29): every measure this rule compares agreed to within 0.67 pt there (a figure's run a fraction wider, sub-point rounding), so 2 pt is three times that noise and still half the smallest spacing step, 4 pt, a layout change moves an edge by.
    public static var defaultTolerance: Double {
        2
    }

    /// One flag per paired section with a measure past the tolerance, in the reference's order.
    public func flags(reference: SegmentedCapture, run: SegmentedCapture) -> [FormFlag] {
        reference.sections.compactMap { referenceSection in
            guard let runSection = run.section(keyed: referenceSection.key) else { return nil }
            let changes = measures(referenceSection, in: reference, against: runSection, in: run)
                .filter { abs($0.reference - $0.run) > tolerance }
            guard !changes.isEmpty else { return nil }
            return FormFlag(
                key: referenceSection.key,
                finding: .box(changes),
                crops: [reference.crop(of: referenceSection, side: .reference), run.crop(of: runSection, side: .run)]
            )
        }
    }

    /// The measures a value change cannot move, on each side.
    func measures(
        _ referenceSection: ScreenSection,
        in reference: SegmentedCapture,
        against runSection: ScreenSection,
        in run: SegmentedCapture
    ) -> [FormFlag.BoxChange] {
        let referenceFrame = referenceSection.frame
        let runFrame = runSection.frame
        guard referenceSection.role == .content else {
            return [
                FormFlag.BoxChange(measure: .leadingEdge, reference: referenceFrame.x, run: runFrame.x),
                FormFlag.BoxChange(measure: .top, reference: referenceFrame.y, run: runFrame.y),
                FormFlag.BoxChange(measure: .width, reference: referenceFrame.width, run: runFrame.width),
                FormFlag.BoxChange(measure: .height, reference: referenceFrame.height, run: runFrame.height),
            ]
        }
        let referenceContainer = referenceSection.containerFrame
        let runContainer = runSection.containerFrame
        var changes: [FormFlag.BoxChange] = []
        if let referenceContainer, let runContainer {
            changes.append(FormFlag.BoxChange(measure: .leadingEdge, reference: referenceContainer.x, run: runContainer.x))
        }
        let referenceAbove = reference.contentSection(before: referenceSection)
        let runAbove = run.contentSection(before: runSection)
        if let referenceAbove, let runAbove, referenceAbove.key == runAbove.key {
            changes.append(FormFlag.BoxChange(measure: .gapAbove, reference: referenceFrame.y - referenceAbove.frame.maxY, run: runFrame.y - runAbove.frame.maxY))
        } else if referenceAbove == nil, runAbove == nil, !reference.scrolled, !run.scrolled {
            changes.append(FormFlag.BoxChange(measure: .top, reference: referenceFrame.y, run: runFrame.y))
        }
        guard let referenceContainer, let runContainer else { return changes }
        changes.append(FormFlag.BoxChange(measure: .width, reference: referenceContainer.width, run: runContainer.width))
        if sameLines(referenceSection, runSection) {
            changes.append(FormFlag.BoxChange(measure: .height, reference: referenceContainer.height, run: runContainer.height))
        }
        return changes
    }

    /// Whether the two sections hold the same runs by shape, as many of each, and each shape's runs, tallest to shortest, are as tall on both sides: nothing was added, and nothing wrapped onto another line.
    func sameLines(_ referenceSection: ScreenSection, _ runSection: ScreenSection) -> Bool {
        let referenceHeights = Self.runHeights(of: referenceSection)
        let runHeights = Self.runHeights(of: runSection)
        guard Set(referenceHeights.keys) == Set(runHeights.keys) else { return false }
        return referenceHeights.allSatisfy { shape, heights in
            let other = runHeights[shape] ?? []
            return heights.count == other.count && zip(heights.sorted(), other.sorted()).allSatisfy { abs($0 - $1) <= tolerance }
        }
    }

    /// The heights of a section's runs, by shape.
    static func runHeights(of section: ScreenSection) -> [String: [Double]] {
        section.textRuns.reduce(into: [:]) { heights, run in heights[run.shape, default: []].append(run.frame.height) }
    }
}
