//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `unlabelledControl`: an enabled control a screen reader has nothing to say for.
struct UnlabelledControlAuditTests {
    private static func evaluate(_ children: [AXNode]) -> LabelRuleResult {
        UnlabelledControlAudit().evaluate(LabelTreeFixture.screen(children), screenID: "you", stateSlug: "light")
    }

    /// Every operable type the rule names, each with neither label nor identifier.
    @Test
    func anEnabledControlWithNeitherLabelNorIdentifierIsAFinding() {
        let controls = ["Button", "Link", "Switch", "Slider", "TextField"].enumerated().map { index, type in
            LabelTreeFixture.element(type, y: Double(index) * 60)
        }

        let result = Self.evaluate(controls)

        #expect(result.findings.map(\.type) == ["Button", "Link", "Switch", "Slider", "TextField"])
        #expect(result.examined == 5)
    }

    @Test
    func aLabelOrAnIdentifierIsEnough() {
        let result = Self.evaluate([
            LabelTreeFixture.element("Button", label: "Save", y: 0),
            LabelTreeFixture.element("Switch", identifier: "notifications-toggle", y: 60),
            LabelTreeFixture.element("Slider", label: "  ", identifier: "volume", y: 120),
        ])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 3)
    }

    /// A control offered as unavailable is deliberate, and is not examined.
    @Test
    func aDisabledControlIsNotExamined() {
        let result = Self.evaluate([LabelTreeFixture.element("Button", y: 0, enabled: false)])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    @Test
    func aBlankLabelCountsAsNone() {
        let result = Self.evaluate([LabelTreeFixture.element("Button", label: "   ", y: 0)])

        #expect(result.findings.count == 1)
    }

    /// The glyph of a button with no label of its own is its only voice.
    @Test
    func anUnlabelledImageInsideAnUnlabelledButtonIsAFinding() {
        let glyph = LabelTreeFixture.element("Image", y: 4)
        let result = Self.evaluate([LabelTreeFixture.element("Button", identifier: "settings", y: 0, children: [glyph])])

        #expect(result.findings.map(\.type) == ["Image"])
    }

    /// The Settings calibration: each row's icon is a decorative image inside a button whose label is read.
    @Test
    func anUnlabelledImageInsideALabelledButtonIsNot() {
        let icon = LabelTreeFixture.element("Image", y: 4)
        let result = Self.evaluate([LabelTreeFixture.element("Button", label: "General", identifier: "com.apple.settings.general", y: 0, children: [icon])])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    @Test
    func anImageOutsideAnyButtonIsNotAControl() {
        let result = Self.evaluate([LabelTreeFixture.element("Image", y: 0)])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    @Test
    func aCleanScreenHasNoFindings() {
        let result = Self.evaluate([
            LabelTreeFixture.element("StaticText", label: "Title", y: 0),
            LabelTreeFixture.element("Button", label: "Save", y: 60),
        ])

        #expect(result.findings.isEmpty)
    }

    /// One defective control, not two: the button is the finding and its glyph is not counted again.
    @Test
    func anUnlabelledButtonHoldingAnUnlabelledImageIsOneFinding() {
        let glyph = LabelTreeFixture.element("Image", y: 4)
        let result = Self.evaluate([LabelTreeFixture.element("Button", y: 0, children: [glyph])])

        #expect(result.findings.map(\.type) == ["Button"])
        #expect(result.examined == 1)
    }

    @Test
    func anUnlabelledControlInABarIsExamined() {
        let bar = LabelTreeFixture.element("NavigationBar", y: 0, children: [LabelTreeFixture.element("Button", y: 4)])
        let result = Self.evaluate([bar])

        #expect(result.findings.map(\.type) == ["Button"])
    }

    /// SimWalk#112: a SwiftUI `Menu` row is a labelled `Button` with an unlabelled `Button` of the same frame inside it.
    @Test
    func theButtonAMenuNestsInsideItsLabelledButtonIsNotAFinding() {
        let inner = LabelTreeFixture.element("Button", y: 0)
        let outer = LabelTreeFixture.element("Button", label: "Rowing, 406 sessions", identifier: "Identifiers_row_rowing", y: 0, children: [inner])

        let result = Self.evaluate([outer])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    /// SimWalk#102: a `Toggle` in a `Form` is a labelled `Switch` with the platform's smaller unlabelled `Switch` inside it.
    @Test
    func theSwitchAToggleNestsInsideItsLabelledSwitchIsNotAFinding() {
        let inner = AXNode(type: "Switch", frame: AXNode.Frame(x: 323, y: 12, width: 63, height: 28), isEnabled: true)
        let outer = AXNode(type: "Switch", frame: AXNode.Frame(x: 16, y: 0, width: 370, height: 87), label: "On-device wording, On", identifier: "wording", isEnabled: true, children: [inner])

        let result = Self.evaluate([outer])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    @Test
    func anIdentifierAloneOnTheEnclosingButtonExcusesNothing() {
        let inner = LabelTreeFixture.element("Button", y: 0)
        let outer = LabelTreeFixture.element("Button", identifier: "row", y: 0, children: [inner])

        let result = Self.evaluate([outer])

        #expect(result.findings.count == 1)
        #expect(result.examined == 2)
    }

    @Test
    func aButtonOutsideTheFrameOfItsLabelledEnclosingButtonIsStillAFinding() {
        let inner = LabelTreeFixture.element("Button", y: 200)
        let outer = LabelTreeFixture.element("Button", label: "Row", y: 0, children: [inner])

        let result = Self.evaluate([outer])

        #expect(result.findings.count == 1)
        #expect(result.examined == 2)
    }

    /// The enclosing control is the nearest enabled one (SimWalk#118): a labelled control further up does not excuse an unlabelled one inside another unlabelled one.
    @Test
    func aLabelledControlFurtherUpDoesNotExcuseTheInnermostOfThree() {
        let inner = LabelTreeFixture.element("Switch", y: 0)
        let middle = LabelTreeFixture.element("Button", y: 0, children: [inner])
        let outer = LabelTreeFixture.element("Button", label: "Notifications", y: 0, children: [middle])

        let result = Self.evaluate([outer])

        #expect(result.findings.map(\.type) == ["Switch"])
    }

    /// SimWalk#234, from a real add-feed sheet: an empty `TextField` with only a placeholder is named by it, as VoiceOver speaks it.
    ///
    /// Does not pin the other text-entry types, which the rule does not yet examine.
    @Test
    func anEmptyTextFieldWithAPlaceholderIsNamedByIt() {
        let field = LabelTreeFixture.element("TextField", placeholder: "URL", y: 192)

        let result = Self.evaluate([field])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    /// SimWalk#234, the control: a field holding a value shows and speaks the value, never the placeholder, so `Name` over `NetNewsWire Blog` is still unlabelled.
    @Test
    func aTextFieldHoldingAValueIsNotNamedByItsPlaceholder() {
        let field = LabelTreeFixture.element("TextField", value: "NetNewsWire Blog", placeholder: "Name", y: 244)

        let result = Self.evaluate([field])

        #expect(result.findings.map(\.type) == ["TextField"])
    }

    @Test
    func anEmptyTextFieldWithABlankPlaceholderIsAFinding() {
        let field = LabelTreeFixture.element("TextField", placeholder: "  ", y: 192)

        let result = Self.evaluate([field])

        #expect(result.findings.map(\.type) == ["TextField"])
    }
}
