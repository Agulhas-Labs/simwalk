//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `symbolNameLabel`: a control whose label is an SF Symbol name, read aloud letter for letter.
struct SymbolNameLabelAuditTests {
    private static func evaluate(_ children: [AXNode]) -> LabelRuleResult {
        SymbolNameLabelAudit().evaluate(LabelTreeFixture.screen(children), screenID: "settings", stateSlug: "light")
    }

    @Test(arguments: ["gearshape.fill", "chevron.right", "person.crop.circle", "arrow.up.right.square", "questionmark", "xmark"])
    func aSymbolNameLabelIsAFinding(label: String) {
        let result = Self.evaluate([LabelTreeFixture.element("Button", label: label, y: 0)])

        #expect(result.findings.map(\.label) == [label])
    }

    /// Real labels that a looser rule would read as symbols: an app's unit buttons, single words that are also symbol names, and dotted strings that are not symbols.
    @Test(arguments: ["pounds", "kilograms", "plus", "minus", "heart", "camera", "Save", "Add meal", "Settings.", "example.com", "apple.id", "v1.2", "3.5", "Gearshape.fill", "a.m.", "photo.jpg", "readme.md", "data.csv", "e.g"])
    func aRealLabelIsNot(label: String) {
        let result = Self.evaluate([LabelTreeFixture.element("Button", label: label, y: 0)])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 1)
    }

    /// Apple's Settings labels its disabled disclosure buttons `chevron`; a screen with nothing to find must stay clean.
    @Test
    func aDisabledControlIsNotExamined() {
        let result = Self.evaluate([LabelTreeFixture.element("Button", label: "chevron.right", y: 0, enabled: false)])

        #expect(result.findings.isEmpty)
        #expect(result.examined == 0)
    }

    @Test
    func onlyControlsAreJudged() {
        let result = Self.evaluate([LabelTreeFixture.element("StaticText", label: "chevron.right", y: 0)])

        #expect(result.findings.isEmpty)
    }
}
