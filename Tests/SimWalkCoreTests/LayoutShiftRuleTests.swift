//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The layout-shift rule, replayed over fixture sequences of reads the way `SettleTrackerTests` replays trees (SimWalk#67, M2).
struct LayoutShiftRuleTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    /// A fixed sequence of reads — a banner landing, a still read, a scroll, a row reordered into a cell with a renamed icon — gives the shifts it always gave (SimWalk#96): the rule folds pairwise now, and this pins that folding changed nothing.
    @Test
    func aFixedSequenceOfReadsGivesTheShiftsItAlwaysGave() {
        let loaded = Self.page(rows: Self.rows(from: 100))
        let bannered = Self.page(rows: [Self.banner] + Self.rows(from: 168))
        let scrolled = Self.page(rows: [Self.banner] + Self.rows(from: 148))
        let lengthened = Self.page(rows: [Self.banner] + Self.rows(from: 148, numbered: 1 ... 4))
        let reads = [Self.read(0.1, loaded), Self.read(0.2, bannered), Self.read(0.3, bannered), Self.read(0.45, scrolled), Self.read(0.6, lengthened), Self.read(0.7, loaded)]
            + [Self.read(0.8, Self.unscrolled(Self.rows(from: 100))), Self.read(0.9, Self.unscrolled([Self.banner] + Self.rows(from: 168))), Self.read(1.0, Self.unscrolled(Self.rows(from: 100)))]

        let summary = LayoutShiftRule.shifts(in: reads, afterScroll: false).map { shift in
            "\(shift.element.label ?? "-")@\(shift.movedAtMilliseconds) \(Int(shift.before.y))->\(Int(shift.after.y)) \(shift.cause.map { "\($0.change) \($0.element.label ?? $0.element.type)" } ?? "none")"
        }

        #expect(summary == [
            "Row 1@200 100->168 inserted New: offline mode", "Row 2@200 156->224 inserted New: offline mode", "Row 3@200 212->280 inserted New: offline mode",
            "Row 1@900 100->168 inserted New: offline mode", "Row 2@900 156->224 inserted New: offline mode", "Row 3@900 212->280 inserted New: offline mode",
            "Row 1@1000 168->100 removed New: offline mode", "Row 2@1000 224->156 removed New: offline mode", "Row 3@1000 280->212 removed New: offline mode",
        ])
    }

    /// A watch of many reads holds at most the previous one beside the one being compared, never every tree it saw (SimWalk#96).
    @Test
    func aWatchKeepsOnlyThePreviousReadWhateverItsLength() {
        var fold = LayoutShiftRule.Fold(afterScroll: false)
        var most = 0

        for step in 0 ..< 50 {
            fold.add(Self.read(Double(step) * 0.1, Self.page(rows: Self.rows(from: 100 + Double(step % 2) * 68))))
            most = max(most, fold.retainedReads + 1)
        }

        #expect(most <= 2)
        #expect(fold.gaps.count == 49)
    }

    /// A banner inserted above a list pushes the rows down: each row is reported, with the banner named as the insertion that moved it, and the banner itself is not a shift.
    @Test
    func aBannerInsertedAboveAListReportsTheRowsItPushedNamingTheInsertion() {
        let loaded = Self.page(rows: Self.rows(from: 100))
        let bannered = Self.page(rows: [Self.banner] + Self.rows(from: 168))

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, loaded), Self.read(1.2, bannered)], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["Row 1", "Row 2", "Row 3"])
        #expect(shifts.first?.element == CaptureManifest.Motion.Element(type: "StaticText", identifier: nil, label: "Row 1", path: [0, 0, 1]))
        #expect(shifts.first?.before == AXNode.Frame(x: 16, y: 100, width: 370, height: 44))
        #expect(shifts.first?.after == AXNode.Frame(x: 16, y: 168, width: 370, height: 44))
        #expect(shifts.allSatisfy { $0.movedAtMilliseconds == 1200 })
        #expect(shifts.allSatisfy {
            $0.cause == CaptureManifest.Motion.Cause(change: .inserted, element: CaptureManifest.Motion.Element(type: "StaticText", identifier: "banner", label: "New: offline mode", path: [0, 0, 0]))
        })
    }

    /// Every element of a scroll container moving by the same offset, with nothing displacing it, is a scroll: no shift.
    @Test
    func aUniformMoveOfAScrollContainersContentIsNoShift() {
        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, Self.page(rows: Self.rows(from: 100))), Self.read(0.2, Self.page(rows: Self.rows(from: 20)))], afterScroll: false)

        #expect(shifts.isEmpty)
    }

    /// A lazy list dropping the row it scrolled past is the scroll's motion, not a removal pulling the rest up: after a `scrollTo`, and when the app scrolled by itself, since the row's extent is not the distance scrolled.
    @Test
    func aScrollIsNoShiftThoughALazyListDropsARow() {
        let reads = [Self.read(0.1, Self.page(rows: Self.rows(from: 100))), Self.read(0.2, Self.page(rows: Array(Self.rows(from: 56).dropFirst())))]

        #expect(LayoutShiftRule.shifts(in: reads, afterScroll: true).isEmpty)
        #expect(LayoutShiftRule.shifts(in: reads, afterScroll: false).isEmpty)
    }

    /// An app scrolling its own lazy list — a chat jumping to its latest message — drops rows at one edge and builds them at the other: every row it kept moved by one offset no change in the list accounts for, so it is a scroll and no shift.
    @Test
    func anAppsOwnScrollOfALazyListIsNoShift() {
        let before = Self.page(rows: Self.rows(from: 100, numbered: 1 ... 6))
        let after = Self.page(rows: Self.rows(from: 26, numbered: 2 ... 8))

        #expect(LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false).isEmpty)
    }

    /// A banner inserted in a scroll container below a title that stays put pushes the rows under it, not the title: the content did not move as one, so it is no scroll and the rows are reported.
    @Test
    func aBannerInsertedBelowAStillTitleInAScrollContainerIsReported() {
        let title = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 40, width: 370, height: 40), label: "Inbox")

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, Self.page(rows: [title] + Self.rows(from: 100))), Self.read(0.2, Self.page(rows: [title, Self.banner] + Self.rows(from: 168)))], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["Row 1", "Row 2", "Row 3"])
        #expect(shifts.allSatisfy { $0.cause?.element.identifier == "banner" })
    }

    /// A loading text replaced by a taller header pushes the rows down — the typical loading-to-loaded shift.
    ///
    /// The screen's first label changed, so nothing under the window holds the old one; the window, the only anonymous one of its type, is still paired, and the rows are reported with the header as the cause, in a scroll container too, where the header's extent less the loading text's is the distance the rows moved.
    @Test
    func aLoadingTextReplacedByATallerHeaderReportsTheRowsItPushed() {
        let loading = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 20), label: "Loading")
        let header = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 60), label: "Welcome, Alice")

        let screens: [([AXNode]) -> AXNode] = [Self.unscrolled, { Self.page(rows: $0) }]

        for screen in screens {
            let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, screen([loading] + Self.rows(from: 132))), Self.read(0.2, screen([header] + Self.rows(from: 172)))], afterScroll: false)

            #expect(shifts.map(\.element.label) == ["Row 1", "Row 2", "Row 3"])
            #expect(shifts.allSatisfy { $0.cause?.change == .inserted && $0.cause?.element.label == "Welcome, Alice" })
        }
    }

    /// A label pinned in a scroll container that changes in place while the rows scroll under it, in one step of the app's own scroll: the two boxes are the same size, so nothing replaced one with a taller one, and the rows scrolled.
    @Test
    func aLabelChangingInPlaceDuringTheAppsOwnScrollIsNoShift() {
        func today(_ label: String) -> AXNode {
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 30), label: label)
        }
        let before = Self.page(rows: [today("Today")] + Self.rows(from: 140))
        let after = Self.page(rows: [today("Yesterday")] + Self.rows(from: 130))

        #expect(LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false).isEmpty)
    }

    /// An app scrolling its own lazy list by one row's height (not its pitch) while the list builds a row at the bottom is a scroll, not a shift caused by that row.
    @Test
    func aScrollByARowsHeightWhileALazyListBuildsARowIsNoShift() {
        let before = Self.page(rows: Self.rows(from: 100, numbered: 1 ... 3))
        let after = Self.page(rows: Self.rows(from: 56, numbered: 1 ... 4))

        #expect(LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false).isEmpty)
    }

    /// A banner under a title that stays put in a scroll container, with a different gap above it than the first row had: the rows moved by the banner's height, which is its box plus the gap before it, not the gap after it, and it is reported.
    @Test
    func aBannerWhoseGapAboveDiffersFromTheFirstRowsIsReportedInAScrollContainer() {
        let title = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 30), label: "Inbox")
        let before = Self.page(rows: [title] + Self.rows(from: 150))
        let banner = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 130, width: 370, height: 60), label: "New: offline mode", identifier: "banner")
        let after = Self.page(rows: [title, banner] + Self.rows(from: 210))

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["Row 1", "Row 2", "Row 3"])
        #expect(shifts.allSatisfy { $0.cause?.element.identifier == "banner" })
    }

    /// Anonymous rows that all begin with one icon are told apart by the names they hold after it, so a banner pushing them reports each row's icon and text.
    ///
    /// A row whose own text changed is left out, never paired with another row.
    @Test
    func rowsBeginningWithOneIconAreToldApartByTheirOtherNames() {
        func item(_ name: String, at top: Double) -> AXNode {
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: top, width: 402, height: 44), children: [
                AXNode(type: "Image", frame: AXNode.Frame(x: 16, y: top + 10, width: 24, height: 24), label: "circle"),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 52, y: top + 10, width: 300, height: 24), label: name),
            ])
        }
        let before = Self.unscrolled([item("Milk", at: 100), item("Eggs", at: 156)])

        let pushed = LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, Self.unscrolled([Self.banner, item("Milk", at: 172), item("Eggs", at: 228)]))], afterScroll: false)
        let renamed = LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, Self.unscrolled([Self.banner, item("Milk ×2", at: 172), item("Eggs", at: 228)]))], afterScroll: false)

        #expect(pushed.map(\.element.label) == ["circle", "Milk", "circle", "Eggs"])
        #expect(pushed.allSatisfy { $0.cause?.element.identifier == "banner" })
        #expect(renamed.map(\.element.label) == ["circle", "Eggs"])
        #expect(renamed.allSatisfy { $0.before.y == 166 })
    }

    /// A row whose first name changes — its icon becoming a checkmark — and grows is a resize of that row, not a removal and an insertion; the cause names the resize, and an anonymous cause is named by its nearest named ancestor (SimWalk#96).
    @Test
    func aRowWhoseIconBecomesACheckmarkIsAResizeNamedByItsAncestor() {
        func item(_ icon: String, _ name: String, at top: Double, height: Double = 44) -> AXNode {
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: top, width: 402, height: height), children: [
                AXNode(type: "Image", frame: AXNode.Frame(x: 16, y: top + 10, width: 24, height: 24), label: icon),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 52, y: top + 10, width: 300, height: 24), label: name),
            ])
        }
        func list(_ rows: [AXNode]) -> AXNode {
            Self.unscrolled([AXNode(type: "Other", frame: Self.screen, label: "Groceries", children: rows)])
        }
        let before = list([item("circle", "Milk", at: 100), item("circle", "Eggs", at: 156)])
        let after = list([item("checkmark", "Milk", at: 100, height: 60), item("circle", "Eggs", at: 172)])

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["circle", "Eggs"])
        #expect(shifts.allSatisfy { $0.cause?.change == .resized })
        #expect(shifts.allSatisfy { $0.cause?.element == CaptureManifest.Motion.Element(type: "Cell", identifier: nil, label: nil, path: [0, 0, 0], within: "Groceries") })
    }

    /// An anonymous cell inserted above the rows is named, as the cause, by the nearest named element holding it.
    @Test
    func anAnonymousInsertedCellIsNamedByItsNearestNamedAncestor() {
        let before = Self.unscrolled([AXNode(type: "Other", frame: Self.screen, label: "Inbox", children: [Self.cell("Ada", at: 100, height: 60)])])
        let after = Self.unscrolled([AXNode(type: "Other", frame: Self.screen, label: "Inbox", children: [Self.cell("Grace", at: 100, height: 60), Self.cell("Ada", at: 160, height: 60)])])

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false)

        #expect(shifts.isEmpty == false)
        #expect(shifts.allSatisfy { $0.cause?.change == .inserted && $0.cause?.element.type == "Cell" && $0.cause?.element.label == nil && $0.cause?.element.within == "Inbox" })
    }

    /// The app's own name is no help in placing an element: an anonymous cell whose only named ancestor is the Application root has no `within`.
    @Test
    func anAnonymousCellUnderOnlyTheNamedApplicationRootHasNoWithin() throws {
        let before = Self.unscrolled([Self.cell("Ada", at: 100, height: 60)])
        let after = Self.unscrolled([Self.cell("Grace", at: 100, height: 60), Self.cell("Ada", at: 160, height: 60)])

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false)

        let cause = try #require(shifts.first?.cause)

        #expect(cause.element.type == "Cell")
        #expect(cause.element.label == nil)
        #expect(cause.element.within == nil)
    }

    /// An app scrolling its own list under a section header pinned in place: the header did not move, every row that did moved by one offset, so it is a scroll and no shift.
    @Test
    func anAppsOwnScrollUnderAPinnedSectionHeaderIsNoShift() {
        let header = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 100, width: 402, height: 30), label: "Today")
        let before = Self.page(rows: [header] + Self.rows(from: 140, numbered: 1 ... 6))
        let after = Self.page(rows: [header] + Self.rows(from: 122, numbered: 2 ... 8))

        #expect(LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false).isEmpty)
    }

    /// An element moving with a reported ancestor is that ancestor's shift: a card pushed down by a banner is reported, the button inside it is not reported again.
    @Test
    func aDescendantMovingWithAReportedAncestorIsFoldedIntoIt() {
        func card(at top: Double) -> AXNode {
            AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: top, width: 370, height: 100), label: "Alice card", children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 326, y: top + 10, width: 44, height: 30), label: "More"),
            ])
        }

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, Self.unscrolled([card(at: 100)])), Self.read(0.2, Self.unscrolled([Self.banner, card(at: 172)]))], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["Alice card"])
    }

    /// A change in another column does not displace an element: a banner inserted above the left column is the cause of the left row's move, not of a right-hand element that moved down past it.
    @Test
    func aChangeInAnotherColumnIsNoCause() {
        let banner = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 170, height: 60), identifier: "banner")
        func row(at top: Double) -> AXNode {
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: top, width: 170, height: 44), label: "Row")
        }
        func clock(at top: Double) -> AXNode {
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 216, y: top, width: 170, height: 44), label: "Clock")
        }

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, Self.unscrolled([row(at: 100), clock(at: 100)])), Self.read(0.2, Self.unscrolled([banner, row(at: 168), clock(at: 180)]))], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["Row"])
    }

    /// A cell inserted at the top of a table of anonymous cells moves the cells below it by its height: each row's `More` button is matched with its own row's, so it is reported moving by that height, never paired with another row's button.
    @Test
    func aButtonInAnAnonymousCellIsMatchedWithinItsOwnCell() {
        let before = Self.table([Self.cell("Alice", at: 100, height: 100), Self.cell("Bob", at: 200, height: 100)])
        let after = Self.table([Self.cell("Carol", at: 100, height: 60), Self.cell("Alice", at: 160, height: 100), Self.cell("Bob", at: 260, height: 100)])

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, before), Self.read(0.2, after)], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["Alice", "More", "Bob", "More"])
        #expect(shifts.allSatisfy { $0.after.y - $0.before.y == 60 && $0.cause?.change == .inserted })
    }

    /// A move under 1 pt is jitter, ignored even with an insertion above it.
    @Test
    func aSubPointMoveIsIgnored() {
        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, Self.page(rows: Self.rows(from: 100))), Self.read(0.2, Self.page(rows: [Self.sliver] + Self.rows(from: 100.6)))], afterScroll: false)

        #expect(shifts.isEmpty)
    }

    /// A text growing to two lines pushes its sibling below: the sibling is reported, the resize named as the cause.
    @Test
    func aResizePushingASiblingIsReportedAgainstTheSibling() {
        let short = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 20), label: "Summary")
        var tall = short
        tall.frame.height = 40
        let below = AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 130, width: 370, height: 44), label: "Continue")
        var pushed = below
        pushed.frame.y = 150

        let shifts = LayoutShiftRule.shifts(in: [Self.read(0.1, Self.page(rows: [short, below])), Self.read(0.2, Self.page(rows: [tall, pushed]))], afterScroll: false)

        #expect(shifts.map(\.element.label) == ["Continue"])
        #expect(shifts.first?.cause?.change == .resized)
        #expect(shifts.first?.cause?.element.label == "Summary")
    }

    /// An element that only appears or disappears is not a shift, and neither is a sheet arriving over the screen: it covers what it lands on rather than displacing it.
    @Test
    func anAppearanceOrASheetOverTheScreenIsNoShift() {
        let plain = Self.page(rows: Self.rows(from: 100))
        let toast = Self.page(rows: Self.rows(from: 100) + [AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 700, width: 370, height: 44), label: "Saved")])
        var sheeted = plain
        sheeted.children.append(AXNode(type: "Sheet", frame: AXNode.Frame(x: 0, y: 60, width: 402, height: 814), label: "Allow access", children: [
            AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 120, width: 370, height: 44), label: "Allow"),
        ]))

        #expect(LayoutShiftRule.shifts(in: [Self.read(0.1, plain), Self.read(0.2, toast), Self.read(0.3, plain)], afterScroll: false).isEmpty)
        #expect(LayoutShiftRule.shifts(in: [Self.read(0.1, plain), Self.read(0.2, sheeted)], afterScroll: false).isEmpty)
    }
}

