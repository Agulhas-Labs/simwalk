//
// Copyright © Agulhas Labs
//

import Foundation

/// One difference of form between two captures of a screen in the same state: which section, what differs, and the crops that show it.
public struct FormFlag: Codable, Equatable, Sendable {
    /// The section's key — what paired it, or failed to.
    public var key: String
    /// What differs.
    public var finding: Finding
    /// The crops that show it: one for a section on one side only, one per side otherwise, reference first.
    public var crops: [SectionCrop]

    public init(key: String, finding: Finding, crops: [SectionCrop]) {
        self.key = key
        self.finding = finding
        self.crops = crops
    }

    /// Whether the reference has this same finding, so the run did not introduce it: reported, but not a difference between the two bundles.
    public var isInherited: Bool {
        switch finding {
        case let .overlappingRuns(_, _, alsoInReference), let .overlappingSections(_, alsoInReference), let .degenerateChart(_, _, alsoInReference):
            alsoInReference
        case .onlyIn, .onlyInList, .moved, .box, .rowTemplate:
            false
        }
    }

    /// The rule that raised this flag, as it is printed.
    public var rule: String {
        switch finding {
        case .onlyIn, .onlyInList: "presence"
        case .moved: "order"
        case .box: "box"
        case .rowTemplate: "row template"
        case .overlappingRuns, .overlappingSections: "overlap"
        case .degenerateChart: "degenerate chart"
        }
    }
}

public extension FormFlag {
    /// What one rule found.
    enum Finding: Codable, Equatable, Sendable {
        /// The section is on this side only (``PresenceRule``).
        case onlyIn(BundleDiff.Side)
        /// The section is on this side only, and its body is a list: one or more rows of one template, which an app may draw only when it has rows (``PresenceRule``).
        case onlyInList(BundleDiff.Side)
        /// The section is drawn at a different place among the content sections both sides share, counted from 1 (``OrderRule``).
        case moved(referencePosition: Int, runPosition: Int, shared: Int)
        /// The section's box changed beyond the tolerance in each of these measures (``BoxRule``).
        case box([BoxChange])
        /// A row of this template is on this side only, in a list-like section both sides have; `row` is the first such row's runs by shape (``RowTemplateRule``).
        case rowTemplate(side: BundleDiff.Side, template: [RowEdge], row: [String])
        /// Two runs of the section, by shape, cross on the run side (``OverlapRule``).
        case overlappingRuns(first: String, second: String, alsoInReference: Bool)
        /// The section and the content section keyed `other` cross on the run side (``OverlapRule``).
        case overlappingSections(other: String, alsoInReference: Bool)
        /// A chart in the section has an axis row, by its ticks' shapes, under a plot `plot` points tall on the run side (``DegenerateChartRule``).
        case degenerateChart(axis: [String], plot: Double, alsoInReference: Bool)
    }

    /// The edge of its row a run sits on, which is what a row template is written in.
    enum RowEdge: String, Codable, Sendable {
        case leading
        case trailing
    }

    /// One measure of a section's box on each side, in points.
    struct BoxChange: Codable, Equatable, Sendable {
        public var measure: BoxMeasure
        public var reference: Double
        public var run: Double

        public init(measure: BoxMeasure, reference: Double, run: Double) {
            self.measure = measure
            self.reference = reference
            self.run = run
        }
    }

    /// A measure of a section's box.
    enum BoxMeasure: String, Codable, Sendable {
        /// Its left edge.
        case leadingEdge
        /// Its top edge, measured where nothing is above it to measure from: a bar, or the first content section.
        case top
        /// The space between it and the content section above it, where that is the same section on both sides.
        case gapAbove
        case width
        case height
    }
}
