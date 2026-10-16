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
        #expect(result.findings.first?.note == "overlaps '12,345'")
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
        #expect(result.findings.first?.note == "extends past the screen's width; overlaps '62'; overlaps 'bpm'")
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
}
