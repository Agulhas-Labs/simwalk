//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `duplicateLabel`: two distinct enabled controls on one screen state answering to one label.
struct DuplicateLabelAuditTests {
    private static func evaluate(_ children: [AXNode]) -> LabelRuleResult {
        DuplicateLabelAudit().evaluate(LabelTreeFixture.screen(children), screenID: "you", stateSlug: "light")
    }

    @Test
    func twoControlsWithOneLabelAreOneFinding() {
        let result = Self.evaluate([
            LabelTreeFixture.element("Button", label: "Connect", y: 0),
            LabelTreeFixture.element("Button", label: "Connect", y: 60),
            LabelTreeFixture.element("Button", label: "Save", y: 120),
        ])

        #expect(result.findings.count == 1)
        #expect(result.findings.first?.label == "Connect")
        #expect(result.findings.first?.note == "×2")
        #expect(result.examined == 3)
    }

    @Test
    func distinctLabelsAreClean() {
        let result = Self.evaluate([
            LabelTreeFixture.element("Button", label: "Connect Strava", y: 0),
            LabelTreeFixture.element("Button", label: "Connect Concept2", y: 60),
        ])

        #expect(result.findings.isEmpty)
    }

    /// The Settings calibration: one `Dictate` button listed twice at one frame is one control seen by two paths.
    @Test
    func theSameElementListedTwiceAtOneFrameIsNotTwoControls() {
        let result = Self.evaluate([
            LabelTreeFixture.element("Button", label: "Dictate", y: 0),
            LabelTreeFixture.element("Button", label: "Dictate", y: 0),
        ])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    /// The app calibration: a tab named `Browse` and the back button to it on a detail screen.
    @Test
    func aTabAndTheBackButtonToItAreNotDuplicates() {
        let result = Self.evaluate([
            LabelTreeFixture.bar("NavigationBar", [LabelTreeFixture.element("Button", label: "Browse", y: 60)]),
            LabelTreeFixture.bar("TabBar", [LabelTreeFixture.element("Button", label: "Browse", y: 790)]),
        ])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    @Test
    func aDisabledTwinIsNotACompetingControl() {
        let result = Self.evaluate([
            LabelTreeFixture.element("Button", label: "Connect", y: 0),
            LabelTreeFixture.element("Button", label: "Connect", y: 60, enabled: false),
        ])

        #expect(result.findings.isEmpty)
    }

    @Test
    func aControlWithoutALabelIsNotCompared() {
        let result = Self.evaluate([
            LabelTreeFixture.element("Switch", y: 0),
            LabelTreeFixture.element("Switch", y: 60),
        ])

        #expect(result.findings.isEmpty)
    }

    /// An onboarding pager keeps every page in the tree; a `Continue` a page away is not on this screen.
    @Test
    func anOffScreenTwinIsNotACompetingControl() {
        let result = Self.evaluate([
            LabelTreeFixture.element("Button", label: "Continue", y: 0),
            AXNode(type: "Button", frame: AXNode.Frame(x: 402, y: 0, width: 200, height: 44), label: "Continue"),
        ])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }
}