private extension LayoutShiftRuleTests {
    static let banner = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 60), label: "New: offline mode", identifier: "banner")
    static let sliver = AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 99, width: 370, height: 0.6), identifier: "hairline")

    static func read(_ elapsed: TimeInterval, _ tree: AXNode) -> LayoutShiftRule.Read {
        LayoutShiftRule.Read(elapsed: elapsed, tree: tree)
    }

    /// Rows 44 pt tall and 12 apart, labelled by `numbers`, the first at `top`.
    static func rows(from top: Double, numbered numbers: ClosedRange<Int> = 1 ... 3) -> [AXNode] {
        numbers.map { AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: top + Double($0 - numbers.lowerBound) * 56, width: 370, height: 44), label: "Row \($0)") }
    }

    /// A screen of `children` with no scroll container.
    static func unscrolled(_ children: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: screen, label: "Fixture", children: [AXNode(type: "Window", frame: screen, children: children)])
    }

    /// An anonymous table cell holding a name and a `More` button, `height` tall at `top`.
    static func cell(_ name: String, at top: Double, height: Double) -> AXNode {
        AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: top, width: 402, height: height), children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: top + 8, width: 200, height: 30), label: name),
            AXNode(type: "Button", frame: AXNode.Frame(x: 342, y: top + 8, width: 44, height: 30), label: "More"),
        ])
    }

    static func table(_ cells: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: screen, label: "Fixture", children: [
            AXNode(type: "Window", frame: screen, children: [AXNode(type: "Table", frame: screen, children: cells)]),
        ])
    }

    static func page(rows: [AXNode]) -> AXNode {
        AXNode(type: "Application", frame: screen, label: "Fixture", children: [
            AXNode(type: "Window", frame: screen, children: [AXNode(type: "ScrollView", frame: screen, children: rows)]),
        ])
    }
}
