//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Validation is the first honest refusal a walkbook meets, so each problem must name its subject — a verdict of "invalid" tells an author nothing they did not already know.
struct WalkbookValidationTests {
    @Test
    func aValidWalkbookProducesNoProblems() {
        #expect(WalkbookLoader.problems(in: Self.valid()).isEmpty)
    }

    @Test
    func duplicateScreenIDsAreReportedOnceWithTheirCount() {
        var book = Self.valid()
        book.screens.append(book.screens[0])
        book.screens.append(book.screens[0])

        #expect(WalkbookLoader.problems(in: book) == [.duplicateScreenID(id: "today", occurrences: 3)])
    }

    @Test
    func anEmptyScreensListIsReported() {
        var book = Self.valid()
        book.screens = []

        #expect(WalkbookLoader.problems(in: book) == [.noScreens])
    }

    @Test
    func anEmptyRouteIsReportedAgainstItsScreen() {
        var book = Self.valid()
        book.screens[0].route = []

        #expect(WalkbookLoader.problems(in: book) == [.emptyRoute(screenID: "today", index: 0)])
    }

    @Test
    func aBlankRouteStepLabelIsReportedWithItsPosition() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tap(label: "  ")]

        #expect(WalkbookLoader.problems(in: book) == [.blankRouteStepLabel(screenID: "today", index: 0, stepIndex: 1)])
    }

    /// A `type` step carries two payloads and both can be blank; the field it names is caught by the label rule, and this is the other half.
    @Test
    func atypeStepWithABlankLabelIsReportedWithItsPosition() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .type(label: " ", text: "resting")]

        #expect(WalkbookLoader.problems(in: book) == [.blankRouteStepLabel(screenID: "today", index: 0, stepIndex: 1)])
    }

    /// Typing nothing is not "clear the field": it taps, types nothing, and reports the step as landed — the silent discard every state axis is refused for.
    @Test
    func atypeStepThatWouldTypeNothingIsReportedWithItsPosition() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .type(label: "Search", text: "")]

        #expect(WalkbookLoader.problems(in: book) == [.blankTypedText(screenID: "today", index: 0, stepIndex: 1)])
    }

    /// A space is text — it goes into the field and it is what a search sees — so only genuine emptiness is refused.
    @Test
    func atypeStepCarryingRealTextIsAccepted() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .type(label: "Search", text: "resting")]

        #expect(WalkbookLoader.problems(in: book).isEmpty)
    }

    /// A screen's own quiet period is refused where `--settle 0` is refused, and for the same reason: the runner would fall back to the walk's default and nothing anywhere would say the key had been ignored.
    @Test
    func aNonPositiveScreenSettleIsRefusedRatherThanDiscarded() {
        var book = Self.valid()
        book.screens[0].settle = 0

        #expect(WalkbookLoader.problems(in: book) == [.nonPositiveSettle(screenID: "today", index: 0, value: 0)])

        book.screens[0].settle = -1
        #expect(WalkbookLoader.problems(in: book) == [.nonPositiveSettle(screenID: "today", index: 0, value: -1)])
    }

    @Test
    func aScreenStatingItsOwnQuietPeriodIsAccepted() {
        var book = Self.valid()
        book.screens[0].settle = 6000

        #expect(WalkbookLoader.problems(in: book).isEmpty)
    }

    /// `expect` that checks nothing is the same failure `--settle 0` is refused for: a value present and unable to do what it claims, rather than the absence that honestly checks nothing.
    @Test
    func aBlankExpectIsRefusedRatherThanDiscarded() {
        var book = Self.valid()
        book.screens[0].expect = "  "

        #expect(WalkbookLoader.problems(in: book) == [.blankExpect(screenID: "today", index: 0)])
    }

    @Test
    func aScreenStatingExpectIsAccepted() {
        var book = Self.valid()
        book.screens[0].expect = "today-root"

        #expect(WalkbookLoader.problems(in: book).isEmpty)
    }

    /// Round 2 nit: no captured screen identifier will ever carry a leading or trailing space, so a padded `expect` can never satisfy the exact match it asks for — the same failure shape as a blank one, refused rather than accepted as though it did something.
    @Test
    func aPaddedExpectIsRefusedRatherThanDiscarded() {
        var book = Self.valid()
        book.screens[0].expect = " today-root "

        #expect(WalkbookLoader.problems(in: book) == [.paddedExpect(screenID: "today", index: 0, value: " today-root ")])
    }

    /// Both forms of a point step, written as the docs show them, are accepted — including the edges of an element's frame (SimWalk#29).
    @Test(arguments: [
        Walkbook.RouteStep.tapPoint(label: "Steps chart", point: [0.8, 0.5]),
        Walkbook.RouteStep.tapPoint(label: "Steps chart", point: [0, 1]),
        Walkbook.RouteStep.tapPoint(label: nil, point: [201, 610]),
    ])
    func apointStepWithinWhatItIsMeasuredAgainstIsAccepted(_ step: Walkbook.RouteStep) {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), step]

        #expect(WalkbookLoader.problems(in: book).isEmpty)
    }

    /// A fraction of an element outside 0…1 lands on whatever is drawn beside it, while the step reports having tapped the element it names.
    @Test(arguments: [[1.2, 0.5], [0.5, -0.1]])
    func apointOutsideItsElementsFrameIsRefused(_ point: [Double]) {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tapPoint(label: "Steps chart", point: point)]

        #expect(WalkbookLoader.problems(in: book) == [
            .tapPointOutsideElement(screenID: "today", index: 0, stepIndex: 1, label: "Steps chart", point: point),
        ])
    }

    /// A NaN, which only a walkbook built in code can carry, fails every comparison — so it is refused for failing the range, not waved through for failing to break it.
    @Test
    func anotANumberPointIsRefusedInBothForms() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tapPoint(label: "Steps chart", point: [.nan, 0.5]), .tapPoint(label: nil, point: [.nan, 610])]

        let found = WalkbookLoader.problems(in: book).map(\.description)

        #expect(found.count == 2)
        #expect(found.first?.contains("outside its frame") == true)
        #expect(found.last?.contains("never negative") == true)
    }

    /// `at` is an x and a y; any other count has no point to tap, with or without an element to measure it against.
    @Test(arguments: [[Double](), [0.5], [0.5, 0.5, 0.5]])
    func apointThatIsNotTwoNumbersIsRefused(_ point: [Double]) {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tapPoint(label: "Steps chart", point: point), .tapPoint(label: nil, point: point)]

        #expect(WalkbookLoader.problems(in: book) == [
            .malformedTapPoint(screenID: "today", index: 0, stepIndex: 1, count: point.count),
            .malformedTapPoint(screenID: "today", index: 0, stepIndex: 2, count: point.count),
        ])
    }

    /// An `openURL` URL that does not parse, or parses without a scheme, has nothing to be handed to (checked with a well-formed one beside it, which is not reported).
    @Test(arguments: ["not a url", "detail", "/detail", ""])
    func anOpenURLWithNoSchemeIsRefused(_ url: String) {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .openURL(url: url), .openURL(url: "simwalk-fixture://detail")]

        #expect(WalkbookLoader.problems(in: book) == [.unopenableURL(screenID: "today", index: 0, stepIndex: 1, url: url)])
    }

    /// The refusal names the screen, the step and the URL, and `openURL` names no element label, so it is not also a blank label.
    @Test
    func anUnopenableURLIsNamedByScreenStepAndURL() {
        let problem = WalkbookProblem.unopenableURL(screenID: "today", index: 0, stepIndex: 1, url: "not a url")

        #expect(problem.description.contains("screen 'today' route step 1"))
        #expect(problem.description.contains("'not a url'"))
    }

    /// A screen point is never negative; one beyond the far edges is the walk's to refuse, since `validate` does not know the device.
    @Test
    func anegativeScreenPointIsRefusedAndAFarOneIsLeftToTheWalk() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tapPoint(label: nil, point: [-1, 610]), .tapPoint(label: nil, point: [5000, 5000])]

        #expect(WalkbookLoader.problems(in: book) == [.tapPointOffScreen(screenID: "today", index: 0, stepIndex: 1, point: [-1, 610])])
    }

    /// Written without a `label`, both coordinates below 1 reads as a fraction meant to measure an element's frame with the `label` that would have made it one left off — never a plausible screen point on a real device (SimWalk#29 review, item 2).
    @Test
    func afractionalPointWithNoLabelIsRefused() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tapPoint(label: nil, point: [0.8, 0.5])]

        #expect(WalkbookLoader.problems(in: book) == [
            .tapPointFractionalWithoutLabel(screenID: "today", index: 0, stepIndex: 1, point: [0.8, 0.5]),
        ])
    }

    /// A fraction of exactly 1 is still a fraction: `[1, 0.5]` without its label is the right edge of an element, not a screen point beside the status bar.
    @Test
    func afractionOfExactlyOneWithNoLabelIsRefused() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tapPoint(label: nil, point: [1, 0.5])]

        #expect(WalkbookLoader.problems(in: book) == [
            .tapPointFractionalWithoutLabel(screenID: "today", index: 0, stepIndex: 1, point: [1, 0.5]),
        ])
    }

    /// A point step's element is named like any other step's, so a blank one is caught by the same rule.
    @Test
    func apointStepWithABlankLabelIsReportedWithItsPosition() {
        var book = Self.valid()
        book.screens[0].route = [.tab(label: "Today"), .tapPoint(label: " ", point: [0.5, 0.5])]

        #expect(WalkbookLoader.problems(in: book) == [.blankRouteStepLabel(screenID: "today", index: 0, stepIndex: 1)])
    }

    @Test
    func aScreenWithNoCaptureStatesIsReported() {
        var book = Self.valid()
        book.screens[0].states = []

        #expect(WalkbookLoader.problems(in: book) == [.noCaptureStates(screenID: "today", index: 0)])
    }

    @Test
    func aStateRequestedTwiceIsReportedOnceUnderItsBundleSlug() {
        var book = Self.valid()
        book.screens[0].states = Array(
            repeating: Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityXL"),
            count: 3
        )

        #expect(WalkbookLoader.problems(in: book) == [
            .duplicateCaptureState(screenID: "today", index: 0, slug: "dark-dt_uictcontentsizecategoryaccessibilityxl"),
        ])
    }

    @Test
    func aBlankNameAndBundleIDAreBothReported() {
        var book = Self.valid()
        book.name = " "
        book.appBundleID = ""

        #expect(WalkbookLoader.problems(in: book) == [.blankWalkName, .blankAppBundleID])
    }

    @Test
    func everyProblemIsReportedTogetherRatherThanOnlyTheFirst() {
        var book = Self.valid()
        book.name = ""
        book.screens[0].route = []
        book.screens[0].states = []

        #expect(WalkbookLoader.problems(in: book).count == 3)
    }

    @Test
    func loadingInvalidBytesRefusesNamingTheSourceAndEveryProblem() throws {
        var book = Self.valid()
        book.screens[0].route = []
        let data = try JSONEncoder().encode(book)

        #expect(throws: WalkbookLoadError.invalid(source: "memory", problems: [.emptyRoute(screenID: "today", index: 0)])) {
            try WalkbookLoader.load(from: data, source: "memory")
        }
    }

    /// Round 2, finding 5: an unknown key used to abort the whole decode, so `emptyRoute` beside it was never listed — the two now come back together in one `.invalid` refusal.
    @Test
    func loadingBytesWithAnUnknownKeyAndAStructuralProblemReportsBothTogether() throws {
        let json = #"""
        {"name":"example-validation","appBundleID":"dev.simwalk.route-fixture","screens":[
          {"id":"today","route":[],"states":[{"theme":"light"}],"setle":6000}
        ]}
        """#

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "memory")
        })
        guard case let .invalid(source, problems) = thrown else {
            Issue.record("expected an invalid refusal listing both problems, got \(thrown)")
            return
        }

        #expect(source == "memory")
        #expect(problems.contains(.emptyRoute(screenID: "today", index: 0)))
        #expect(problems.contains {
            if case .unknownKey(_, "setle", _) = $0 {
                true
            } else {
                false
            }
        })
    }

    /// The same interaction, direct: a screen's unrecognised key is reported by `problems(in:)`-shaped output via `load`, naming the key, its location and the nearest one it is probably meant as.
    @Test
    func anUnknownKeyNamesItsPathAndNearestMatch() throws {
        let json = #"""
        {"name":"example-validation","appBundleID":"dev.simwalk.route-fixture","screens":[
          {"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}],"expects":"today-root"}
        ]}
        """#

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "memory")
        })
        guard case let .invalid(_, problems) = thrown else {
            Issue.record("expected an invalid refusal, got \(thrown)")
            return
        }

        #expect(problems == [.unknownKey(path: "screens[0]", key: "expects", suggestion: "expect")])
    }

    /// A direct `JSONDecoder().decode(Walkbook.self, …)` — no sink installed — still refuses immediately on an unknown key, exactly as every `StrictKeyDecodingTests` case relies on; only `WalkbookLoader.load` softens it into a collected problem.
    @Test
    func decodingDirectlyWithNoSinkStillThrowsOnAnUnknownKey() throws {
        let json = #"{"name":"w","appBundleID":"com.example.app","screens":[],"walk":true}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.self, from: Data(json.utf8))
        }
    }

    @Test
    func loadingMalformedJSONRefusesAsMalformedRatherThanAsInvalid() throws {
        let data = Data("{ not json".utf8)

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: data, source: "torn.json")
        })
        guard case let .malformed(source, _) = thrown else {
            Issue.record("expected a malformed refusal, got \(thrown)")
            return
        }

        #expect(source == "torn.json")
    }

    @Test
    func loadingJSONMissingARequiredKeyNamesTheKey() throws {
        let data = Data(#"{"name":"w","screens":[]}"#.utf8)

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: data, source: "partial.json")
        })

        #expect(thrown.description.contains("appBundleID"))
    }

    @Test
    func loadingAMissingFileRefusesAsUnreadableNamingThePath() throws {
        let url = URL(fileURLWithPath: "/nonexistent/simwalk/absent.json")

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(contentsOf: url)
        })
        guard case let .unreadable(source, _) = thrown else {
            Issue.record("expected an unreadable refusal, got \(thrown)")
            return
        }

        #expect(source == url.path)
    }

    @Test
    func aStateSlugCannotIntroduceAPathSeparator() {
        let state = Walkbook.CaptureState(theme: .light, dynamicTypeSize: "../escape", locale: "en_GB")

        #expect(state.slug == "light-dt____escape-loc_en_gb")
    }

    @Test
    func screenIDsThatDifferOnlyByCaseAreReportedAsACollision() {
        var book = Self.valid()
        var other = book.screens[0]
        other.id = "Today"
        book.screens.append(other)

        #expect(WalkbookLoader.problems(in: book) == [.collidingScreenIDs(slug: "today", ids: ["Today", "today"])])
    }

    @Test
    func screenIDsThatDifferOnlyByPunctuationAreReportedAsACollision() {
        var book = Self.valid()
        var other = book.screens[0]
        other.id = "to-day"
        book.screens[0].id = "to_day"
        book.screens.append(other)

        #expect(WalkbookLoader.problems(in: book) == [.collidingScreenIDs(slug: "to_day", ids: ["to-day", "to_day"])])
    }

    /// The collision check used to slug the *trimmed* id while every on-disk path slugs the raw one, so this pair validated, ran a whole simulator pass, and was refused only by `finalise` — which discards the bundle it just spent the walk producing.
    @Test
    func screenIDsCollidingOnlyOnceTheirWhitespaceIsSluggedAreReportedBeforeTheWalk() {
        var book = Self.valid()
        var other = book.screens[0]
        other.id = "_today"
        book.screens[0].id = " today"
        book.screens.append(other)

        #expect(WalkbookLoader.problems(in: book) == [.collidingScreenIDs(slug: "_today", ids: [" today", "_today"])])
    }

    @Test
    func aScreenIDThatWouldClimbOutOfTheBundleStillFilesInsideIt() {
        let slug = CaptureBundleLayout.screenSlug("../../../../tmp/simwalk-pwned")

        #expect(!slug.contains("/"))
        #expect(!slug.contains("."))
    }

    @Test
    func aProblemAgainstABlankScreenIDNamesItsPositionRatherThanEmptyQuotes() {
        var book = Self.valid()
        book.screens[0].id = ""
        book.screens[0].route = []

        let rendered = WalkbookLoader.problems(in: book).map(\.description).joined(separator: "\n")

        #expect(rendered.contains("screen at index 0 has a blank id"))
        #expect(rendered.contains("screen at index 0 has an empty route"))
        #expect(!rendered.contains("screen ''"))
    }

    @Test
    func aDynamicTypeSizeTheSimulatorWouldDiscardIsRefusedRatherThanCaptured() {
        var book = Self.valid()
        book.screens[0].states = [Walkbook.CaptureState(theme: .light, dynamicTypeSize: "accessibility2")]

        #expect(WalkbookLoader.problems(in: book) == [
            .unknownDynamicTypeSize(
                screenID: "today",
                index: 0,
                value: "accessibility2",
                suggestion: "UICTContentSizeCategoryAccessibilityL"
            ),
        ])
    }

    @Test
    func aLocaleTheSimulatorWouldDiscardIsRefusedRatherThanCaptured() {
        var book = Self.valid()
        book.screens[0].states = [Walkbook.CaptureState(theme: .light, locale: "zz_NONSENSE")]

        #expect(WalkbookLoader.problems(in: book) == [
            .unknownLocale(screenID: "today", index: 0, value: "zz_NONSENSE", suggestion: nil),
        ])
    }

    /// The spellings that actually reached a simulator, pinned so the accepted set can never narrow beneath the walkbook this repo ships.
    @Test(arguments: [
        Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL"),
        Walkbook.CaptureState(theme: .light, dynamicTypeSize: "UICTContentSizeCategoryXS"),
        Walkbook.CaptureState(theme: .light, locale: "en_GB"),
        Walkbook.CaptureState(theme: .light, locale: "fr_FR"),
        Walkbook.CaptureState(theme: .light, locale: "zh_Hans_CN"),
    ])
    func anHonouredStateValidates(state: Walkbook.CaptureState) {
        var book = Self.valid()
        book.screens[0].states = [state]

        #expect(WalkbookLoader.problems(in: book).isEmpty)
    }

    /// One mistake, made once, reported once — however many states repeat it.
    @Test
    func oneOffendingValueSpreadAcrossStatesIsReportedOnce() {
        var book = Self.valid()
        book.screens[0].states = [
            Walkbook.CaptureState(theme: .light, dynamicTypeSize: "accessibility3"),
            Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "accessibility3"),
        ]

        #expect(WalkbookLoader.problems(in: book) == [
            .unknownDynamicTypeSize(
                screenID: "today",
                index: 0,
                value: "accessibility3",
                suggestion: "UICTContentSizeCategoryAccessibilityXL"
            ),
        ])
    }

    /// A near miss earns the value the author meant; anything else earns silence, since a wrong suggestion is followed.
    @Test
    func aNearMissIsNamedAndAGenuineUnknownIsNot() {
        #expect(ContentSizeCategoryName.suggestion(for: "accessibility3") == "UICTContentSizeCategoryAccessibilityXL")
        #expect(ContentSizeCategoryName.suggestion(for: "uictcontentsizecategoryxl") == "UICTContentSizeCategoryXL")
        #expect(ContentSizeCategoryName.suggestion(for: "enormous") == nil)
        #expect(LocaleIdentifierName.suggestion(for: "en-GB") == "en_GB")
        #expect(LocaleIdentifierName.suggestion(for: "zz_NONSENSE") == nil)
    }

    /// SwiftUI's spelling is a refusal, never an alias — accepting it silently is how the two stayed confusable.
    @Test
    func theSwiftUISpellingIsRejectedEvenThoughItsMeaningIsKnown() {
        #expect(!ContentSizeCategoryName.isValid("accessibility2"))
        #expect(ContentSizeCategoryName.isValid("UICTContentSizeCategoryAccessibilityL"))
    }

    private static func valid() -> Walkbook {
        Walkbook(
            name: "example-validation",
            appBundleID: "dev.simwalk.route-fixture",
            screens: [
                Walkbook.Screen(
                    id: "today",
                    route: [.tab(label: "Today")],
                    states: [Walkbook.CaptureState(theme: .light), Walkbook.CaptureState(theme: .dark)]
                ),
            ]
        )
    }

    @Test
    func aBudgetsObjectWithNeitherKeyIsRefused() {
        var book = Self.valid()
        book.screens[0].budgets = Walkbook.Budgets()

        #expect(WalkbookLoader.problems(in: book) == [.emptyBudgets(screenID: "today", index: 0)])
    }

    @Test
    func aNegativeBudgetIsRefusedNamingItsKeyAndZeroIsAccepted() {
        var book = Self.valid()
        book.screens[0].budgets = Walkbook.Budgets(settleMs: -1, layoutShifts: 0)

        #expect(WalkbookLoader.problems(in: book) == [.negativeBudget(screenID: "today", index: 0, key: "settleMs", value: -1)])

        book.screens[0].budgets = Walkbook.Budgets(settleMs: 0, layoutShifts: -2)
        #expect(WalkbookLoader.problems(in: book) == [.negativeBudget(screenID: "today", index: 0, key: "layoutShifts", value: -2)])

        book.screens[0].budgets = Walkbook.Budgets(settleMs: 0, layoutShifts: 0)
        #expect(WalkbookLoader.problems(in: book).isEmpty)
    }
}
