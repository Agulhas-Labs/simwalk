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

    /// Pins the parent/child shape, which already yields one run: a labelled `Other` over a `StaticText` carrying the same sentence at a wider frame is the child's run alone, and no overlap (the sibling shape of #171 is further down).
    @Test
    func aContainerLabelledLikeItsOnlyTextChildIsOneRun() {
        let sentence = "Smart Invert reverses the colours of the display, except for images."
        let footer = AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 728, width: 358, height: 62), label: sentence, children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 0, y: 728, width: 390, height: 62), label: sentence),
        ])
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([footer])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).filter { $0.text == sentence }.map(\.frame) == [AXNode.Frame(x: 0, y: 728, width: 390, height: 62)])
        #expect(OverlapRule().flags(reference: capture, run: capture).isEmpty)
    }

    /// Pins the parent/child shape: a container whose label differs from its child's is not a run either: only the text below it is.
    @Test
    func aContainerLabelledUnlikeItsTextChildIsNotARun() {
        let footer = AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 728, width: 358, height: 62), label: "Footer", children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 0, y: 728, width: 390, height: 62), label: "Smart Invert reverses the colours."),
        ])
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([footer])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.text).suffix(2) == ["Drag alarm, 30 m", "Smart Invert reverses the colours."])
    }

    /// Pins the parent/child shape: a container with the label and two text children is unchanged: both children are runs.
    @Test
    func aContainerWithTwoTextChildrenKeepsBoth() {
        let footer = AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 728, width: 358, height: 62), label: "Same", children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 0, y: 728, width: 390, height: 30), label: "Same"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 0, y: 760, width: 390, height: 30), label: "Other line"),
        ])
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([footer])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.text).suffix(2) == ["Same", "Other line"])
    }

    /// The footer sentence the tests use.
    private static var note: String {
        "Colours are reversed on the display, except for images."
    }

    /// A section footer a tree exposes twice as siblings (#171): an `Other` at the row's full width holding a `StaticText`, and a childless `Other` at the inset, both labelled with the text.
    ///
    /// One run results, the `StaticText`'s.
    @Test
    func aFooterExposedTwiceAsSiblingsIsOneRun() {
        let wide = AXNode.Frame(x: 0, y: 727.9999974568684, width: 390, height: 62)
        let inset = AXNode.Frame(x: 16, y: 727.9999974568684, width: 358, height: 62)
        let row = AXNode(type: "Other", frame: wide, identifier: Self.note, children: [AXNode(type: "StaticText", frame: wide, label: Self.note)])
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([row, AXNode(type: "Other", frame: inset, label: Self.note)])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).filter { $0.text == Self.note }.map(\.frame) == [wide])
        #expect(OverlapRule().flags(reference: capture, run: capture).isEmpty)
    }

    /// The same pair with the inset `Other` first in the tree: the same single run, the `StaticText`'s.
    @Test
    func aFooterExposedTwiceInTheOppositeOrderIsTheSameRun() {
        let wide = AXNode.Frame(x: 0, y: 727.9999974568684, width: 390, height: 62)
        let inset = AXNode.Frame(x: 16, y: 727.9999974568684, width: 358, height: 62)
        let row = AXNode(type: "Other", frame: wide, identifier: Self.note, children: [AXNode(type: "StaticText", frame: wide, label: Self.note)])
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([AXNode(type: "Other", frame: inset, label: Self.note), row])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).filter { $0.text == Self.note }.map(\.frame) == [wide])
    }

    /// A bar that exposes its text twice (#190): a `StaticText` at the strip's width and a childless labelled `Other` at the inset, the sibling shape of #171.
    ///
    /// The bar section has one run of the text, the `StaticText`'s.
    @Test
    func aBarExposingItsTextTwiceIsOneRun() {
        let wide = AXNode.Frame(x: 0, y: 735, width: 402, height: 33)
        let inset = AXNode.Frame(x: 16, y: 735, width: 370, height: 33)
        let strip = AXNode(type: "Toolbar", frame: Self.frame(y: 727, height: 49), children: [
            AXNode(type: "StaticText", frame: wide, label: Self.note),
            AXNode(type: "Other", frame: inset, label: Self.note),
        ])
        let sections = AXSegmenter().sections(of: Self.screen([Self.stack, strip]))

        #expect(sections.first { $0.role == .toolbar }?.textRuns.filter { $0.text == Self.note }.map(\.frame) == [wide])
    }

    /// Two childless labelled `Other`s with one text, the wide one first in the tree (#190): neither is a `StaticText`, so the first in tree order is kept.
    @Test
    func twoOthersWithOneTextKeepTheFirstWideOne() {
        let wide = AXNode.Frame(x: 0, y: 728, width: 390, height: 62)
        let inset = AXNode.Frame(x: 16, y: 728, width: 358, height: 62)
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([AXNode(type: "Other", frame: wide, label: Self.note), AXNode(type: "Other", frame: inset, label: Self.note)])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).filter { $0.text == Self.note }.map(\.frame) == [wide])
    }

    /// The same two `Other`s with the inset one first in the tree (#190): the first in tree order is kept, so the inset one.
    @Test
    func twoOthersWithOneTextKeepTheFirstInsetOne() {
        let wide = AXNode.Frame(x: 0, y: 728, width: 390, height: 62)
        let inset = AXNode.Frame(x: 16, y: 728, width: 358, height: 62)
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([AXNode(type: "Other", frame: inset, label: Self.note), AXNode(type: "Other", frame: wide, label: Self.note)])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).filter { $0.text == Self.note }.map(\.frame) == [inset])
    }

    /// Two `StaticText`s with one sentence at a wide and an inset frame (#190): a doubled rendering of the sentence, not one text exposed twice, so both are runs.
    @Test
    func twoStaticTextsWithOneSentenceStayTwoRuns() {
        let wide = AXNode.Frame(x: 0, y: 728, width: 390, height: 62)
        let inset = AXNode.Frame(x: 16, y: 728, width: 358, height: 62)
        let capture = SegmentedCapture(tree: Self.screen([Self.footerList([AXNode(type: "StaticText", frame: wide, label: Self.note), AXNode(type: "StaticText", frame: inset, label: Self.note)])]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).filter { $0.text == Self.note }.map(\.frame) == [wide, inset])
    }

    /// Two runs with one label stay two unless they share y and height and one holds the other across: crossing without containment, a different y, a different height, or different labels at the same frames.
    @Test
    func runsThatAreNotOneTextTwiceStayTwo() {
        func texts(_ first: AXNode.Frame, _ second: AXNode.Frame, labels: (String, String) = (Self.note, Self.note)) -> [String] {
            let extra = [
                AXNode(type: "StaticText", frame: first, label: labels.0),
                AXNode(type: "StaticText", frame: second, label: labels.1),
            ]
            let capture = SegmentedCapture(tree: Self.screen([Self.footerList(extra)]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())
            return capture.contentSections.flatMap(\.textRuns).map(\.text).filter { $0 == labels.0 || $0 == labels.1 }
        }
        let base = AXNode.Frame(x: 0, y: 728, width: 200, height: 62)

        #expect(texts(base, AXNode.Frame(x: 100, y: 728, width: 200, height: 62)).count == 2)
        #expect(texts(base, AXNode.Frame(x: 0, y: 760, width: 390, height: 62)).count == 2)
        #expect(texts(base, AXNode.Frame(x: 0, y: 728, width: 390, height: 30)).count == 2)
        #expect(texts(base, base, labels: ("Alpha", "Beta")) == ["Alpha", "Beta"])
    }

    /// An indicator written in Arabic-Indic digits and the Arabic percent sign, `٥٠٪`, is an indicator too.
    @Test
    func anArabicIndicPercentageIndicatorIsNotText() {
        let indicator = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 384, y: 101, width: 30, height: 695.67),
            label: "شريط تمرير رأسي, صفحتان",
            value: "\u{200F}\u{0665}\u{0660}\u{066A}",
            children: [Self.thumb]
        )
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [indicator])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/account/light-loc_ar-rtl/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape) == ["Anchor watch", "Drag alarm, {n} m"])
    }

    /// Every locale's percent format is an indicator's value: a space between figure and sign (French, German), the sign first (Turkish), Persian digits.
    @Test(arguments: ["0\u{00A0}%", "50\u{202F}%", "%0", "\u{06F0}\u{066A}"])
    func aLocalePercentageIndicatorIsNotText(value: String) {
        let indicator = AXNode(type: "Other", frame: AXNode.Frame(x: 384, y: 101, width: 30, height: 695.67), label: "Vertical scroll bar, 2 pages", value: value, children: [Self.thumb])
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [indicator])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/account/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape) == ["Anchor watch", "Drag alarm, {n} m"])
    }

    /// A value that only looks like a percentage — no figure, a sign at both ends, a decimal point — keeps the element content.
    @Test(arguments: ["%", "%5%", "5.5%", "5 % 5"])
    func aNonPercentageValueIsNotAnIndicator(value: String) {
        let element = AXNode(type: "Other", frame: AXNode.Frame(x: 384, y: 101, width: 30, height: 695.67), label: "Scroll bar", value: value, children: [Self.thumb])
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [element])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/account/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape).contains("Scroll bar"))
    }

    /// SimWalk#169: a percentage `Other` whose bare child is a 20×20 box (not a thin thumb) directly in a scroll view is content, labelled as it is.
    @Test
    func aPercentageElementWithAFatBareChildIsText() {
        let element = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 16, y: 180, width: 358, height: 52),
            label: "Battery",
            value: "80%",
            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 20, y: 190, width: 20, height: 20))]
        )
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [element])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/device/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape).contains("Battery"))
    }

    /// SimWalk#208: a combined element with a percentage for its value and no children, placed straight in a scroll view, is content, not an indicator without its thumb.
    @Test
    func aPercentageElementWithNoChildrenIsText() {
        let element = AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 180, width: 358, height: 52), label: "Storage", value: "45%")
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [element])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/device/light/screen.png", segmenter: AXSegmenter())

        #expect(capture.contentSections.flatMap(\.textRuns).map(\.shape).contains("Storage"))
    }

    /// The measured thumb shapes (3 pt thin, vertical and horizontal) are indicators, and the line sits at 4 pt: a 4 pt-thin thumb is taken, one 4.5 pt in both dimensions is not, and a zero frame counts as thin.
    @Test(arguments: [(3.0, 400.0, true), (272.0, 3.0, true), (4.0, 400.0, true), (400.0, 4.0, true), (4.5, 4.5, false), (4.5, 400.0, false), (0.0, 0.0, true)])
    func aThumbIsTakenOnlyWhenThin(width: Double, height: Double, isIndicator: Bool) {
        let indicator = AXNode(
            type: "Other",
            frame: AXNode.Frame(x: 369, y: 116, width: 30, height: 675),
            label: "Vertical scroll bar, 2 pages",
            value: "0%",
            children: [AXNode(type: "Other", frame: AXNode.Frame(x: 396, y: 119, width: width, height: height))]
        )
        let content = AXNode(type: "ScrollView", frame: Self.frame(y: 100, height: 700), children: Self.stack.children + [indicator])
        let capture = SegmentedCapture(tree: Self.screen([content]), screenshotPath: "screens/root/light/screen.png", segmenter: AXSegmenter())

        let shapes = capture.contentSections.flatMap(\.textRuns).map(\.shape)

        #expect(shapes.contains("Vertical scroll bar, {n} pages") == !isIndicator)
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

    /// A vertical indicator's thumb as the captures carry it: bare, 3 pt wide.
    private static let thumb = AXNode(type: "Other", frame: AXNode.Frame(x: 411, y: 104, width: 3, height: 500))

    /// A full-width frame on a 402×874 screen.
    private static func frame(y: Double, height: Double) -> AXNode.Frame {
        AXNode.Frame(x: 0, y: y, width: 402, height: height)
    }

    /// An element of `type` framed at the whole screen, named by its type as iOS 27's `Toolbar` is.
    private static func fullScreen(_ type: String, holding children: [AXNode]) -> AXNode {
        AXNode(type: type, frame: frame(y: 0, height: 874), label: type, identifier: type, children: children)
    }

    /// A collection view holding the stack's rows and then `extra`.
    private static func footerList(_ extra: [AXNode]) -> AXNode {
        AXNode(type: "CollectionView", frame: frame(y: 100, height: 740), children: stack.children + extra)
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
