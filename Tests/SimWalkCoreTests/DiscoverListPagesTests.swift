//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Pages of one list join on a row both show once, so the rows below the fold read in content order and a moved list is told from one that did not move.
struct DiscoverListPagesTests {
    private static let listFrame = AXNode.Frame(x: 0, y: 0, width: 400, height: 800)

    private static func frame(_ y: Double) -> AXNode.Frame {
        AXNode.Frame(x: 0, y: y, width: 400, height: 50)
    }

    /// A disclosure row: a labelled cell with a trailing glyph.
    private static func row(_ label: String, at y: Double) -> AXNode {
        let glyph = AXNode(type: "Image", frame: AXNode.Frame(x: 380, y: y + 15, width: 10, height: 20))
        return AXNode(type: "Cell", frame: frame(y), label: label, children: [glyph])
    }

    private static func page(_ rows: [(String, Double)]) -> AXNode {
        let list = AXNode(type: "Table", frame: listFrame, children: rows.map { row($0.0, at: $0.1) })
        return AXNode(type: "Application", frame: listFrame, children: [list])
    }

    private static func pages(_ first: [(String, Double)]) -> DiscoverListPages {
        let tree = page(first)
        return DiscoverListPages(first: tree, container: tree.children[0], screenID: "hub")
    }

    /// A page whose table holds `rows` and also `extra`, nodes such as a pinned header or a switch's cell.
    private static func page(_ rows: [(String, Double)], extra: [AXNode]) -> AXNode {
        let list = AXNode(type: "Table", frame: listFrame, children: extra + rows.map { row($0.0, at: $0.1) })
        return AXNode(type: "Application", frame: listFrame, children: [list])
    }

