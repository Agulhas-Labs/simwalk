//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// `AXSegmenter` on captures of `Fixtures/SegmenterFixture`, a sailing log (how each was made: `Fixtures/SegmenterFixture/README.md`): the keys a section pairs by survive a state and a change of data, and a chart card whose plot collapsed is a section of its own.
struct AXSegmenterTests {
    /// The log's summary in light, and in dark at accessibility Large text, where every box moves and the last rows fall below the fold: the same keys, in the same order.
    @Test
    func lightAndDarkStatesSegmentToTheSameKeys() throws {
        let light = try Self.sections("segmenter-summary-light")
        let dark = try Self.sections("segmenter-summary-dark-axl")

        #expect(light.map(\.key) == ["untitled", "Underway", "Check soon", "Before next sail", "tab bar"])
        #expect(dark.map(\.key) == light.map(\.key))
        #expect(dark.map(\.frame) != light.map(\.frame))
    }

    /// A section the app draws empty (`Underway` with its row gone) does not swallow the heading after it: `Check soon` keeps its own key, so it pairs with the other day's instead of flagging for a row count.
    @Test
    func anEmptySectionDoesNotSwallowTheNextHeading() throws {
        var tree = try Self.tree("segmenter-summary-light")
        Self.remove(label: "Wind speed, Up 4 kn on the last passage, 14 kn", from: &tree)
        let keys = AXSegmenter().sections(of: tree).map(\.key)

        #expect(keys == ["untitled", "Underway", "Check soon", "Before next sail", "tab bar"])
    }

    /// Passages in two weeks (captured with and without `-SegmenterFixtureLaterWeek`): another week's dates, other figures, three passages against four and two boats against three — the same keys.
    @Test
    func figuresDatesAndListLengthsLeaveTheKeysAlone() throws {
        let earlier = try Self.sections("segmenter-passages-first-week")
        let later = try Self.sections("segmenter-passages-later-week")

        #expect(earlier.map(\.key) == ["untitled", "Passages", "By boat", "Days afloat", "Too few passages yet", "toolbar", "tab bar"])
        #expect(later.map(\.key) == earlier.map(\.key))
        #expect(later.map(\.textRuns.count) != earlier.map(\.textRuns.count))
    }

    /// A passage's detail: the Boat speed card — its header row, the axis row with nothing drawn above it, its two figures — is one section, apart from the wind chart before it and the earlier passages after it.
    ///
    /// On iOS 27 the navigation stack also puts a full-screen `Toolbar` element in the tree, read as a bar.
    @Test
    func theBoatSpeedCardIsASectionOfItsOwn() throws {
        let sections = try Self.sections("segmenter-passage-detail")
        let boatSpeed = try #require(sections.first { $0.key == "Boat speed" })
        let shapes = boatSpeed.textRuns.map(\.shape)

        #expect(sections.map(\.key) == ["navigation bar", "Coastal passage", "Wind speed", "Boat speed", "Earlier passages", "toolbar", "tab bar"])
        #expect(Array(shapes.prefix(8)) == ["Boat speed", "{n} kn avg", "depart", "arrive", "{n} kn", "Avg speed", "{n} kn", "Top speed"])
        #expect(!shapes.contains("Wind speed"))
        #expect(!shapes.contains("Earlier passages"))
    }

    /// Bars are sections of their own, marked; content the tree holds below the fold is kept and says so.
    @Test
    func barsAreMarkedAndContentBelowTheFoldIsKept() throws {
        let sections = try Self.sections("segmenter-passage-detail")

        #expect(sections.first?.role == .navigationBar)
        #expect(sections.last?.role == .tabBar)
        #expect(sections.first { $0.key == "Earlier passages" }?.placement == .partlyOffScreen)
        #expect(sections.first { $0.key == "Boat speed" }?.placement == .onScreen)
    }

    /// A row's title over its subtitle is not a header row: `Check the bilge pump` stays in `Before next sail`.
    @Test
    func aRowWithASubtitleIsNotAHeading() throws {
        let beforeNextSail = try #require(try Self.sections("segmenter-summary-light").first { $0.key == "Before next sail" })

        #expect(beforeNextSail.textRuns.map(\.shape).contains("Check the bilge pump"))
    }

    /// A text's shape writes every number `{n}`, signed, grouped or timed.
    @Test
    func aShapeWritesEveryNumberAsAPlaceholder() {
        #expect(TextShape.of("+0.29 km") == "{n} km")
        #expect(TextShape.of("−0.05 km") == "{n} km")
        #expect(TextShape.of("19:49–20:02") == "{n}:{n}–{n}:{n}")
        #expect(TextShape.of("2,300 steps") == "{n} steps")
        #expect(TextShape.of("Boat speed") == "Boat speed")
    }

    private static func sections(_ fixture: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [ScreenSection] {
        try AXSegmenter().sections(of: tree(fixture, sourceLocation: sourceLocation))
    }

    private static func tree(_ fixture: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> AXNode {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        return try JSONDecoder().decode(AXNode.self, from: Data(contentsOf: url))
    }

    /// `node` without any element labelled `label`, below it.
    private static func remove(label: String, from node: inout AXNode) {
        node.children.removeAll { $0.label == label }
        for index in node.children.indices {
            remove(label: label, from: &node.children[index])
        }
    }
}
