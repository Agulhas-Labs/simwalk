//
// Copyright © Agulhas Labs
//

import Foundation

/// A section's text runs cut into the lines it is drawn in: runs top to bottom, each joining the line above while it shares more than a point of that line's height.
///
/// **A line is chained, not ruled.** A list row's title, its subtitle and the figure beside both are one line here, because the figure spans the two — which is what a row is to the reader and what ``RowTemplateRule`` compares; a chart's axis row, standing apart from the plot above and the figures below, is one line of its own, which is what ``DegenerateChartRule`` looks for. Within a line the runs keep tree order, the order the app declared them in, which does not move with a value.
struct TextRunLines {
    /// `runs` as lines, top to bottom, each in tree order.
    static func lines(of runs: [ScreenSection.TextRun]) -> [[ScreenSection.TextRun]] {
        let ordered = zip(runs.indices, runs).map { (offset: $0, element: $1) }.sorted { $0.element.frame.y < $1.element.frame.y }
        var lines: [[(offset: Int, element: ScreenSection.TextRun)]] = []
        var extent = AXNode.Frame(x: 0, y: 0, width: 0, height: 0)
        for entry in ordered {
            if !lines.isEmpty, extent.verticalOverlap(with: entry.element.frame) > 1 {
                lines[lines.count - 1].append(entry)
                let top = min(extent.y, entry.element.frame.y)
                extent = AXNode.Frame(x: 0, y: top, width: 0, height: max(extent.maxY, entry.element.frame.maxY) - top)
            } else {
                lines.append([entry])
                extent = AXNode.Frame(x: 0, y: entry.element.frame.y, width: 0, height: entry.element.frame.height)
            }
        }
        return lines.map { line in line.sorted { $0.offset < $1.offset }.map(\.element) }
    }

    /// The horizontal extent of `runs`: from the leftmost run's leading edge to the rightmost run's trailing edge.
    static func span(of runs: [ScreenSection.TextRun]) -> (minX: Double, maxX: Double) {
        (runs.map(\.frame.minX).min() ?? 0, runs.map(\.frame.maxX).max() ?? 0)
    }
}
