//
// Copyright © Agulhas Labs
//

/// What a screen's taken captures become once its checks have had their say — the runner's `record` decision, made here so `swift test` can hold it (`.agents/CodingGuidelines.md`: "a decision the runner makes belongs in the core").
///
/// **The order is the decision.** `expect` is checked first (`ExpectedScreenCheck`), against every capture taken and against the outcome the runner was headed for — a failure part-way included — so a wrong screen is a finding about the whole screen before any state has a verdict to inherit. The open-menu check (`ExpectedMenuCheck`, SimWalk#111) follows it on that outcome, keeping a prior mismatch's expected and found. The values check (`ExpectedValueCheck`, SimWalk#259) follows the menu check the same way. The state check (`StateApplicationCheck.filing`) runs last, on that checked outcome, and decides which states may be filed. Handing the state check the runner's own outcome instead is how a wrong screen's capture came to be filed under `captureFailed`, where `bundle audit` reads it under the id the walkbook expected.
public struct ScreenFiling {
    /// The filing for a screen whose captures produced `trees` and `evidence` (one of each per state taken, in capture order), given the screen's `expect`, `expectMenu` and `expectValues`, and the outcome the runner was headed for.
    public static func decide(
        trees: [AXNode],
        evidence: [StateApplicationCheck.Evidence],
        expect: String?,
        expectMenu: [String]? = nil,
        expectValues: [Walkbook.ExpectedValue]? = nil,
        instead intended: ScreenOutcome,
        deviceAppearance: Walkbook.Theme? = nil,
        deviceLocale: String? = nil,
        fixedAppearance: Walkbook.Theme? = nil
    ) -> StateApplicationCheck.Filing {
        let screenChecked = ExpectedScreenCheck.outcome(for: trees, expect: expect, instead: intended)
        let menuChecked = ExpectedMenuCheck.outcome(for: trees, expectMenu: expectMenu, instead: screenChecked)
        let checked = ExpectedValueCheck.outcome(for: trees, expectValues: expectValues, instead: menuChecked)
        return StateApplicationCheck.filing(for: evidence, instead: checked, deviceAppearance: deviceAppearance, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance)
    }
}
