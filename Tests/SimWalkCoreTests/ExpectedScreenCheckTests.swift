//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A screen's `expect` is a claim about an identifier the reached screen carries in every capture it takes, not just the first one it happens to try — not just at the root, which real captures never carry one at (round 2, finding 1), and never in the tab bar, toolbar or navigation bar (round 3).
struct ExpectedScreenCheckTests {
    @Test
    func aScreenThatNamesNoExpectationKeepsWhateverItWasHeadedFor() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.screen(identifier: "you-root")], expect: nil, instead: .captured)

        #expect(outcome == .captured)
    }

    /// `expect` is opt-in, but not a shield: an intended outcome that already named a problem survives untouched when there is no expectation to check it against.
    @Test
    func aScreenThatNamesNoExpectationLeavesAnIntendedRefusalAlone() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.screen(identifier: "you-root")], expect: nil, instead: .captureFailed(reason: "disk full"))

        #expect(outcome == .captureFailed(reason: "disk full"))
    }

    /// The regression this round fixed: `app.snapshot()`'s root is always `Application`, which never carries an identifier on any capture this was checked against — the real `app.simwalk/screens/you/light` tree holds its screen identifier on a `ScrollView` seventeen levels below the root.
    ///
    /// A check that only read the root would report `unexpectedScreen(found: [nil])` for a screen that was actually correct, which is exactly what happened before this fix.
    @Test
    func anIdentifierSeventeenLevelsBelowTheApplicationRootStillMatches() {
        let outcome = ExpectedScreenCheck.outcome(
            for: [Self.screen(identifier: "activity-detail")],
            expect: "activity-detail",
            instead: .captured
        )

        #expect(outcome == .captured)
    }

    @Test
    func everyStateMatchingKeepsTheIntendedOutcome() {
        let outcome = ExpectedScreenCheck.outcome(
            for: [Self.screen(identifier: "activity-detail"), Self.screen(identifier: "activity-detail"), Self.screen(identifier: "activity-detail")],
            expect: "activity-detail",
            instead: .captured
        )

        #expect(outcome == .captured)
    }

    /// The evidence that would make "this screen was captured" false: a screen identifier that does not match, named beside what was expected.
    @Test
    func amismatchedScreenIdentifierBecomesTheScreensOutcome() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.screen(identifier: "workouts-list")], expect: "activity-detail", instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "activity-detail", found: ["workouts-list"]))
    }

    /// A capture with no screen identifier at all is a mismatch, not a pass — an `expect` that got nothing back has not been verified.
    @Test
    func acaptureWithNoScreenIdentifierIsAMismatch() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.screen(identifier: nil)], expect: "activity-detail", instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "activity-detail", found: [nil]))
    }

    /// Every captured state is checked, not only the first — a screen that lands right under `light` and wrong under `dark` is exactly the case a single-state check would file as a pass.
    @Test
    func aLaterStateLandingOnTheWrongScreenIsCaughtEvenWhenTheFirstMatched() {
        let outcome = ExpectedScreenCheck.outcome(
            for: [Self.screen(identifier: "activity-detail"), Self.screen(identifier: "workouts-list")],
            expect: "activity-detail",
            instead: .captured
        )

        #expect(outcome == .unexpectedScreen(expected: "activity-detail", found: ["workouts-list"]))
    }

    /// One mistake, made across several states, reported once — not once per state that repeats it.
    @Test
    func distinctMismatchesAreNamedOnceEachInCaptureOrder() {
        let outcome = ExpectedScreenCheck.outcome(
            for: [
                Self.screen(identifier: "workouts-list"),
                Self.screen(identifier: "workouts-list"),
                Self.screen(identifier: nil),
                Self.screen(identifier: "workouts-list"),
            ],
            expect: "activity-detail",
            instead: .captured
        )

        #expect(outcome == .unexpectedScreen(expected: "activity-detail", found: ["workouts-list", nil]))
    }

    /// A screen never named the search anywhere but at its own identified node still mismatches on an unrelated identifier elsewhere in the tree — the match is "holds a node carrying `expect`", not "holds a node carrying `expect` at the screen's own position".
    @Test
    func anIdentifierElsewhereInTheTreeDoesNotSatisfyAnUnrelatedExpectation() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.screen(identifier: "you-root")], expect: "activity-detail", instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "activity-detail", found: ["you-root"]))
    }

    /// Round 3: no chrome identifier counts toward an `expect`, and what the mismatch names is the screen's own identifier.
    ///
    /// Each of these sits on every screen, or names one element of it — the tab bar's symbol names, `BackButton`, `Toolbar`, SwiftUI's mangled hosting class, an image's symbol, a button's own identifier — so an `expect` matching one would pass everywhere.
    @Test(arguments: ["person.fill", "BackButton", "Toolbar", "_TtGC7SwiftUI32NavigationStackHosting"])
    func chromeNeverSatisfiesAnExpectation(expect: String) {
        let outcome = ExpectedScreenCheck.outcome(for: [ScreenIdentifierRuleTests.pushedScreen(content: "workouts-list")], expect: expect, instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: expect, found: ["workouts-list"]))
    }

    /// An element's own identifier inside the content never satisfies it either, but the refusal now names the element (SimWalk#284).
    @Test(arguments: [("heart.fill", "an Image"), ("share-button", "a Button")])
    func anElementIdentifierNeverSatisfiesAnExpectationAndIsNamed(expect: String, element: String) {
        let outcome = ExpectedScreenCheck.outcome(for: [ScreenIdentifierRuleTests.pushedScreen(content: "workouts-list")], expect: expect, instead: .captured)

        #expect(outcome == .unexpectedScreen(
            expected: expect,
            found: ["workouts-list"],
            reason: "'\(expect)' is on \(element) inside 'workouts-list', not a screen container: expect 'workouts-list' and end the route with scrollTo '\(expect)' to require the element"
        ))
    }

    /// Round 3, finding 3: a screen that filed a capture of the wrong screen and then failed mid-capture has both things wrong with it — the failure rides in the mismatch's `reason` rather than the mismatch being dropped for a bare `captureFailed` (whose captures `bundle audit` would read under the expected id), or the failure being dropped for a bare mismatch.
    @Test
    func afailureMidCaptureRidesInTheMismatchRatherThanEitherBeingDropped() {
        let outcome = ExpectedScreenCheck.outcome(
            for: [Self.screen(identifier: "workouts-list")],
            expect: "activity-detail",
            instead: .captureFailed(reason: "state 'dark': snapshot timed out")
        )

        #expect(outcome == .unexpectedScreen(
            expected: "activity-detail",
            found: ["workouts-list"],
            reason: "The screen also failed mid-capture: state 'dark': snapshot timed out"
        ))
    }

    /// The partial path with the right screen keeps its failure untouched — the check only ever adds a finding.
    @Test
    func afailureMidCaptureOnTheRightScreenIsLeftAlone() {
        let outcome = ExpectedScreenCheck.outcome(
            for: [Self.screen(identifier: "activity-detail")],
            expect: "activity-detail",
            instead: .captureFailed(reason: "state 'dark': snapshot timed out")
        )

        #expect(outcome == .captureFailed(reason: "state 'dark': snapshot timed out"))
    }

    /// Checked first and folded second, the two findings end in the shape round 2 gave a state refusal beside a mismatch: `unexpectedScreen`, carrying the failure and the refusal together, with the refused state named.
    @Test
    func afailureMidCaptureAndAStateRefusalBothSurviveAMismatch() {
        let intended = ExpectedScreenCheck.outcome(
            for: [Self.screen(identifier: "workouts-list"), Self.screen(identifier: "workouts-list")],
            expect: "activity-detail",
            instead: .captureFailed(reason: "state 'light-loc_fr_fr': snapshot timed out")
        )
        let picture = Data("the same picture".utf8)

        let filing = StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light), screenshot: picture),
                StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .dark), screenshot: picture),
            ],
            instead: intended
        )

        guard case let .unexpectedScreen(expected, found, reason) = filing.outcome else {
            Issue.record("expected the mismatch to survive, got \(filing.outcome)")
            return
        }

        #expect(expected == "activity-detail")
        #expect(found == ["workouts-list"])
        #expect(reason?.contains("failed mid-capture") == true)
        #expect(reason?.contains("'light' and 'dark'") == true)
        #expect(!filing.refused.isEmpty)
    }

    /// Round 4, finding 1: an `expect` naming the navigation bar's title — what a reader copies from a title-only screen — is a mismatch, and the mismatch says why, so the fix is the app's identifier rather than a second guess at the title.
    @Test
    func anExpectationNamingTheNavigationBarTitleIsAMismatchThatSaysSo() {
        let outcome = ExpectedScreenCheck.outcome(for: [ScreenIdentifierRuleTests.pushedScreen(content: nil, title: "Heart")], expect: "Heart", instead: .captured)

        #expect(outcome == .unexpectedScreen(
            expected: "Heart",
            found: [nil],
            reason: "'Heart' is this screen's navigation-bar title; titles are localised and never count; set an accessibilityIdentifier on the content"
        ))
    }

    /// The hint leads and a failure mid-capture still rides beside it, and checking the outcome this produced again adds nothing.
    @Test
    func theTitleHintLeadsAndKeepsAFailureMidCapture() {
        let trees = [ScreenIdentifierRuleTests.pushedScreen(content: nil, title: "Heart")]
        let once = ExpectedScreenCheck.outcome(for: trees, expect: "Heart", instead: .captureFailed(reason: "state 'dark': snapshot timed out"))

        #expect(once == .unexpectedScreen(
            expected: "Heart",
            found: [nil],
            reason: "'Heart' is this screen's navigation-bar title; titles are localised and never count; set an accessibilityIdentifier on the content. The screen also failed mid-capture: state 'dark': snapshot timed out"
        ))
        #expect(ExpectedScreenCheck.outcome(for: trees, expect: "Heart", instead: once) == once)
    }

    /// Round 5, finding 4: the real `sleep_detail` capture — `expect: "Sleep"` mismatched a content identifier of `HealthService.SleepView.Identifiers_screen` — where the content *does* carry an identifier, so the hint names it rather than telling an author to add one that is already there.
    @Test
    func theTitleHintNamesTheContentsRealIdentifierWhenItCarriesOne() {
        let outcome = ExpectedScreenCheck.outcome(
            for: [ScreenIdentifierRuleTests.pushedScreen(content: "HealthService.SleepView.Identifiers_screen", title: "Sleep")],
            expect: "Sleep",
            instead: .captured
        )

        #expect(outcome == .unexpectedScreen(
            expected: "Sleep",
            found: ["HealthService.SleepView.Identifiers_screen"],
            reason: "'Sleep' is this screen's navigation-bar title, which is localised and never counts; its stable identifier is 'HealthService.SleepView.Identifiers_screen'"
        ))
    }

    /// SimWalk#103: a screen hosted inside another's content carries both identifiers, and `expect` naming either passes.
    @Test(arguments: ["outer", "inner"])
    func aNestedScreenAnchorSatisfiesAnExpectation(expect: String) {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.hostedScreen()], expect: expect, instead: .captured)

        #expect(outcome == .captured)
    }

    /// A mismatch against a hosted screen names the path of identifiers to the deepest one, and says why the deepest matters (SimWalk#272).
    @Test
    func aMismatchAgainstAHostedScreenNamesThePathToTheDeepestIdentifier() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.hostedScreen()], expect: "missing", instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "missing", found: ["outer > inner"], reason: Self.deepestClause("inner")))
    }

    /// SimWalk#272: `parent` > two `Other`s > `controls` > a `StaticText`, `pin-set` expected — `found` reads `parent > controls`, so the author sees the identifier that replaced theirs.
    @Test
    func aContainerIdentifierReplacingTheOneInsideItIsNamedAsTheDeepestInThePath() {
        let tree = AXNode(type: "Application", frame: Self.screenFrame, children: [
            AXNode(type: "Other", frame: Self.screenFrame, identifier: "parent", children: [
                AXNode(type: "Other", frame: Self.screenFrame, children: [
                    AXNode(type: "Other", frame: Self.screenFrame, children: [
                        AXNode(type: "Other", frame: Self.screenFrame, identifier: "controls", children: [
                            AXNode(type: "StaticText", frame: Self.screenFrame, label: "PIN", identifier: "pin-set"),
                        ]),
                    ]),
                ]),
            ]),
        ])

        let outcome = ExpectedScreenCheck.outcome(for: [tree], expect: "pin-set", instead: .captured)

        #expect(outcome == .unexpectedScreen(
            expected: "pin-set",
            found: ["parent > controls"],
            reason: "\(Self.deepestClause("controls")). 'pin-set' is on a StaticText inside 'controls', not a screen container: expect 'controls' and end the route with scrollTo 'pin-set' to require the element"
        ))
    }

    /// With nothing nested every identifier is deepest and the first in tree order is the whole entry, with no clause.
    @Test
    func siblingIdentifiersThatDoNotNestGiveTheFirstAloneAndNoClause() {
        let tree = AXNode(type: "Application", frame: Self.screenFrame, children: [
            AXNode(type: "Other", frame: Self.screenFrame, identifier: "first"),
            AXNode(type: "Other", frame: Self.screenFrame, identifier: "second"),
        ])

        let outcome = ExpectedScreenCheck.outcome(for: [tree], expect: "missing", instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "missing", found: ["first"]))
    }

    /// The deepest-identifier clause follows a navigation-bar-title hint and precedes what `intended` already said.
    @Test
    func theDeepestClauseComposesWithAnExistingReason() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.hostedScreen()], expect: "missing", instead: .stateNotApplied(reason: "no dark"))

        #expect(outcome == .unexpectedScreen(expected: "missing", found: ["outer > inner"], reason: "\(Self.deepestClause("inner")). no dark"))
    }

    private static func deepestClause(_ identifier: String) -> String {
        "the deepest identifier is '\(identifier)'; an identifier set on a container replaces those of the views inside it"
    }

    /// An element's identifier inside the content is never an anchor, nested or not.
    @Test
    func aNestedElementIdentifierIsNotAnAnchor() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.hostedScreen()], expect: "inner-button", instead: .captured)

        #expect(outcome == .unexpectedScreen(
            expected: "inner-button",
            found: ["outer > inner"],
            reason: "\(Self.deepestClause("inner")). 'inner-button' is on a Button inside 'inner', not a screen container: expect 'inner' and end the route with scrollTo 'inner-button' to require the element"
        ))
    }

    /// `outer` > `Other` `inner` > a `Button` `inner-button`.
    private static func hostedScreen() -> AXNode {
        AXNode(type: "Application", frame: screenFrame, children: [
            AXNode(type: "ScrollView", frame: screenFrame, identifier: "outer", children: [
                AXNode(type: "Other", frame: screenFrame, identifier: "inner", children: [
                    AXNode(type: "Button", frame: screenFrame, label: "Go", identifier: "inner-button"),
                ]),
            ]),
        ])
    }

    /// A verdict that files nothing is not something a mismatch can be about.
    @Test
    func anUnreachableScreenIsLeftAloneWhateverTreesArriveBesideIt() {
        let unreachable = ScreenOutcome.unreachable(routeTried: [.tab(label: "Activity")])

        #expect(ExpectedScreenCheck.outcome(for: [Self.screen(identifier: "workouts-list")], expect: "activity-detail", instead: unreachable) == unreachable)
    }

    /// SimWalk#284: an `expect` naming a text's identifier is refused for what it is — the refusal names the element and the screen identifier to write.
    @Test
    func anExpectationNamingAnElementInsideAContainerSaysSoAndNamesTheContainer() {
        let outcome = ExpectedScreenCheck.outcome(for: [Self.screenWithText(identifier: "lesson.warmUp")], expect: "lesson.warmUp", instead: .captured)

        #expect(outcome == .unexpectedScreen(
            expected: "lesson.warmUp",
            found: ["lesson-answer"],
            reason: "'lesson.warmUp' is on a StaticText inside 'lesson-answer', not a screen container: expect 'lesson-answer' and end the route with scrollTo 'lesson.warmUp' to require the element"
        ))
    }

    /// Chrome is no candidate: a toolbar button's identifier stays silent.
    @Test
    func anExpectationNamingAToolbarButtonGetsNoElementClause() {
        let tree = AXNode(type: "Application", frame: Self.screenFrame, children: [
            AXNode(type: "ScrollView", frame: Self.screenFrame, identifier: "lesson-answer"),
            AXNode(type: "Toolbar", frame: Self.screenFrame, children: [
                AXNode(type: "Button", frame: Self.screenFrame, identifier: "lesson.warmUp"),
            ]),
        ])
        let outcome = ExpectedScreenCheck.outcome(for: [tree], expect: "lesson.warmUp", instead: .captured)

        #expect(outcome == .unexpectedScreen(expected: "lesson.warmUp", found: ["lesson-answer"]))
    }

    static func screenWithText(identifier: String) -> AXNode {
        AXNode(type: "Application", frame: screenFrame, children: [
            AXNode(type: "ScrollView", frame: screenFrame, identifier: "lesson-answer", children: [
                AXNode(type: "StaticText", frame: screenFrame, label: "Warm up", identifier: identifier),
            ]),
        ])
    }

    private static let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    /// A real capture's shape: `Application` (the root `app.snapshot()` always returns, and which never carries an identifier) nested seventeen levels deep before reaching the node an app actually sets one on — matching the depth measured on the real `app.simwalk/screens/you/light` tree.
    private static func screen(identifier: String?) -> AXNode {
        AXNode(type: "Application", frame: screenFrame, label: "RouteFixture", children: [nested(depth: 17, identifier: identifier)])
    }

    private static func nested(depth: Int, identifier: String?) -> AXNode {
        guard depth > 0 else {
            return AXNode(type: "ScrollView", frame: screenFrame, identifier: identifier)
        }
        return AXNode(type: "Other", frame: screenFrame, children: [nested(depth: depth - 1, identifier: identifier)])
    }
}
