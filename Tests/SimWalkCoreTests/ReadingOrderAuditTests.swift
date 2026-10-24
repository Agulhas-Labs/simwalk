//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import Testing

/// `readingOrder`: the tree's order against the visual one, over leaves with text and controls.
struct ReadingOrderAuditTests {
    private static func text(_ label: String, _ x: Double, _ y: Double, width: Double = 100, height: Double = 20) -> AXNode {
        AXNode(type: "StaticText", frame: AXNode.Frame(x: x, y: y, width: width, height: height), label: label)
    }

    private static func evaluate(_ children: [AXNode], slug: String = "light") -> LabelRuleResult {
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: children)
        return ReadingOrderAudit().evaluate(screen, screenID: "you", stateSlug: slug)
    }

    @Test
    func aLowerElementReadBeforeAnUpperOneFiresOnce() {
        let result = Self.evaluate([Self.text("Total", 20, 300), Self.text("Title", 20, 100), Self.text("Footer", 20, 500)])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.label == "Total")
        #expect(result.findings.first?.note == "read before StaticText 'Title', which sits above it")
        #expect(result.examined == 3)
    }

    @Test
    func aTrailingElementReadBeforeALeadingOneOnTheSameRowFires() {
        let result = Self.evaluate([Self.text("Value", 250, 100), Self.text("Name", 20, 102)])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note?.hasSuffix("which sits to its left") == true)
    }

    @Test
    func topToBottomAndLeadingToTrailingIsClean() {
        let result = Self.evaluate([
            Self.text("Name", 20, 100), Self.text("Value", 250, 102),
            Self.text("Body", 20, 200),
        ])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 3)
    }

    @Test
    func aStepUpAndAcrossIsAColumnBreakNotAnInversion() {
        let result = Self.evaluate([Self.text("Left column, low", 20, 500, width: 150), Self.text("Right column, high", 220, 100, width: 150)])

        #expect(result.findings.isEmpty)
    }

    @Test
    func anOverlappingFloatingButtonIsNotOrdered() {
        let fab = AXNode(type: "Button", frame: AXNode.Frame(x: 300, y: 700, width: 60, height: 60), label: "Add")
        let content = Self.text("Last row", 20, 700, width: 380, height: 60)

        let result = Self.evaluate([Self.text("First row", 20, 100), fab, Self.text("Middle", 20, 300), content])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 2)
    }

    @Test
    func aControlIsOneElementWhateverItContains() {
        let button = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 300, width: 200, height: 44), label: "Row", children: [
            Self.text("Row", 30, 320),
            Self.text("Detail", 30, 305),
        ])

        let result = Self.evaluate([Self.text("Title", 20, 100), button])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 2)
    }

    @Test
    func aLabelledContainerThatSpeaksForItsTextIsOneStop() {
        // SimWalk#105: a combined element, "Step 3 of 4, RouteFixture", holding "RouteFixture" left of "3" in tree order.
        let step = AXNode(type: "Other", frame: AXNode.Frame(x: 20, y: 180, width: 360, height: 40), label: "Step 3 of 4, RouteFixture", children: [
            Self.text("RouteFixture", 120, 186),
            Self.text("3", 20, 186, width: 20),
        ])

        let result = Self.evaluate([Self.text("Title", 20, 100), step, Self.text("Body", 20, 300)])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 3)
    }

    @Test
    func aLabelledContainerWhoseLabelLacksAChildsTextIsStillCollectedChildByChild() {
        let step = AXNode(type: "Other", frame: AXNode.Frame(x: 20, y: 180, width: 360, height: 40), label: "Step 3 of 4", children: [
            Self.text("RouteFixture", 120, 186),
            Self.text("3", 20, 186, width: 20),
        ])

        let result = Self.evaluate([step])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note?.hasSuffix("which sits to its left") == true)
    }

    @Test
    func aLabelledContainerHoldingAnEnabledControlIsDescended() {
        let button = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 260, width: 80, height: 44), label: "Edit")
        let row = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 180, width: 400, height: 150), label: "Step 3 of 4, RouteFixture, Edit", children: [
            Self.text("RouteFixture", 20, 186),
            button,
            Self.text("Step 3 of 4", 20, 220),
        ])

        let result = Self.evaluate([row])

        #expect(result.examined == 3)
        #expect(result.findings.count == 1)
        #expect(result.findings.first?.label == "Edit")
    }

    @Test
    func barsAreLeftOut() {
        let bar = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 100), children: [Self.text("Title", 100, 60)])

        let result = Self.evaluate([Self.text("Body", 20, 200), bar])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    @Test
    func aRightToLeftStateIsNotJudged() {
        let children = [Self.text("Value", 250, 100), Self.text("Name", 20, 102)]

        #expect(Self.evaluate(children, slug: "light-loc_ar").findings.isEmpty)
        #expect(Self.evaluate(children, slug: "light-loc_en_gb").findings.count == 1)
    }

    @Test
    func aLayoutDirectionAxisStateIsNotJudged() {
        let mirrored = [Self.text("Value", 250, 100), Self.text("Name", 20, 102)]

        #expect(Self.evaluate(mirrored, slug: "light-rtl").findings.isEmpty)
        #expect(Self.evaluate(mirrored, slug: "light-loc_iw").findings.isEmpty)
        #expect(Self.evaluate(mirrored, slug: "light-ltr").findings.count == 1)
    }

    /// A labelled container whose children carry no text speaks for nothing (SimWalk#118), so it is not a stop of its own.
    @Test
    func aLabelledContainerWhoseChildrenCarryNoTextIsNotAStop() {
        let glyph = AXNode(type: "Image", frame: AXNode.Frame(x: 20, y: 300, width: 40, height: 40))
        let card = AXNode(type: "Other", frame: AXNode.Frame(x: 20, y: 300, width: 300, height: 60), label: "Card", children: [glyph])

        let result = Self.evaluate([card, Self.text("Title", 20, 100)])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    private static func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> AXNode.Frame {
        AXNode.Frame(x: x, y: y, width: width, height: height)
    }

    /// A labelled table cell is one stop (SimWalk#236): the settings-table shape, a count right of the title and an icon whose label is a symbol name the cell's label lacks. Does not pin the cell's own frame being on screen.
    @Test
    func aLabelledCellWithoutAControlIsOneStop() {
        let icon = AXNode(type: "Other", frame: Self.frame(36, 319.33, 24, 24), children: [
            AXNode(type: "Image", frame: Self.frame(36, 319.33, 24, 24), label: "brightness higher"),
        ])
        let cell = AXNode(type: "Cell", frame: Self.frame(20, 292.33, 380, 78), label: "Today 17 unread", children: [
            AXNode(type: "Other", frame: Self.frame(20, 292.33, 380, 78), children: [AXNode(type: "Other", frame: Self.frame(20, 292.33, 380, 78))]),
            Self.text("Today", 68, 307.33, width: 265.33, height: 48),
            Self.text("17", 343.33, 304.33, width: 40.67, height: 55),
            icon,
        ])

        let result = Self.evaluate([Self.text("Title", 20, 100), cell, Self.text("Body", 20, 600)])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 3)
    }

    /// The control for #236: the same cell holding an enabled switch is descended into, so a backward step inside it is still found.
    @Test
    func aLabelledCellHoldingAControlIsDescendedInto() {
        let cell = AXNode(type: "Cell", frame: Self.frame(20, 300, 380, 40), label: "Today 17 unread", children: [
            AXNode(type: "Switch", frame: Self.frame(330, 300, 50, 30), label: "Today"),
            Self.text("Today", 68, 300, width: 100, height: 30),
        ])

        let result = Self.evaluate([cell])

        #expect(result.findings.count == 1)
    }

    /// A tall paragraph with a picture beside it is not a line read out of order (SimWalk#237): the picture's 50 pt overlaps 50 of the paragraph's 284 pt. Frames are the tree's own.
    @Test
    func aPictureBesideATallParagraphIsNotOnTheParagraphsRow() {
        let paragraph = AXNode(type: "StaticText", frame: Self.frame(94, 166, 276, 284.33), label: "Hi there! My name is Thomas.")
        let photo = AXNode(type: "Image", frame: Self.frame(32, 234, 50, 50), label: "icon0")
        let cell = AXNode(type: "Cell", frame: Self.frame(16, 151, 370, 314.33), children: [paragraph, photo])

        let result = Self.evaluate([cell])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 2)
    }

    /// The control for #237: two one-line elements on one row, the one on the left read second, are still a finding.
    @Test
    func twoOneLineElementsOnOneRowInTheWrongOrderAreStillFound() {
        let overflow = AXNode(type: "Button", frame: Self.frame(300, 100, 60, 20), label: "overflow")

        let result = Self.evaluate([overflow, Self.text("Featured article", 20, 100, width: 200)])

        #expect(result.findings.count == 1)
    }

    /// A section title beside a taller menu button is one row, though their overlap is less than half the button (SimWalk#237): it does not pin a paragraph's exact cutoff.
    @Test
    func aTitleBesideATallerButtonIsStillOneRow() {
        let title = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 215, width: 200, height: 18), label: "Featured article")
        let menu = AXNode(type: "Button", frame: AXNode.Frame(x: 336, y: 199, width: 50, height: 50), label: "overflow")
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [menu, title])

        let result = ReadingOrderAudit().evaluate(screen, screenID: "home", stateSlug: "light")

        #expect(result.findings.count == 1)
    }
}
