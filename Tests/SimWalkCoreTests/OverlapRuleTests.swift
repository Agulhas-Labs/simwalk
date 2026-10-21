//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// ``OverlapRule`` on sections built by hand: what collides, what a control's tap target only touches, and what both sides share.
struct OverlapRuleTests {
    /// A run that lands on another past half its height is a new overlap, flagged plainly with the run's crop alone.
    @Test
    func aNewOverlapIsFlagged() {
        let reference = Self.capture([Self.card("Card", [Self.run("Title", y: 100, height: 20), Self.run("Body", y: 130, height: 20)])])
        let run = Self.capture([Self.card("Card", [Self.run("Title", y: 100, height: 20), Self.run("Body", y: 108, height: 20)])])

        let flags = OverlapRule().flags(reference: reference, run: run)

        #expect(flags.map(\.key) == ["Card"])
        #expect(flags.map(\.finding) == [.overlappingRuns(first: "Body", second: "Title", alsoInReference: false)])
        #expect(flags.first?.crops.map(\.side) == [.run])
    }

    /// The same two runs overlapping on both sides are one flag, marked as also in the reference, with both crops.
    @Test
    func anOverlapAlsoInTheReferenceIsReportedOnce() {
        let runs = [Self.run("Title", y: 100, height: 20), Self.run("Body", y: 108, height: 20)]
        let capture = Self.capture([Self.card("Card", runs)])

        let flags = OverlapRule().flags(reference: capture, run: capture)

        #expect(flags.map(\.finding) == [.overlappingRuns(first: "Body", second: "Title", alsoInReference: true)])
        #expect(flags.first?.crops.map(\.side) == [.reference, .run])
    }

    /// A segmented control's frame reaches 2 pt into the text under it at the default size and 10 pt at accessibility Large: a tap target, not a collision.
    @Test
    func aControlsTapTargetReachIsNotAnOverlap() {
        let defaultSize = Self.capture([Self.card("Card", [Self.run("Title", y: 100, height: 20), Self.run("Control", y: 118, height: 44)])])
        let accessibilityLarge = Self.capture([Self.card("Card", [Self.run("Date", y: 100, height: 24), Self.run("Control", y: 114, height: 59)])])

        #expect(OverlapRule().flags(reference: defaultSize, run: defaultSize).isEmpty)
        #expect(OverlapRule().flags(reference: accessibilityLarge, run: accessibilityLarge).isEmpty)
    }

    /// Two content sections whose frames cross by more than the tolerance both ways are flagged, on the first's key.
    @Test
    func twoOverlappingContentSectionsAreFlagged() {
        let reference = Self.capture([FormRuleTests.section("A", y: 100), FormRuleTests.section("B", y: 210)])
        let run = Self.capture([FormRuleTests.section("A", y: 100), FormRuleTests.section("B", y: 150)])

        let flags = OverlapRule().flags(reference: reference, run: run)

        #expect(flags.map(\.key) == ["A"])
        #expect(flags.map(\.finding) == [.overlappingSections(other: "B", alsoInReference: false)])
        #expect(flags.first?.crops.map(\.side) == [.run, .run])
    }

    /// The Settings sidebar's `Dictate` button, exposed twice at one frame, is one element, not text over text; different text at that frame still collides.
    @Test
    func oneRunExposedTwiceIsNotAnOverlap() {
        let dictate = AXNode.Frame(x: 379.7, y: 893, width: 17.3, height: 22)
        let twice = Self.capture([Self.card("Search", [
            ScreenSection.TextRun(shape: "Dictate", frame: dictate),
            ScreenSection.TextRun(shape: "Dictate", frame: dictate),
        ])])
        let stacked = Self.capture([Self.card("Search", [
            ScreenSection.TextRun(shape: "Dictate", frame: dictate),
            ScreenSection.TextRun(shape: "Search", frame: dictate),
        ])])

        #expect(OverlapRule().flags(reference: twice, run: twice).isEmpty)
        #expect(OverlapRule().flags(reference: stacked, run: stacked).map(\.finding) == [.overlappingRuns(first: "Dictate", second: "Search", alsoInReference: true)])
    }

    /// Two times drawn at one frame, `12:05` over `13:45`, share the shape `{n}:{n}` but not their text: a collision, not one element exposed twice.
    ///
    /// Segmented from a tree, so each run carries the text it was drawn with.
    @Test
    func twoTimesAtOneFrameAreAnOverlap() {
        let time = AXNode.Frame(x: 16, y: 140, width: 48, height: 22)
        let card = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 100, width: 402, height: 80), children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 140, height: 24), label: "Departures"),
            AXNode(type: "StaticText", frame: time, label: "12:05"),
            AXNode(type: "StaticText", frame: time, label: "13:45"),
        ])
        let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), label: "Logbook", children: [
            AXNode(type: "Window", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [card]),
        ])
        let capture = SegmentedCapture(tree: tree, screenshotPath: "screens/departures/light/screen.png", segmenter: AXSegmenter())

        #expect(OverlapRule().flags(reference: capture, run: capture).map(\.finding) == [
            .overlappingRuns(first: "{n}:{n}", second: "{n}:{n}", alsoInReference: true),
        ])
    }

    static func run(_ shape: String, y: Double, height: Double) -> ScreenSection.TextRun {
        ScreenSection.TextRun(shape: shape, frame: AXNode.Frame(x: 22, y: y, width: 120, height: height))
    }

    static func card(_ key: String, _ runs: [ScreenSection.TextRun]) -> ScreenSection {
        ScreenSection(key: key, role: .content, frame: AXNode.Frame(x: 14, y: 90, width: 374, height: 200), placement: .onScreen, textRuns: runs)
    }

    static func capture(_ sections: [ScreenSection]) -> SegmentedCapture {
        FormRuleTests.capture(sections)
    }
}
