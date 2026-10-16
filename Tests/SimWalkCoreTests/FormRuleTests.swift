//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The form rules on sections built by hand: what each flags, what each leaves alone because it is a value, and the crop every flag names.
struct FormRuleTests {
    /// A card on one side only is flagged on that side, with the crop of that side's screenshot; a bar counts too.
    @Test
    func aSectionOnOneSideOnlyIsAPresenceFlag() {
        let reference = Self.capture([Self.section("Summary", y: 60), Self.bar(.tabBar)])
        let run = Self.capture([Self.section("Summary", y: 60), Self.section("Working", y: 180)])

        let flags = PresenceRule().flags(reference: reference, run: run)

        #expect(flags.map(\.key) == ["tab bar", "Working"])
        #expect(flags.map(\.finding) == [.onlyIn(.reference), .onlyIn(.run)])
        #expect(flags.map { $0.crops.map(\.side) } == [[.reference], [.run]])
        #expect(flags[1].crops.first?.rect == AXNode.Frame(x: 14, y: 180, width: 374, height: 100))
    }

    /// Two cards swapped: the one that moved is flagged with its position among the shared content on each side; bars and one-sided sections are not ordered.
    @Test
    func aMovedCardIsAnOrderFlag() {
        let reference = Self.capture([Self.bar(.navigationBar), Self.section("A", y: 100), Self.section("B", y: 210), Self.section("C", y: 320), Self.section("Gone", y: 430)])
        let run = Self.capture([Self.section("C", y: 100), Self.section("A", y: 210), Self.section("B", y: 320), Self.bar(.navigationBar)])

        let flags = OrderRule().flags(reference: reference, run: run)

        #expect(flags.map(\.key) == ["C"])
        #expect(flags.first?.finding == .moved(referencePosition: 3, runPosition: 1, shared: 3))
        #expect(flags.first?.crops.map(\.side) == [.reference, .run])
    }

    /// The same keys in the same order, one side with an extra card between them: no order flag.
    @Test
    func anExtraCardIsNotAMove() {
        let reference = Self.capture([Self.section("A", y: 100), Self.section("B", y: 210)])
        let run = Self.capture([Self.section("A", y: 100), Self.section("New", y: 210), Self.section("B", y: 320)])

        #expect(OrderRule().flags(reference: reference, run: run).isEmpty)
    }