    /// A page with a navigation bar's `Add` button and a `Profile` disclosure row above the table, neither of which scrolls.
    private static func pageWithFixedChrome(_ rows: [(String, Double)]) -> AXNode {
        let add = AXNode(type: "Button", frame: AXNode.Frame(x: 330, y: 0, width: 60, height: 44), label: "Add")
        let bar = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 44), children: [add])
        let list = AXNode(type: "Table", frame: listFrame, children: rows.map { row($0.0, at: $0.1) })
        return AXNode(type: "Application", frame: listFrame, children: [bar, row("Profile", at: 50), list])
    }

    /// A cell that is no disclosure row, holding a switch: the switch is a control the classifier skips.
    private static func switchCell(_ label: String, at y: Double) -> AXNode {
        let toggle = AXNode(type: "Switch", frame: AXNode.Frame(x: 330, y: y + 10, width: 50, height: 30), label: label)
        return AXNode(type: "Cell", frame: frame(y), label: label, children: [toggle])
    }

    @Test
    func twoOverlappingPagesJoinOnTheirSharedAnchorAndLaterRowsFollowTheFirstPages() {
        var pages = Self.pages([("A", 0), ("B", 400), ("C", 750)])
        let next = Self.page([("B", 100), ("C", 450), ("D", 750)])

        #expect(DiscoverListPages.shift(from: Self.page([("A", 0), ("B", 400), ("C", 750)]), to: next, container: Self.page([]).children[0]) == 300)
        #expect(pages.add(next) == .moved)

        let read = pages.read()
        #expect(read.rows.map(\.label) == ["A", "B", "C", "D"])
        #expect(read.rows.map(\.node.frame.y) == [0, 400, 750, 1050])
        #expect(read.rows.map(\.isOnScreen) == [true, true, true, false])
        #expect(read.skipped.isEmpty)
    }

    @Test
    func aDragThatMovedNothingEndsTheListAndKeepsNoPage() {
        var pages = Self.pages([("A", 0), ("B", 400)])

        #expect(pages.add(Self.page([("A", 0), ("B", 400.5)])) == .end)
        #expect(pages.read().rows.map(\.label) == ["A", "B"])
    }

    @Test
    func aDragThatAddedARowWhileKeepingTheOthersInPlaceChangedTheListInPlace() {
        var pages = Self.pages([("A", 0), ("B", 400)])

        #expect(pages.add(Self.page([("A", 0), ("B", 400), ("C", 750)])) == .changedInPlace)
    }

    @Test
    func pagesWithNoAnchorInCommonAreUnjoined() {
        var pages = Self.pages([("A", 0), ("B", 400)])

        #expect(pages.add(Self.page([("X", 0), ("Y", 400)])) == .unjoined)
    }

    @Test
    func aRowWhoseTextRepeatsOnOnePageIsNoAnchor() {
        var pages = Self.pages([("A", 0), ("Same", 400), ("Same", 450)])

        #expect(pages.add(Self.page([("Same", 100), ("Same", 150), ("Z", 700)])) == .unjoined)
    }

    @Test
    func aPageWithoutTheContainerIsGone() {
        var pages = Self.pages([("A", 0)])
        let other = AXNode(type: "Table", frame: AXNode.Frame(x: 0, y: 0, width: 400, height: 700), children: [Self.row("A", at: 0)])

        #expect(pages.add(AXNode(type: "Application", frame: Self.listFrame, children: [other])) == .containerGone)
    }

    @Test
    func aRowSeenOnTwoPagesAtTheSameContentPositionIsTakenOnce() {
        var pages = Self.pages([("A", 0), ("B", 400), ("C", 750)])

        #expect(pages.add(Self.page([("B", 100), ("C", 450), ("D", 750)])) == .moved)

        let read = pages.read()
        #expect(read.rows.map(\.label) == ["A", "B", "C", "D"])
        #expect(read.rows.map(\.node.frame.y) == [0, 400, 750, 1050])
        #expect(read.skipped.isEmpty)
    }

    @Test
    func oneLabelAtTwoContentPositionsIsSkippedAtBothAndIsInNeitherRows() {
        var pages = Self.pages([("A", 0), ("Dup", 400), ("C", 750)])

        #expect(pages.add(Self.page([("C", 450), ("Dup", 750)])) == .moved)

        let read = pages.read()
        #expect(read.rows.map(\.label) == ["A", "C"])
        let skipped = read.skipped.filter { $0.reason == .labelNotUnique }
        #expect(skipped.map(\.name) == ["Dup", "Dup"])
        #expect(skipped.map(\.frame.y) == [400, 1050])
    }

    @Test
    func theContinuingListIsTheFirstQualifyingContainerInTreeOrder() {
        let short = AXNode(type: "Table", frame: Self.listFrame, children: [Self.row("A", at: 0)])
        let long = AXNode(type: "ScrollView", frame: Self.listFrame, children: [Self.row("B", at: 760)])
        let second = AXNode(type: "CollectionView", frame: Self.listFrame, children: [Self.row("C", at: 780)])
        let tree = AXNode(type: "Application", frame: Self.listFrame, children: [short, long, second])

        #expect(DiscoverClassifier.continuingList(tree) == long)
        #expect(DiscoverClassifier.continuingList(AXNode(type: "Application", frame: Self.listFrame, children: [short])) == nil)
    }

    @Test
    func whatLiesOutsideTheListIsReadFromTheFirstPageAlone() {
        let first = Self.pageWithFixedChrome([("A", 100), ("B", 400), ("C", 750)])
        var pages = DiscoverListPages(first: first, container: first.children[2], screenID: "hub")

        #expect(pages.add(Self.pageWithFixedChrome([("B", 100), ("C", 450), ("D", 750)])) == .moved)
        #expect(pages.add(Self.pageWithFixedChrome([("C", 150), ("D", 450), ("E", 750)])) == .moved)

        let read = pages.read()
        #expect(read.rows.map(\.label) == ["Profile", "A", "B", "C", "D", "E"])
        let profile = read.rows.filter { $0.label == "Profile" }
        #expect(profile.map(\.node.frame.y) == [50])
        #expect(profile.map(\.isOnScreen) == [true])
        let add = read.skipped.filter { $0.name == "Add" }
        #expect(add.map(\.frame.y) == [0])
        #expect(!read.skipped.contains { $0.reason == .labelNotUnique })
    }

    @Test
    func anAnchorThatNeverMovesSaysNothingAboutTheShift() {
        let header = AXNode(type: "Cell", frame: Self.frame(0), label: "Header")
        let first = Self.page([("A", 100), ("B", 400), ("C", 750)], extra: [header])
        var pages = DiscoverListPages(first: first, container: first.children[0], screenID: "hub")

        #expect(pages.add(Self.page([("B", 100), ("C", 450), ("D", 750)], extra: [header])) == .moved)
        #expect(pages.read().rows.filter { $0.label == "D" }.map(\.node.frame.y) == [1050])

        var still = DiscoverListPages(first: first, container: first.children[0], screenID: "hub")
        #expect(still.add(Self.page([("A", 100.5), ("B", 400), ("C", 750)], extra: [header])) == .end)
    }

    @Test
    func theShiftIsTheOneMostMovedAnchorsAgreeOn() {
        let before = Self.page([("A", 0), ("B", 200), ("C", 400), ("E", 600)])
        let after = Self.page([("B", 0), ("C", 100), ("E", 300)])

        #expect(DiscoverListPages.shift(from: before, to: after, container: Self.page([]).children[0]) == 300)
    }

    @Test
    func aLabelNotUniqueOnALaterPageLeavesTheFirstPagesRowUntapped() {
        var pages = Self.pages([("A", 100), ("X", 400), ("C", 750)])

        #expect(pages.add(Self.page([("X", 100), ("C", 450), ("X", 600), ("D", 750)])) == .moved)

        let read = pages.read()
        #expect(!read.rows.contains { $0.label == "X" })
        let skipped = read.skipped.filter { $0.reason == .labelNotUnique }
        #expect(skipped.allSatisfy { $0.name == "X" })
        #expect(skipped.map(\.frame.y).sorted() == [400, 900])
    }

    @Test
    func aLabelNotUniqueOnTheFirstPageLeavesALaterPagesRowUntapped() {
        var pages = Self.pages([("A", 100), ("X", 300), ("X", 500), ("C", 750)])

        #expect(pages.add(Self.page([("C", 450), ("D", 600), ("X", 700)])) == .moved)

        let read = pages.read()
        #expect(!read.rows.contains { $0.label == "X" })
        let skipped = read.skipped.filter { $0.reason == .labelNotUnique }
        #expect(skipped.allSatisfy { $0.name == "X" })
        #expect(skipped.map(\.frame.y).sorted() == [300, 500, 1000])
    }

    @Test
    func aControlSeenOnTwoPagesAtTheSameContentPositionIsSkippedOnce() {
        let first = Self.page([("A", 100), ("C", 750)], extra: [Self.switchCell("Wi-Fi", at: 400)])
        var pages = DiscoverListPages(first: first, container: first.children[0], screenID: "hub")

        #expect(pages.add(Self.page([("C", 450), ("D", 750)], extra: [Self.switchCell("Wi-Fi", at: 100)])) == .moved)

        let switches = pages.read().skipped.filter { $0.type == "Switch" }
        #expect(switches.map(\.frame.y) == [410])
    }

    @Test
    func pagesThatShareOnlyAPinnedHeaderWhileTheOtherRowsChangedCannotBeJoined() {
        func plain(_ rows: [(String, Double)]) -> AXNode {
            let children = rows.map { AXNode(type: "Other", frame: Self.frame($0.1), label: $0.0) }
            let list = AXNode(type: "Table", frame: Self.listFrame, children: children)
            return AXNode(type: "Application", frame: Self.listFrame, children: [list])
        }
        let first = plain([("Header", 0), ("A", 100), ("B", 200)])
        var pages = DiscoverListPages(first: first, container: first.children[0], screenID: "hub")

        #expect(DiscoverListPages.shift(from: first, to: plain([("Header", 0), ("C", 150), ("D", 250)]), container: first.children[0]) == nil)
        #expect(pages.add(plain([("Header", 0), ("C", 150), ("D", 250)])) == .unjoined)
        #expect(!DiscoverListPages.stayedPut(from: first, to: plain([("Header", 0), ("C", 150), ("D", 250)]), container: first.children[0]))
    }

    @Test
    func contentScrolledUnderAPinnedHeaderOverUnlabelledRowsHasNotStayedPut() {
        func plain(_ rows: [(String, Double)]) -> AXNode {
            let children = rows.map { AXNode(type: "Other", frame: Self.frame($0.1), label: $0.0) }
            let list = AXNode(type: "Table", frame: Self.listFrame, children: children)
            return AXNode(type: "Application", frame: Self.listFrame, children: [list])
        }
        let first = plain([("Today", 0), ("Photo", 100), ("Photo", 200), ("Photo", 300)])
        let scrolled = plain([("Today", 0), ("Photo", 50), ("Photo", 150), ("Photo", 250)])
        var pages = DiscoverListPages(first: first, container: first.children[0], screenID: "hub")

        #expect(!DiscoverListPages.stayedPut(from: first, to: scrolled, container: first.children[0]))
        #expect(pages.add(scrolled) == .unjoined)
    }

    /// Within a point is strictly under one for rows and anchors alike, so a list whose rows sit exactly a point lower has not stayed put (SimWalk#210).
    @Test
    func aListWhoseRowsAndAnchorsSitExactlyAPointLowerHasNotStayedPut() {
        let first = Self.plainList([("A", 0), ("B", 100), ("C", 200)])
        let lower = Self.plainList([("A", 1), ("B", 101), ("C", 201)])
        let under = Self.plainList([("A", 0.5), ("B", 100.5), ("C", 200.5)])

        #expect(!DiscoverListPages.stayedPut(from: first, to: lower, container: first.children[0]))
        #expect(DiscoverListPages.stayedPut(from: first, to: under, container: first.children[0]))
    }

    @Test
    func aRowAppendedAfterADragThatMovedNothingIsAListThatChangedInPlace() {
        let first = Self.plainList([("A", 0), ("B", 100), ("C", 200)])
        let grown = Self.plainList([("A", 0), ("B", 100), ("C", 200), ("More", 300)])
        var pages = DiscoverListPages(first: first, container: first.children[0], screenID: "hub")

        #expect(DiscoverListPages.stayedPut(from: first, to: grown, container: first.children[0]))
        #expect(pages.add(grown) == .changedInPlace)
    }

    @Test
    func aLastRowThatGrewInHeightAtTheSameYIsAListThatChangedInPlace() {
        let first = Self.plainList([("A", 0), ("B", 100), ("C", 200)])
        let rows = [("A", 0.0, 44.0), ("B", 100.0, 44.0), ("C", 200.0, 120.0)]
        let children = rows.map { AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: $0.1, width: 402, height: $0.2), label: $0.0) }
        let list = AXNode(type: "Table", frame: Self.listFrame, children: children)
        let grown = AXNode(type: "Application", frame: Self.listFrame, children: [list])
        var pages = DiscoverListPages(first: first, container: first.children[0], screenID: "hub")

        #expect(pages.add(grown) == .changedInPlace)
    }

    private static func plainList(_ rows: [(String, Double)]) -> AXNode {
        let children = rows.map { AXNode(type: "Other", frame: Self.frame($0.1), label: $0.0) }
        let list = AXNode(type: "Table", frame: Self.listFrame, children: children)
        return AXNode(type: "Application", frame: Self.listFrame, children: [list])
    }

    @Test
    func theShiftOfTwoMovedAnchorsThatDisagreeIsTheOneFirstInTheNewPagesVisualOrder() {
        let before = Self.page([("A", 150), ("B", 200)])
        // In tree order A comes first; in visual order B does.
        let after = Self.page([("A", 100), ("B", 0)])

        #expect(DiscoverListPages.shift(from: before, to: after, container: Self.page([]).children[0]) == 200)
    }
}
