//
// Copyright © Agulhas Labs
//

import Foundation

/// A chart drawn with no room for its plot: an axis row sitting directly under the text above it — exactly a field round's power-chart find.
///
/// **A defect in one capture, not a difference between two.** The plot of a SwiftUI chart is not in the tree at all; it is the gap between the axis row and the text above it (Brief §8, *Segmenting by the tree alone*). So this rule measures the run side on its own and flags every degenerate chart it finds there, saying when the reference has the same one — a bug both days share is still a bug. A degenerate chart on the reference only is the run's fix, not a finding.
///
/// **An axis row**, from two walks of one build (2026-09-29), is a line of a content section that:
/// - is not the section's first line, which is its heading row;
/// - holds two runs or more, none taller than the section's heading run — tick labels are caption text, never a 44 pt control;
/// - stands alone: no run of the section within ``pairGap`` directly above or below any of its runs, which is what a stat grid's value over its label does;
/// - spans at least ``minimumSpan`` of the section's text width, since ticks mark the ends of a plot;
/// - with three runs or more, is evenly spaced: every step between tick centres within ``spacingTolerance`` of their mean;
/// - reads as ticks rather than a row of labels: its runs sit apart, every gap between neighbours at least ``tickSeparation`` of their mean width, or every run leads with a number (a time, a count of days) — a stack's `First Second Third`, a row of filter chips, sits packed at its spacing and names things rather than values.
///
/// **The plot** is the gap from the nearest run above the axis row that shares its horizontal extent — the chart's heading or summary, never a y-axis label beside the plot — to the axis row's top. It is degenerate below ``plotLines`` times the axis row's own height: no room for two lines of its labels.
public struct DegenerateChartRule: FormRule {
    public init() {}

    /// Two lines of the axis labels' own height.
    ///
    /// The real plots measured 76 to 126 pt over 12–13 pt labels; the Power card's 14 pt is one line's spacing.
    public static var plotLines: Double {
        2
    }

    /// The widest gap, in points, between a figure and its label in a stat grid is 4 pt; the narrowest between a real tick and the run beside it, 13 pt.
    static var pairGap: Double {
        8
    }

    /// The real axis rows span 87–100 % of their section's text; a label and its trailing figure, 63 %.
    static var minimumSpan: Double {
        0.8
    }

    /// Bar-chart day letters and time ticks step within 7 % of their mean.
    static var spacingTolerance: Double {
        0.25
    }

    /// The narrowest gap between neighbouring ticks, in the line's mean tick width, for ticks that do not lead with a number.
    ///
    /// The real axes' runs sit 1.4 (sleep's weekdays) to 12 (Power's `start` … `finish`) mean widths apart; the route fixture's `First Second Third`, packed at a 16 pt stack spacing, 0.36. The one packed real axis, sleep's times at 0.32, leads every tick with a number.
    static var tickSeparation: Double {
        1
    }

    /// One flag per degenerate chart in the run, in the run's order.
    ///
    /// A chart is the same chart on the other side by its place among the section's axis rows, not by its ticks: the ticks are data — a week's day letters start on another day tomorrow.
    public func flags(reference: SegmentedCapture, run: SegmentedCapture) -> [FormFlag] {
        run.contentSections.flatMap { runSection in
            let referenceSection = reference.section(keyed: runSection.key)
            let referenceAxes = referenceSection.map(Self.axisRows(in:)) ?? []
            return Self.axisRows(in: runSection).enumerated().filter(\.element.isDegenerate).map { index, axis in
                let alsoInReference = referenceAxes.indices.contains(index) && referenceAxes[index].isDegenerate
                let referenceCrop = alsoInReference ? referenceSection.map { [reference.crop(of: $0, side: .reference)] } ?? [] : []
                return FormFlag(
                    key: runSection.key,
                    finding: .degenerateChart(axis: axis.shapes, plot: axis.plot, alsoInReference: alsoInReference),
                    crops: referenceCrop + [run.crop(of: runSection, side: .run)]
                )
            }
        }
    }

