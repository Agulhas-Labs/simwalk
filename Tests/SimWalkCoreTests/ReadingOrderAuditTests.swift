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
}
