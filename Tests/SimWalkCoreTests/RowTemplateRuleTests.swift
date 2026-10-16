//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// ``RowTemplateRule`` on lists built by hand: a longer list is data, a row laid out in a new way is form.
struct RowTemplateRuleTests {
    /// One more row of a template the reference already has is not a flag.
    @Test
    func anExtraRowOfAnExistingTemplateIsNotAFlag() {
        let reference = FormRuleTests.capture([FormRuleTests.section("Sessions", y: 100, rows: 3)])
        let run = FormRuleTests.capture([FormRuleTests.section("Sessions", y: 100, rows: 4, figure: "12.5 km")])

        #expect(RowTemplateRule().flags(reference: reference, run: run).isEmpty)
    }

    /// A row whose figure now comes before its title is a template the reference lacks: flagged once, on the run side, whatever its text.
    @Test
    func aRowOfANewTemplateIsAFlag() {
        let reference = FormRuleTests.capture([FormRuleTests.section("Sessions", y: 100, rows: 3)])
        var section = FormRuleTests.section("Sessions", y: 100, rows: 3)
        section.textRuns += [
            ScreenSection.TextRun(shape: "figure", frame: AXNode.Frame(x: 300, y: 426, width: 60, height: 20)),
            ScreenSection.TextRun(shape: "title", frame: AXNode.Frame(x: 22, y: 426, width: 60, height: 20)),
        ]
        let run = FormRuleTests.capture([section])

        let flags = RowTemplateRule().flags(reference: reference, run: run)

        #expect(flags.map(\.key) == ["Sessions"])
        #expect(flags.map(\.finding) == [.rowTemplate(side: .run, template: [.trailing, .leading], row: ["figure", "title"])])
        #expect(flags.first?.crops.map(\.side) == [.run])
    }
}
