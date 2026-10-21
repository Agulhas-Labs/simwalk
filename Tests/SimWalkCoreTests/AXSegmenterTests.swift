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

        #expect(earlier.map(\.key) == ["untitled", "Passages", "By boat", "Days afloat", "Too few passages yet", "tab bar"])
        #expect(later.map(\.key) == earlier.map(\.key))
        #expect(later.map(\.textRuns.count) != earlier.map(\.textRuns.count))
    }

    /// A passage's detail: the Boat speed card — its header row, the axis row with nothing drawn above it, its two figures — is one section, apart from the wind chart before it and the earlier passages after it.
    ///
    /// On iOS 27 the navigation stack also puts a full-screen `Toolbar` element in the tree: a container, not a bar, so it makes no section (SimWalk#131).
    @Test
    func theBoatSpeedCardIsASectionOfItsOwn() throws {
        let sections = try Self.sections("segmenter-passage-detail")
        let boatSpeed = try #require(sections.first { $0.key == "Boat speed" })
        let shapes = boatSpeed.textRuns.map(\.shape)

        #expect(sections.map(\.key) == ["navigation bar", "Coastal passage", "Wind speed", "Boat speed", "Earlier passages", "tab bar"])
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

    /// A real toolbar, a strip at the foot of the screen, is still a `toolbar` section beside the full-screen `Toolbar` iOS 27 adds — the only one — and a tab bar the full-screen one holds is still found.
    @Test
    func aToolbarStripIsABarBesideTheFullScreenOne() {
        let strip = AXNode(type: "Toolbar", frame: Self.frame(y: 727, height: 49), children: [
            AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 735, width: 60, height: 33), label: "Share"),
        ])
        let tabBar = AXNode(type: "TabBar", frame: Self.frame(y: 776, height: 98), children: [
            AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 784, width: 120, height: 54), label: "Passages"),
        ])
        let sections = AXSegmenter().sections(of: Self.screen([Self.stack, strip, Self.fullScreen("Toolbar", holding: [tabBar])]))

        #expect(sections.map(\.key) == ["Anchor watch", "toolbar", "tab bar"])
        #expect(sections.first { $0.role == .toolbar }?.frame == strip.frame)
    }

    /// Labelled text inside the full-screen `Toolbar` is content, not dropped with a bar nobody drew.
    @Test
    func textInsideTheFullScreenToolbarIsContent() {
        let sections = AXSegmenter().sections(of: Self.screen([Self.fullScreen("Toolbar", holding: [Self.stack])]))

        #expect(sections.map(\.key) == ["Anchor watch"])
        #expect(sections.map(\.role) == [.content])
        #expect(sections.first?.textRuns.map(\.shape) == ["Anchor watch", "Drag alarm, {n} m"])
    }

    /// The height test is the same for every bar type: a `TabBar` or `NavigationBar` framed at the whole screen is a container too.
    @Test(arguments: ["TabBar", "NavigationBar"])
    func anyFullScreenBarTypeIsAContainer(type: String) {
        let sections = AXSegmenter().sections(of: Self.screen([Self.fullScreen(type, holding: [Self.stack])]))

        #expect(sections.map(\.key) == ["Anchor watch"])
    }

    /// The demo app's account screen in Arabic (2026-10-20) carries its scroll indicator twice at one frame directly under the collection view, its value wrapped in direction marks: still an indicator, so no text run and nothing for the overlap rule to read as text over text.
    @Test
    func aRightToLeftScrollIndicatorIsNotText() {
        let indicator = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 384, y: 101, width: 30, height: 695.67),
            label: "شريط تمرير رأسي, صفحة واحدة",
            value: "\u{200F}0\u{200E}%\u{200E}",
            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 384, y: 786.67, width: 3, height: 7))]
        )
        let content = AXNode(type: "CollectionView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [indicator, indicator])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/account/light-loc_ar-rtl/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.first?.textRuns.map(\.shape) == ["Anchor watch", "Drag alarm, {n} m"])
        #expect(OverlapRule().flags(reference: capture, run: capture).isEmpty)
    }

    /// The Settings sidebar (2026-10-20) carries its scroll indicator twice at one frame inside the collection view, below the stack's level: no text run there either.
    @Test
    func aScrollIndicatorInsideASectionIsNotText() {
        let indicator = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 407, y: 116, width: 30, height: 778),
            label: "Vertical scroll bar, 2 pages",
            value: "0%",
            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 434, y: 119, width: 3, height: 525))]
        )
        let heading = Self.stack.children[0]
        let list = AXNode(type: "CollectionView", frame: Self.frame(y: 140, height: 700), children: [Self.stack.children[1], indicator, indicator])
        let content = AXNode(type: "Other", frame: Self.frame(y: 100, height: 740), children: [heading, list])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape) == ["Anchor watch", "Drag alarm, {n} m"])
        #expect(OverlapRule().flags(reference: capture, run: capture).isEmpty)
    }

    /// An indicator written in Arabic-Indic digits and the Arabic percent sign, `٥٠٪`, is an indicator too.
    @Test
    func anArabicIndicPercentageIndicatorIsNotText() {
        let indicator = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 384, y: 101, width: 30, height: 695.67),
            label: "شريط تمرير رأسي, صفحتان",
            value: "\u{200F}\u{0665}\u{0660}\u{066A}"
        )
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [indicator])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/account/light-loc_ar-rtl/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape) == ["Anchor watch", "Drag alarm, {n} m"])
    }

    /// Every locale's percent format is an indicator's value: a space between figure and sign (French, German), the sign first (Turkish), Persian digits.
    @Test(arguments: ["0\u{00A0}%", "50\u{202F}%", "%0", "\u{06F0}\u{066A}"])
    func aLocalePercentageIndicatorIsNotText(value: String) {
        let indicator = AXNode(type: "Other", frame: AXNode.Frame(x: 384, y: 101, width: 30, height: 695.67), label: "Vertical scroll bar, 2 pages", value: value)
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [indicator])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/account/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape) == ["Anchor watch", "Drag alarm, {n} m"])
    }

    /// A value that only looks like a percentage — no figure, a sign at both ends, a decimal point — keeps the element content.
    @Test(arguments: ["%", "%5%", "5.5%", "5 % 5"])
    func aNonPercentageValueIsNotAnIndicator(value: String) {
        let element = AXNode(type: "Other", frame: AXNode.Frame(x: 384, y: 101, width: 30, height: 695.67), label: "Scroll bar", value: value)
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [element])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/account/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape).contains("Scroll bar"))
    }

    /// A combined row whose value is a percentage — SwiftUI's `Battery` with `80%`, one `Other` — is content in a list cell or a card: only an element directly under a scrolling container can be its indicator.
    @Test
    func aPercentageRowInACellOrACardIsText() {
        let battery = AXNode(type: "Other", frame: AXNode.Frame(x: 32, y: 196, width: 326, height: 20), label: "Battery", value: "80%")
        let cell = AXNode(type: "Cell", frame: AXNode.Frame(x: 16, y: 180, width: 358, height: 52), children: [battery])
        let inList = AXNode(type: "CollectionView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [cell])
        let inCard = AXNode(type: "Other", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [
            AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 180, width: 358, height: 52), children: [battery]),
        ])

        for content in [inList, inCard] {
            let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/device/light/screen.png", segmenter: AXSegmenter())
            #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape) == ["Anchor watch", "Drag alarm, {n} m", "Battery"])
        }
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

    /// A heading over a row, the content of the synthetic screens.
    private static let stack = AXNode(type: "Other", frame: frame(y: 100, height: 80), children: [
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 140, height: 24), label: "Anchor watch"),
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 140, width: 180, height: 24), label: "Drag alarm, 30 m"),
    ])

    /// A full-width frame on a 402×874 screen.
    private static func frame(y: Double, height: Double) -> AXNode.Frame {
        AXNode.Frame(x: 0, y: y, width: 402, height: height)
    }

    /// An element of `type` framed at the whole screen, named by its type as iOS 27's `Toolbar` is.
    private static func fullScreen(_ type: String, holding children: [AXNode]) -> AXNode {
        AXNode(type: type, frame: frame(y: 0, height: 874), label: type, identifier: type, children: children)
    }

    /// An application whose window holds `children`.
    private static func screen(_ children: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: frame(y: 0, height: 874), label: "Logbook", children: [
            AXNode(type: "Window", frame: frame(y: 0, height: 874), children: children),
        ])
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
