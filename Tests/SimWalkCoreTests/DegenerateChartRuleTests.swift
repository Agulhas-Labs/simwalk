//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The degenerate-chart rule on captures of `Fixtures/SegmenterFixture` (how each was made: `Fixtures/SegmenterFixture/README.md`).
///
/// On the passage detail (`segmenter-passage-detail`) the Boat speed card's axis row sits 14 pt under its header, its chart drawn at no height; the Wind speed chart's 110 pt under its own.
struct DegenerateChartRuleTests {
    /// Phase 2's gate (Brief §6): the empty Boat speed plot is flagged, and the Wind speed chart — read as a chart, with its plot measured — is not.
    @Test
    func theBoatSpeedPlotIsDegenerateAndTheWindPlotIsNot() throws {
        let capture = try Self.capture("segmenter-passage-detail")
        let wind = try #require(capture.section(keyed: "Wind speed"))
        let windAxis = try #require(DegenerateChartRule.axisRows(in: wind).first)

        let flags = DegenerateChartRule().flags(reference: capture, run: capture)

        #expect(windAxis.shapes == ["{n}:{n}", "{n}:{n}", "{n}:{n}"])
        #expect(windAxis.plot > 100)
        #expect(flags.map(\.key) == ["Boat speed"])
        #expect(flags.first?.finding == .degenerateChart(axis: ["depart", "arrive"], plot: 14, alsoInReference: true))
        #expect(flags.first?.crops.map(\.side) == [.reference, .run])
    }

    /// A degenerate chart the reference does not have is flagged on the run alone, with the run's crop only.
    @Test
    func aDegenerateChartOnTheRunAloneIsNotAlsoInTheReference() throws {
        let run = try Self.capture("segmenter-passage-detail")
        var reference = run
        reference.sections.removeAll { $0.key == "Boat speed" }

        let flags = DegenerateChartRule().flags(reference: reference, run: run)

        #expect(flags.first?.finding == .degenerateChart(axis: ["depart", "arrive"], plot: 14, alsoInReference: false))
        #expect(flags.first?.crops.map(\.side) == [.run])
        #expect(DegenerateChartRule().flags(reference: run, run: reference).isEmpty)
    }

    /// A label under its figure, or a heading over a trailing figure, is not an axis row: a stat grid on its own raises nothing.
    @Test
    func aStatGridIsNotAChart() {
        let section = ScreenSection(key: "Stats", role: .content, frame: AXNode.Frame(x: 22, y: 100, width: 358, height: 60), placement: .onScreen, textRuns: [
            ScreenSection.TextRun(shape: "Stats", frame: AXNode.Frame(x: 22, y: 100, width: 60, height: 12)),
            ScreenSection.TextRun(shape: "{n} kn", frame: AXNode.Frame(x: 22, y: 120, width: 41, height: 17)),
            ScreenSection.TextRun(shape: "{n} kn", frame: AXNode.Frame(x: 339, y: 120, width: 41, height: 17)),
            ScreenSection.TextRun(shape: "Avg speed", frame: AXNode.Frame(x: 22, y: 139, width: 51, height: 12)),
            ScreenSection.TextRun(shape: "Top speed", frame: AXNode.Frame(x: 327, y: 139, width: 53, height: 12)),
        ])

        #expect(DegenerateChartRule.axisRows(in: section).isEmpty)
    }

    /// Every chart in the fixture app is read as one, its plot measured, and only the Boat speed card's is degenerate: the Wind speed and Boat speed cards on the passage detail, the wind detail's month (two end ticks), the hours-afloat detail's bars (day letters), and the anchor-watch detail's watches (packed time ticks) and last seven nights (weekdays).
    @Test
    func everyChartIsReadAsOneAndOnlyBoatSpeedIsDegenerate() throws {
        let fixtures = ["segmenter-passage-detail", "segmenter-wind-detail", "segmenter-hours-afloat-detail", "segmenter-anchor-watch-detail"]
        let captures = try fixtures.map { try Self.capture($0) }

        let axes = captures.map { capture in
            capture.contentSections.flatMap(DegenerateChartRule.axisRows(in:)).map { "\($0.shapes.joined(separator: " ")) / \(Int($0.plot.rounded()))" }
        }
        let flags = captures.flatMap { DegenerateChartRule().flags(reference: $0, run: $0) }

        #expect(axes == [
            ["{n}:{n} {n}:{n} {n}:{n} / 110", "depart arrive / 14"],
            ["{n} days ago Today / 96"],
            ["T W T F S S M / 94"],
            ["{n}:{n} pm {n}:{n} am {n}:{n} am {n}:{n} am {n}:{n} am / 126", "Tue Wed Thu Fri Sat Sun Mon / 76"],
        ])
        #expect(flags.map(\.key) == ["Boat speed"])
    }

    /// The route fixture's home, walked on iOS 27: a line of text over an `HStack` of `First`, `Second` and `Third` at 16 pt spacing, 24 pt below it — evenly spaced, spanning the section, and packed, which a chart's ticks never are.
    @Test
    func aLabelRowUnderAHeadingIsNotAnAxis() {
        let section = Self.section([
            ("Home", AXNode.Frame(x: 178.2, y: 471.7, width: 45.7, height: 20.3)),
            ("First", AXNode.Frame(x: 119.5, y: 516, width: 33.3, height: 20.3)),
            ("Second", AXNode.Frame(x: 168.8, y: 516, width: 58, height: 20.3)),
            ("Third", AXNode.Frame(x: 242.8, y: 516, width: 39.7, height: 20.3)),
        ])

        #expect(DegenerateChartRule.axisRows(in: section).isEmpty)
        #expect(!DegenerateChartRule.hasAxisRow(in: section))
    }

    /// A picker drawn as three filter chips under its heading: the chips' padding sets their labels 32 pt apart, still closer than the labels are wide.
    @Test
    func aRowOfFilterChipsIsNotAnAxis() {
        let section = Self.section([
            ("Range", AXNode.Frame(x: 22, y: 100, width: 44, height: 20)),
            ("Day", AXNode.Frame(x: 22, y: 140, width: 33, height: 20)),
            ("Week", AXNode.Frame(x: 87, y: 140, width: 44, height: 20)),
            ("Month", AXNode.Frame(x: 163, y: 140, width: 52, height: 20)),
        ])

        #expect(DegenerateChartRule.axisRows(in: section).isEmpty)
    }

    /// A content section holding `runs` in order, framed by their union.
    private static func section(_ runs: [(shape: String, frame: AXNode.Frame)]) -> ScreenSection {
        let minX = runs.map(\.frame.minX).min() ?? 0
        let minY = runs.map(\.frame.minY).min() ?? 0
        let frame = AXNode.Frame(x: minX, y: minY, width: (runs.map(\.frame.maxX).max() ?? 0) - minX, height: (runs.map(\.frame.maxY).max() ?? 0) - minY)
        return ScreenSection(key: "untitled", role: .content, frame: frame, placement: .onScreen, textRuns: runs.map { ScreenSection.TextRun(shape: $0.shape, frame: $0.frame) })
    }

    private static func capture(_ fixture: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> SegmentedCapture {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        let tree = try JSONDecoder().decode(AXNode.self, from: Data(contentsOf: url))
        return SegmentedCapture(tree: tree, screenshotPath: "screens/passage_detail/light/screen.png", segmenter: AXSegmenter())
    }
}
