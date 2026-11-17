//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import Testing

/// `largeTypeOverflow`: text that does not fit at an accessibility Dynamic Type size.
struct LargeTypeOverflowAuditTests {
    private static var accessibility: String {
        "dark-dt_uictcontentsizecategoryaccessibilityl"
    }

    private static func text(_ label: String, _ x: Double, _ y: Double, width: Double = 100, height: Double = 20) -> AXNode {
        AXNode(type: "StaticText", frame: AXNode.Frame(x: x, y: y, width: width, height: height), label: label)
    }

    private static func evaluate(_ children: [AXNode], slug: String) -> LabelRuleResult {
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: children)
        return LargeTypeOverflowAudit().evaluate(screen, screenID: "progress", stateSlug: slug)
    }

    @Test
    func aRunPastTheScreenWidthFiresAtAnAccessibilitySize() {
        let result = Self.evaluate([Self.text("Resting heart rate", 200, 100, width: 300)], slug: Self.accessibility)

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note == "extends past the screen's width")
        #expect(result.examined == 1)
    }

    @Test
    func theSameOverflowInAnOrdinaryStateIsNotExamined() {
        let children = [Self.text("Resting heart rate", 200, 100, width: 300)]

        for slug in ["light", "light-dt_uictcontentsizecategoryxxl", "dark-loc_en_gb"] {
            let result = Self.evaluate(children, slug: slug)
            #expect(result.findings.isEmpty)
            #expect(result.examined == 0)
        }
    }

    @Test
    func aRunReportingItsContainersFrameDoesNotOverlapASiblingInsideIt() {
        // SimWalk#100: the row's text carries the Button's own 362x182 frame; the chevron inside is real.
        let row = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 100, width: 362, height: 182), label: "What changed around then", children: [
            Self.text("What changed around then", 20, 100, width: 362, height: 182),
            Self.text("›", 360, 160, width: 19, height: 58),
        ])

        let result = Self.evaluate([row], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
        #expect(result.examined == 2)
    }

    @Test
    func twoSiblingRunsWhoseFramesOverlapFire() {
        let result = Self.evaluate([Self.text("Steps", 20, 100, width: 200), Self.text("12,345", 150, 105, width: 200)], slug: Self.accessibility)

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.label == "Steps")
        #expect(result.findings.first?.note == "y 100–120 (20 pt) overlaps '12,345' y 105–125 (20 pt)")
    }

    /// SimWalk#142: the tall run an `accessibilityRepresentation` lays out at body size runs past the table it speaks for; the note must say which run is which size.
    @Test
    func anOverlapNoteCarriesBothRunsRangesAndHeights() {
        let result = Self.evaluate([
            Self.text("Time, not walks", 20, 2735, width: 300, height: 497),
            Self.text("Found 6 Jan", 20, 3051, width: 300, height: 240),
        ], slug: Self.accessibility)

        let note = result.findings.first?.note

        #expect(note == "y 2735–3232 (497 pt) overlaps 'Found 6 Jan' y 3051–3291 (240 pt)", "\(String(describing: note))")
    }

    @Test
    func runsThatFitAndStackAreClean() {
        let result = Self.evaluate([Self.text("Steps", 20, 100, width: 300), Self.text("12,345", 20, 130, width: 300)], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
        #expect(result.examined == 2)
    }

    @Test
    func identicalFramesAndNonSiblingsAreNotOverlaps() {
        let twin = [Self.text("Dictate", 20, 100), Self.text("Dictate", 20, 100)]
        let card = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 300, width: 402, height: 80), children: [Self.text("Inside", 20, 310)])

        let result = Self.evaluate(twin + [Self.text("Outside", 20, 305), card], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
    }

    @Test
    func aRunThatOverflowsAndOverlapsTwoSiblingsIsOneFinding() {
        let result = Self.evaluate([
            Self.text("Resting heart rate", 300, 100, width: 300),
            Self.text("62", 310, 105, width: 40),
            Self.text("bpm", 360, 105, width: 30),
        ], slug: Self.accessibility)

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note == "extends past the screen's width; y 100–120 (20 pt) overlaps '62' y 105–125 (20 pt); overlaps 'bpm' y 105–125 (20 pt)")
    }

    /// The container-framed run is left out whichever side of the pair it is on (SimWalk#118).
    @Test
    func aRunReportingItsContainersFrameAfterTheSiblingDoesNotOverlapIt() {
        let row = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 100, width: 362, height: 182), label: "What changed around then", children: [
            Self.text("›", 360, 160, width: 19, height: 58),
            Self.text("What changed around then", 20, 100, width: 362, height: 182),
        ])

        let result = Self.evaluate([row], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
        #expect(result.examined == 2)
    }

    /// Reporting its container's frame excuses a run from overlap, not from the screen's width.
    @Test
    func aRunReportingItsContainersFrameIsStillCheckedAgainstTheScreenWidth() {
        let row = AXNode(type: "Button", frame: AXNode.Frame(x: 200, y: 100, width: 300, height: 40), label: "Wide", children: [
            Self.text("Wide", 200, 100, width: 300, height: 40),
        ])

        let result = Self.evaluate([row], slug: Self.accessibility)

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note == "extends past the screen's width")
    }

    /// Two runs of a cell below the fold, both still at the placeholder origin a table gives a cell it has not laid out (SimWalk#230).
    ///
    /// Does not pin the runs of a laid-out cell.
    @Test
    func runsAtAPlaceholderFrameInACellBelowTheFoldAreNotJudged() {
        let theme = AXNode(type: "StaticText", frame: AXNode.Frame(x: 0, y: 142, width: 120, height: 48), label: "Theme")
        let value = AXNode(type: "StaticText", frame: AXNode.Frame(x: 0, y: 142, width: 122.67, height: 48), label: "Default")
        let cell = AXNode(type: "Cell", frame: AXNode.Frame(x: 20, y: 2017.3, width: 380, height: 58), children: [theme, value])

        let result = Self.evaluate([cell], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    private static func webRuns() -> [AXNode] {
        [
            text(".", 111, 1418, width: 10, height: 48),
            AXNode(type: "Link", frame: AXNode.Frame(x: 122, y: 1413, width: 40, height: 48), label: "[14]"),
            text(" Cape Town is the capital and largest city of the", 16, 1418, width: 346, height: 173),
        ]
    }

    /// A page's wrapped run reports a multi-line bounding box, so it overlaps the words before it without a glyph doing so (SimWalk#229).
    ///
    /// Does not pin a Link being compared: only `StaticText` is a run.
    @Test
    func runsInsideAWebViewAreNotComparedWithEachOther() {
        let page = AXNode(type: "WebView", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [
            AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 1034, width: 358, height: 1148), children: Self.webRuns()),
        ])

        let result = Self.evaluate([page], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
    }

    /// The exemption is the web view, not the shape of the runs.
    @Test
    func theSameRunsWithoutAWebViewStillOverlap() {
        let block = AXNode(type: "Other", frame: AXNode.Frame(x: 16, y: 1034, width: 358, height: 1148), children: Self.webRuns())

        let result = Self.evaluate([block], slug: Self.accessibility)

        #expect(!result.findings.isEmpty)
    }

    /// A run inside a web view is still held to the screen's width.
    @Test
    func aRunInsideAWebViewIsStillCheckedAgainstTheScreenWidth() {
        let page = AXNode(type: "WebView", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [Self.text("Wide", 200, 100, width: 300)])

        let result = Self.evaluate([page], slug: Self.accessibility)

        #expect(result.findings.first?.note == "extends past the screen's width")
    }

    /// A button's combined label and its own part share a frame region and a label, by design (SimWalk#238).
    @Test
    func anElementsCombinedLabelDoesNotOverlapItsOwnPart() {
        let button = AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 369.67, width: 380, height: 130), label: "Folder, On My iPhone", children: [
            Self.text("Folder, On My iPhone", 40, 384.67, width: 239.67, height: 100),
            Self.text("Folder", 40, 384.67, width: 100, height: 48),
        ])

        let result = Self.evaluate([button], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
    }

    /// A title and the subtitle under it overlap by line-box slack, a third of a line at most (SimWalk#238).
    @Test
    func aShallowVerticalOverlapIsNotACollision() {
        let bar = AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 68, width: 402, height: 160.33), children: [
            Self.text("Feeds", 19.94, 127.90, width: 147.78, height: 63.53),
            Self.text("Updated 13 minutes ago", 19.99, 183.83, width: 319.35, height: 35.33),
        ])

        let result = Self.evaluate([bar], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
    }

    /// The slack allowance stops at 12 pt, so two tall wrapped runs that share 50 pt are a collision (SimWalk#238).
    @Test
    func aDeepVerticalOverlapOfTallRunsIsStillACollision() {
        let column = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [
            Self.text("First paragraph", 20, 100, width: 300, height: 240),
            Self.text("Second paragraph", 20, 290, width: 300, height: 250),
        ])

        let result = Self.evaluate([column], slug: Self.accessibility)

        #expect(!result.findings.isEmpty)
    }

    private static func strip(_ chips: [AXNode], width: Double = 600, height: Double = 68) -> AXNode {
        AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 240, width: width, height: height), identifier: "home-topics", children: chips)
    }

    private static func evaluate(_ children: [AXNode], screenWidth: Double, screenHeight: Double) -> LabelRuleResult {
        let screen = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: screenWidth, height: screenHeight), children: children)
        return LargeTypeOverflowAudit().evaluate(screen, screenID: "home", stateSlug: accessibility)
    }

    /// Topic chips in a horizontal ScrollView scroll sideways by design, so a chip past the edge is not overflow (SimWalk#287).
    @Test
    func runsInAHorizontalStripPastTheScreenWidthAreNotReportedButCounted() {
        let chips = Self.strip([Self.text("Times tables", 20, 250, width: 160), Self.text("Fractions", 450, 250, width: 150)])

        let result = Self.evaluate([chips], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
        #expect(result.examined == 2)
        #expect(result.inHorizontalScroller == 1)
    }

    /// A sheet holding a chip strip is not itself a strip: the chip past the edge exempts only the strip's own runs, and the sheet's overflowing label is reported (SimWalk#287 round 2 re-review).
    @Test
    func aSheetHoldingAChipStripStillReportsItsOwnOverflow() {
        let chips = Self.strip([Self.text("Times tables", 20, 450, width: 160), Self.text("Fractions", 410, 450, width: 150)], width: 402)
        let sheet = AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 400, width: 402, height: 380), children: [
            chips,
            Self.text("Resting heart rate", 20, 560, width: 500),
        ])

        let result = Self.evaluate([sheet], slug: Self.accessibility)

        #expect(result.findings.count == 1)
        #expect(result.inHorizontalScroller == 1)
    }

    /// A short vertical scroller (a medium-detent sheet) has the strip's shape but nothing laid out past the screen, so its overflowing label is reported (SimWalk#287 round 2).
    @Test
    func aShortVerticalScrollerHoldingAnOverflowingRunIsStillReported() {
        let sheet = AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 400, width: 402, height: 380), children: [
            Self.text("Resting heart rate", 20, 450, width: 500),
        ])

        let result = Self.evaluate([sheet], slug: Self.accessibility)

        #expect(result.findings.count == 1)
        #expect(result.inHorizontalScroller == 0)
    }

    /// A strip as wide as the screen is a scroller when a chip starts at or beyond the right edge.
    @Test
    func aScreenWideStripWithARunStartingPastTheEdgeIsExempt() {
        let chips = Self.strip([Self.text("Times tables", 20, 250, width: 160), Self.text("Fractions", 410, 250, width: 150)], width: 402)

        let result = Self.evaluate([chips], slug: Self.accessibility)

        #expect(result.findings.isEmpty)
        #expect(result.inHorizontalScroller == 1)
        #expect(result.inHorizontalScrollerScreens == ["progress"])
    }

    /// A scroller as wide as a landscape iPad's screen is the vertical scroller of the whole screen, not a strip.
    @Test
    func aRunPastTheWidthInAFullScreenScrollViewIsStillReported() {
        let scroller = AXNode(type: "ScrollView", frame: AXNode.Frame(x: 0, y: 0, width: 1194, height: 834), children: [
            Self.text("Resting heart rate", 1000, 100, width: 300),
        ])

        let result = Self.evaluate([scroller], screenWidth: 1194, screenHeight: 834)

        #expect(result.findings.count == 1)
        #expect(result.inHorizontalScroller == 0)
    }

    @Test
    func aRunPastTheWidthInAScrollViewTallerThanWideIsStillReported() {
        let chips = Self.strip([Self.text("Fractions", 450, 250, width: 150)], width: 300, height: 600)

        let result = Self.evaluate([chips], slug: Self.accessibility)

        #expect(result.findings.count == 1)
    }

    @Test
    func collidingRunsInsideAHorizontalStripStillCollide() {
        let chips = Self.strip([Self.text("Times tables", 20, 250, width: 160, height: 40), Self.text("Fractions", 100, 260, width: 150, height: 40)])

        let result = Self.evaluate([chips], slug: Self.accessibility)

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.note?.contains("overlaps 'Fractions'") == true)
    }
}