    /// Every axis row in `section` with the plot above it, top to bottom.
    static func axisRows(in section: ScreenSection) -> [AxisRow] {
        guard let heading = section.textRuns.first else { return [] }
        let lines = TextRunLines.lines(of: section.textRuns)
        let sectionSpan = TextRunLines.span(of: section.textRuns)
        return lines.dropFirst().compactMap { line in
            guard isAxis(line, in: section, headingHeight: heading.frame.height, sectionWidth: sectionSpan.maxX - sectionSpan.minX) else { return nil }
            let span = TextRunLines.span(of: line)
            let top = line.map(\.frame.minY).min() ?? 0
            let above = section.textRuns.filter { run in
                run.frame.maxY <= top + 1 && run.frame.maxX > span.minX && run.frame.minX < span.maxX
            }
            guard let plotTop = above.map(\.frame.maxY).max() else { return nil }
            return AxisRow(shapes: line.map(\.shape), plot: top - plotTop, height: line.map(\.frame.height).max() ?? 0)
        }
    }

    /// Whether any line of `section` after its heading reads as a chart's axis row, whether or not a plot above it can be measured.
    static func hasAxisRow(in section: ScreenSection) -> Bool {
        guard let heading = section.textRuns.first else { return false }
        let sectionSpan = TextRunLines.span(of: section.textRuns)
        return TextRunLines.lines(of: section.textRuns).dropFirst().contains {
            isAxis($0, in: section, headingHeight: heading.frame.height, sectionWidth: sectionSpan.maxX - sectionSpan.minX)
        }
    }

    /// Whether `line` reads as a chart's axis row (see the type's documentation).
    static func isAxis(_ line: [ScreenSection.TextRun], in section: ScreenSection, headingHeight: Double, sectionWidth: Double) -> Bool {
        let span = TextRunLines.span(of: line)
        guard line.count >= 2,
              line.allSatisfy({ $0.frame.height <= headingHeight + BoxRule.defaultTolerance }),
              sectionWidth > 0, (span.maxX - span.minX) / sectionWidth >= minimumSpan else { return false }
        let paired = line.contains { tick in
            section.textRuns.contains { other in
                other != tick && other.frame.horizontalOverlap(with: tick.frame) > 0
                    && (abs(other.frame.minY - tick.frame.maxY) < pairGap || abs(tick.frame.minY - other.frame.maxY) < pairGap)
            }
        }
        return !paired && isEvenlySpaced(line) && readsAsTicks(line)
    }

    /// Whether the runs read as a chart's ticks rather than a row of labels: they sit at least ``tickSeparation`` of their mean width apart, or each leads with a number.
    static func readsAsTicks(_ line: [ScreenSection.TextRun]) -> Bool {
        guard !line.allSatisfy({ $0.shape.hasPrefix(RouteTarget.placeholder) }) else { return true }
        let frames = line.map(\.frame).sorted { $0.minX < $1.minX }
        let meanWidth = frames.map(\.width).reduce(0, +) / Double(frames.count)
        return zip(frames.dropFirst(), frames).allSatisfy { next, previous in
            next.minX - previous.maxX >= tickSeparation * meanWidth
        }
    }

    /// Whether the runs' centres step evenly left to right; two runs always do.
    static func isEvenlySpaced(_ line: [ScreenSection.TextRun]) -> Bool {
        let centres = line.map { $0.frame.minX + $0.frame.width / 2 }.sorted()
        let steps = zip(centres.dropFirst(), centres).map { $0 - $1 }
        guard steps.count >= 2 else { return true }
        let mean = steps.reduce(0, +) / Double(steps.count)
        return steps.allSatisfy { abs($0 - mean) <= spacingTolerance * mean }
    }
}

extension DegenerateChartRule {
    /// One axis row: its ticks by shape, the height of the plot above it, and its own height, in points.
    struct AxisRow: Equatable {
        let shapes: [String]
        let plot: Double
        let height: Double

        /// Whether the plot is too short to draw in: under ``DegenerateChartRule/plotLines`` lines of the axis row's own height.
        var isDegenerate: Bool {
            plot < DegenerateChartRule.plotLines * height
        }
    }
}