    /// A card whose runs are the same by shape and whose width or gap changed past the tolerance is a box flag naming each measure; within the tolerance it is not.
    @Test
    func aChangedBoxIsFlaggedPastTheTolerance() {
        let reference = Self.capture([Self.section("A", y: 100), Self.section("B", y: 210)])
        let nudged = Self.capture([Self.section("A", y: 101), Self.section("B", y: 211.5, width: 375.5)])
        let changed = Self.capture([Self.section("A", y: 100), Self.section("B", y: 222, width: 340)])

        let flags = BoxRule().flags(reference: reference, run: changed)

        #expect(BoxRule().flags(reference: reference, run: nudged).isEmpty)
        #expect(flags.map(\.key) == ["B"])
        #expect(flags.first?.finding == .box([
            FormFlag.BoxChange(measure: .gapAbove, reference: 10, run: 22),
            FormFlag.BoxChange(measure: .width, reference: 374, run: 340),
        ]))
    }

    /// G4 by construction: a list one row longer — every row the same shape, so the shape *set* is unchanged — with its figures changed and every card below it pushed down: no flag from any rule.
    @Test
    func aLongerListWithOtherFiguresIsNoFlag() {
        let reference = Self.capture([Self.section("Sessions", y: 100, rows: 3), Self.section("By sport", y: 426)])
        let run = Self.capture([Self.section("Sessions", y: 100, rows: 4, figure: "12.5 km"), Self.section("By sport", y: 526)])

        let flags = BundleDiff.standardRules.flatMap { $0.flags(reference: reference, run: run) }

        #expect(flags.isEmpty)
    }

    /// Edges that text sets are not measured (Brief §2.2): a section with no container keeps no flag however far its words reach, and a card whose line wrapped keeps none for its height — while its width, which the layout sets, still flags.
    @Test
    func extentsTheTextSetsAreNotMeasured() {
        var textOnly = Self.section("A", y: 100)
        textOnly.containerFrame = nil
        var wider = textOnly
        wider.frame.width = 390
        wider.frame.x = 6
        var card = Self.section("B", y: 210, rows: 1)
        var wrapped = card
        wrapped.textRuns[1].frame.height = 40
        wrapped.frame.height += 20
        wrapped.containerFrame?.height += 20
        card.containerFrame?.width = 374
        wrapped.containerFrame?.width = 360

        let flags = BoxRule().flags(reference: Self.capture([textOnly, card]), run: Self.capture([wider, wrapped]))

        #expect(flags.map(\.key) == ["B"])
        #expect(flags.first?.finding == .box([FormFlag.BoxChange(measure: .width, reference: 374, run: 360)]))
    }

    /// A screen the walk reached by a `scrollTo` sits wherever the scroll left it, which follows from the rows above the target: every section shifted down is no flag there, the same shift on an unscrolled screen is, and a gap between neighbours is compared either way.
    @Test
    func aScrolledScreensTopIsNotMeasured() {
        let reference = Self.capture([Self.section("A", y: 100), Self.section("B", y: 210)])
        let shifted = Self.capture([Self.section("A", y: 160), Self.section("B", y: 270)])
        let widened = Self.capture([Self.section("A", y: 160), Self.section("B", y: 290)])
        var scrolledShift = shifted
        scrolledShift.scrolled = true
        var scrolledWidened = widened
        scrolledWidened.scrolled = true
        var scrolledReference = reference
        scrolledReference.scrolled = true

        #expect(BoxRule().flags(reference: reference, run: shifted).first?.finding == .box([FormFlag.BoxChange(measure: .top, reference: 100, run: 160)]))
        #expect(BoxRule().flags(reference: reference, run: scrolledShift).isEmpty)
        #expect(BoxRule().flags(reference: scrolledReference, run: shifted).isEmpty)
        #expect(BoxRule().flags(reference: reference, run: scrolledWidened).map(\.key) == ["B"])
    }

    /// A section on one side only whose body is rows of one template is a list the app may draw only when it has rows; a chart card (an axis row in it), a lone heading and a body of mixed rows are plain presence.
    @Test
    func aPresenceFlagOnAListIsMarkedAndAChartIsNot() {
        var list = Self.section("Working", y: 180)
        list.textRuns += [206.0, 232].flatMap { y in
            [
                ScreenSection.TextRun(shape: "Ride", frame: AXNode.Frame(x: 22, y: y, width: 60, height: 20)),
                ScreenSection.TextRun(shape: "{n} km", frame: AXNode.Frame(x: 300, y: y, width: 60, height: 20)),
            ]
        }
        var mixed = list
        mixed.textRuns[4].frame.x = 22
        let note = Self.section("Working", y: 180)
        var stacked = list
        stacked.textRuns = [list.textRuns[0]] + [206.0, 232, 258].map { ScreenSection.TextRun(shape: "Ride", frame: AXNode.Frame(x: 22, y: $0, width: 60, height: 20)) }
        var brief = stacked
        brief.textRuns.removeLast()
        var chart = Self.section("Power", y: 180)
        let ticks = [22.0, 180, 338].map { ScreenSection.TextRun(shape: "{n}", frame: AXNode.Frame(x: $0, y: 260, width: 24, height: 12)) }
        chart.textRuns += ticks

        func findings(_ section: ScreenSection) -> [FormFlag.Finding] {
            PresenceRule().flags(reference: Self.capture([]), run: Self.capture([section])).map(\.finding)
        }

        #expect(findings(list) == [.onlyInList(.run)])
        #expect(findings(stacked) == [.onlyInList(.run)])
        #expect(findings(brief) == [.onlyIn(.run)])
        #expect(findings(note) == [.onlyIn(.run)])
        #expect(findings(mixed) == [.onlyIn(.run)])
        #expect(findings(chart) == [.onlyIn(.run)])
    }

    /// A bar is pinned, so its top is compared as it stands.
    @Test
    func aMovedBarIsABoxFlag() {
        let reference = Self.capture([Self.bar(.tabBar)])
        var moved = Self.bar(.tabBar)
        moved.frame.y = 760

        let flags = BoxRule().flags(reference: reference, run: Self.capture([moved]))

        #expect(flags.first?.finding == .box([FormFlag.BoxChange(measure: .top, reference: 791, run: 760)]))
    }

    /// A crop is the section's frame clipped to the screenshot, and says so; a section the screenshot does not show at all keeps its frame and is marked.
    @Test
    func aCropIsClippedToTheScreenshotOrMarkedAbsent() {
        let capture = Self.capture([])
        var partly = Self.section("Partly", y: 800)
        partly.placement = .partlyOffScreen
        var below = Self.section("Below", y: 1000)
        below.placement = .offScreen

        let clipped = capture.crop(of: partly, side: .run)
        let absent = capture.crop(of: below, side: .run)

        #expect(clipped.rect == AXNode.Frame(x: 14, y: 800, width: 374, height: 74))
        #expect(clipped.visibility == .clipped)
        #expect(absent.rect == below.frame)
        #expect(absent.visibility == .notInScreenshot)
        #expect(absent.screenshotPath == "screens/s/light/screen.png")
    }

    /// A content section of `rows` rows, each a title and a figure, 100 pt tall per row after a 26 pt heading, drawn as a card: its container is its frame.
    static func section(_ key: String, y: Double, width: Double = 374, rows: Int = 0, figure: String = "5.2 km") -> ScreenSection {
        let heading = ScreenSection.TextRun(shape: TextShape.of(key), frame: AXNode.Frame(x: 22, y: y, width: 120, height: 20))
        let rowRuns = (0 ..< rows).flatMap { row in
            [
                ScreenSection.TextRun(shape: "Ride", frame: AXNode.Frame(x: 22, y: y + 26 + Double(row) * 100, width: 60, height: 20)),
                ScreenSection.TextRun(shape: TextShape.of(figure), frame: AXNode.Frame(x: 300, y: y + 26 + Double(row) * 100, width: 60, height: 20)),
            ]
        }
        let height = rows == 0 ? 100 : 26 + Double(rows) * 100
        let frame = AXNode.Frame(x: 14, y: y, width: width, height: height)
        return ScreenSection(key: key, role: .content, frame: frame, placement: .onScreen, textRuns: [heading] + rowRuns, containerFrame: frame)
    }

    static func bar(_ role: ScreenSection.Role) -> ScreenSection {
        let key = role == .tabBar ? "tab bar" : "navigation bar"
        let y: Double = role == .tabBar ? 791 : 62
        return ScreenSection(key: key, role: role, frame: AXNode.Frame(x: 0, y: y, width: 402, height: role == .tabBar ? 83 : 54), placement: .onScreen, textRuns: [])
    }

    static func capture(_ sections: [ScreenSection]) -> SegmentedCapture {
        SegmentedCapture(screenshotPath: "screens/s/light/screen.png", viewport: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), sections: sections)
    }
}
