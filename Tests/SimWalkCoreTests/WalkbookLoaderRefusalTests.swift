//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// Round 3, finding 1, and round 4, finding 2: what `validate` says, through `WalkbookLoader.load` — the path the CLI, the MCP face and the runner all take.
///
/// A misspelled *required* key is both an unknown key and a missing one. The loader used to refuse on the missing key alone — `missing key 'theme'`, never naming the `them` actually written — and discard every other problem collected before it (round 3); then it named both, but the missing key still stopped the decode, so nothing after it was listed (round 4). Now both are recorded, a placeholder is decoded past, and every problem in the walkbook is listed together. Every naming test before these decoded with a plain `JSONDecoder`, which is not the path any user is on.
struct WalkbookLoaderRefusalTests {
    @Test
    func amisspelledRequiredStateKeyIsNamedBesideTheKeyItLeavesMissing() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"them":"light"}]}"#)

        #expect(problems == [
            .unknownKey(path: "screens[0].states[0]", key: "them", suggestion: "theme"),
            .missingKey(path: "screens[0].states[0]", key: "theme"),
        ])
    }

    /// The placeholder standing in for the missing `route` is never checked as though it were written: no `emptyRoute` beside it.
    @Test
    func amisspelledRouteIsNamedBesideTheKeyItLeavesMissing() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","rout":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [
            .unknownKey(path: "screens[0]", key: "rout", suggestion: "route"),
            .missingKey(path: "screens[0]", key: "route"),
        ])
    }

    /// A `tapPoint`'s own point key is `at`, not `point` — the likelier slip given the step's name — and an unknown key there is named beside the `at` it leaves missing, exactly as any other step's is (SimWalk#29 review, item 4).
    @Test
    func amisspelledTapPointAtKeyIsNamedBesideTheKeyItLeavesMissing() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","route":[{"tab":{"label":"Today"}},{"tapPoint":{"label":"Steps chart","point":[0.8,0.5]}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [
            .unknownKey(path: "screens[0].route[1].tapPoint", key: "point", suggestion: nil),
            .missingKey(path: "screens[0].route[1].tapPoint", key: "at"),
        ])
    }

    /// A misspelled step label is a named refusal.
    @Test
    func amisspelledStepLabelIsNamedBesideTheKeyItLeavesMissing() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","route":[{"tab":{"labl":"Today"}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [
            .unknownKey(path: "screens[0].route[0].tab", key: "labl", suggestion: "label"),
            .missingKey(path: "screens[0].route[0].tab", key: "label"),
        ])
    }

    @Test
    func amisspelledWalkNameIsNamedBesideTheKeyItLeavesMissing() throws {
        let json = #"{"nam":"example","appBundleID":"com.example.app","screens":[]}"#

        let problems = try Self.refusal(json: json)

        #expect(problems == [
            .unknownKey(path: "", key: "nam", suggestion: "name"),
            .missingKey(path: "", key: "name"),
        ])
    }

    /// Round 4, finding 2, as reproduced: a misspelled case name in one screen, a misspelled required key beside it, and a misspelled route on the next screen — all three listed, where the case name used to stop the listing at itself.
    @Test
    func everyMisspellingInTheWalkbookIsListedTogether() throws {
        let json = #"""
        {"name":"example","appBundleID":"com.example.app","screens":[
          {"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}]},
          {"id":"week","route":[{"tab":{"label":"Progress"}},{"tabb":{"label":"Week"}}],"states":[{"them":"dark"}]},
          {"id":"you","rout":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}]}
        ]}
        """#

        let problems = try Self.refusal(json: json)

        #expect(problems == [
            .unknownKey(path: "screens[1].route[1]", key: "tabb", suggestion: "tab"),
            .routeStepNotOneStep(path: "screens[1].route[1]", names: []),
            .unknownKey(path: "screens[1].states[0]", key: "them", suggestion: "theme"),
            .missingKey(path: "screens[1].states[0]", key: "theme"),
            .unknownKey(path: "screens[2]", key: "rout", suggestion: "route"),
            .missingKey(path: "screens[2]", key: "route"),
        ])
    }

    /// A step naming two steps is listed and decoded past the same way, naming both in the format's own order.
    @Test
    func astepNamingTwoStepsIsListedAndDecodedPast() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","route":[{"tap":{"label":"Row"},"tab":{"label":"Today"}}],"states":[{"them":"light"}]}"#)

        #expect(problems == [
            .routeStepNotOneStep(path: "screens[0].route[0]", names: ["tab", "tap"]),
            .unknownKey(path: "screens[0].states[0]", key: "them", suggestion: "theme"),
            .missingKey(path: "screens[0].states[0]", key: "theme"),
        ])
    }

    /// A value of the wrong type has no placeholder to stand in, so the decode still stops there — and what was collected before it is still listed, the stop last.
    @Test
    func avalueOfTheWrongTypeStillStopsTheDecodeLast() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","setle":1,"settle":"slow","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [
            .unknownKey(path: "screens[0]", key: "setle", suggestion: "settle"),
            .undecodable(reason: "expected Int at screens[0].settle"),
        ])
    }

    /// A misspelled case name no longer stops the decode — a placeholder stands in — and the problems collected before it are still listed, each once: a top-level key with no near match, a screen key with one, and the case name itself.
    @Test
    func amisspelledCaseNameKeepsEveryProblemCollectedBeforeIt() throws {
        let json = #"""
        {"name":"example","appBundleID":"com.example.app","version":2,"screens":[
          {"id":"today","setle":6000,"route":[{"tabb":{"label":"Today"}}],"states":[{"theme":"light"}]}
        ]}
        """#

        let problems = try Self.refusal(json: json)

        #expect(problems == [
            .unknownKey(path: "", key: "version", suggestion: nil),
            .unknownKey(path: "screens[0]", key: "setle", suggestion: "settle"),
            .unknownKey(path: "screens[0].route[0]", key: "tabb", suggestion: "tab"),
            .routeStepNotOneStep(path: "screens[0].route[0]", names: []),
        ])
    }

    /// The refusal as `validate` prints it: one refusal, the key written, the key meant, the key missing, and exactly which screen's checks were not run.
    @Test
    func therefusalAsPrintedNamesTheKeyWrittenAndTheKeyMeant() throws {
        let data = Data(Self.walkbook(screen: #"{"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"them":"light"}]}"#).utf8)

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: data, source: "example.json")
        })

        #expect(thrown.description.contains("unknown key 'them' at screens[0].states[0]; did you mean 'theme'?"))
        #expect(thrown.description.contains("missing key 'theme' at screens[0].states[0]"))
        #expect(thrown.description.hasSuffix("the checks for screen at index 0 were not run — they run once the problems above are fixed"))
    }

    /// Round 5, finding 1: a placeholder in one screen used to hide every other screen's problems behind one blanket line.
    ///
    /// Screen 0's misspelled state key leaves only screen 0's checks unrun — screen 1's empty route and padded `expect`, and screen 2's `{n}` tab and duplicate state, are listed exactly as they would be alone.
    @Test
    func aPlaceholderInOneScreenDoesNotHideProblemsInAnother() throws {
        let json = #"""
        {"name":"example","appBundleID":"com.example.app","screens":[
          {"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"them":"light"}]},
          {"id":"week","route":[],"states":[{"theme":"light"}],"expect":" week-root "},
          {"id":"you","route":[{"tab":{"label":"Week {n}"}}],"states":[{"theme":"light"},{"theme":"light"}]}
        ]}
        """#

        let problems = try Self.refusal(json: json)

        #expect(problems == [
            .unknownKey(path: "screens[0].states[0]", key: "them", suggestion: "theme"),
            .missingKey(path: "screens[0].states[0]", key: "theme"),
            .emptyRoute(screenID: "week", index: 1),
            .paddedExpect(screenID: "week", index: 1, value: " week-root "),
            .placeholderInTabStep(screenID: "you", index: 2, stepIndex: 0, label: "Week {n}"),
            .duplicateCaptureState(screenID: "you", index: 2, slug: "light"),
        ])

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "example.json")
        })
        #expect(thrown.description.hasSuffix("the checks for screen at index 0 were not run — they run once the problems above are fixed"))
    }

    /// Round 6, finding C: the walk-level trailer line had no test naming its wording.
    @Test
    func amissingTopLevelKeyNamesTheWalkLevelTrailer() throws {
        let json = #"{"nam":"example","appBundleID":"com.example.app","screens":[]}"#

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "example.json")
        })

        #expect(thrown.description.hasSuffix("the checks for the walkbook's own name, appBundleID and screens were not run — they run once the problems above are fixed"))
    }

    /// Round 6, finding D: a placeholder screen still takes part in the duplicate-id check with its real id — a misspelled key elsewhere in screen 0 must never hide a genuine duplicate with screen 1.
    @Test
    func aPlaceholderScreenStillCollidesOnItsRealID() throws {
        let json = #"""
        {"name":"example","appBundleID":"com.example.app","screens":[
          {"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"them":"light"}]},
          {"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"dark"}]}
        ]}
        """#

        let problems = try Self.refusal(json: json)

        #expect(problems == [
            .unknownKey(path: "screens[0].states[0]", key: "them", suggestion: "theme"),
            .missingKey(path: "screens[0].states[0]", key: "theme"),
            .duplicateScreenID(id: "today", occurrences: 2),
        ])

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "example.json")
        })
        #expect(thrown.description.hasSuffix("the checks for screen at index 0 were not run — they run once the problems above are fixed"))
    }

    /// Round 4: a missing key nobody misspelled is listed like any other, rather than stopping the decode as `.malformed` — so a second one further down is listed beside it.
    @Test
    func amissingKeyNobodyMisspelledIsListedWithTheRest() throws {
        let problems = try Self.refusal(json: #"""
        {"name":"example","appBundleID":"com.example.app","screens":[
          {"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{}]},
          {"route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}]}
        ]}
        """#)

        #expect(problems == [
            .missingKey(path: "screens[0].states[0]", key: "theme"),
            .missingKey(path: "screens[1]", key: "id"),
        ])
    }

    /// A refusal that ran every check does not claim otherwise.
    @Test
    func arefusalThatRanEveryCheckSaysNothingAboutChecksNotRun() throws {
        let data = Data(Self.walkbook(screen: #"{"id":"today","route":[],"states":[{"theme":"light"}],"setle":1}"#).utf8)

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: data, source: "example.json")
        })

        #expect(!thrown.description.contains("were not run"))
    }

    /// A value its field cannot take, with nothing collected before it, is still what it was: not a walkbook.
    @Test
    func avalueItsFieldCannotTakeAloneIsStillMalformed() throws {
        let data = Data(Self.walkbook(screen: #"{"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"purple"}]}"#).utf8)

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: data, source: "example.json")
        })

        guard case let .malformed(source, reason) = thrown else {
            Issue.record("expected a malformed refusal, got \(thrown)")
            return
        }

        #expect(source == "example.json")
        #expect(reason.hasSuffix("at screens[0].states[0].theme"))
    }

    /// `expect` beside a step's case name — the spec's own phrase read literally — is told where it goes, not offered the nearest step key (`type`).
    @Test
    func expectOnAStepIsToldItBelongsOnTheScreen() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","route":[{"tab":{"label":"Today"},"expect":"today-root"}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [
            .misplacedKey(path: "screens[0].route[0]", key: "expect", belongsOn: "the screen, beside its 'route' and 'states'"),
        ])
    }

    /// SimWalk#119: `expectMenu` on a route step is told where it goes, as `expect` is.
    @Test
    func expectMenuOnAStepIsToldItBelongsOnTheScreen() throws {
        let problems = try Self.refusal(screen: #"{"id":"menus","route":[{"tab":{"label":"Menus"},"expectMenu":["Endurance"]}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [
            .misplacedKey(path: "screens[0].route[0]", key: "expectMenu", belongsOn: "the screen, beside its 'route' and 'states'"),
        ])
    }

    /// Round 3: SwiftUI's hosting class sits on every pushed screen and is never counted as a screen's identifier, so an `expect` naming one could never pass.
    @Test
    func aMangledSwiftNameAsExpectIsRefused() throws {
        let problems = try Self.refusal(screen: #"{"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}],"expect":"_TtGC7SwiftUI32NavigationStackHosting"}"#)

        #expect(problems == [.mangledExpect(screenID: "today", index: 0, value: "_TtGC7SwiftUI32NavigationStackHosting")])
    }

    /// SimWalk#111: an `expectMenu` that is empty, or holds a blank or padded label, could never check anything or never pass.
    @Test
    func anEmptyBlankOrPaddedExpectMenuIsRefused() throws {
        let screen = #"{"id":"menus","route":[{"tab":{"label":"Menus"}}],"states":[{"theme":"light"}],"expectMenu":"#

        #expect(try Self.refusal(screen: screen + "[]}") == [.emptyExpectMenu(screenID: "menus", index: 0)])
        #expect(try Self.refusal(screen: screen + #"["Walking"," "]}"#) == [.blankExpectMenuLabel(screenID: "menus", index: 0, position: 1)])
        #expect(try Self.refusal(screen: screen + #"[" Walking"]}"#) == [.paddedExpectMenuLabel(screenID: "menus", index: 0, position: 0, value: " Walking")])
    }

    /// Round 4, the `{n}` handover: a tab is looked up by its name as it reads, so a placeholder in one can never land.
    @Test
    func aPlaceholderInATabStepIsRefused() throws {
        let problems = try Self.refusal(screen: #"{"id":"week","route":[{"tab":{"label":"Week {n}"}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [.placeholderInTabStep(screenID: "week", index: 0, stepIndex: 0, label: "Week {n}")])
        #expect(problems.first?.description == "screen 'week' route step 0 names tab 'Week {n}' with {n} — a tab is looked up by its name as it reads, so the placeholder never matches and the step is UNREACHABLE; name the tab as it reads")
    }

    /// A system sheet's control is looked up by its label or identifier as it reads, so `{n}` in a `systemTap` can never land either (SimWalk#28 review, item 6).
    @Test
    func aPlaceholderInASystemTapStepIsRefused() throws {
        let problems = try Self.refusal(screen: #"{"id":"asked","route":[{"systemTap":{"label":"Allow {n}"}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [.placeholderInSystemTapStep(screenID: "asked", index: 0, stepIndex: 0, label: "Allow {n}")])
        #expect(problems.first?.description == "screen 'asked' route step 0 names systemTap 'Allow {n}' with {n} — a system sheet's control is looked up by its label or identifier as it reads, so the placeholder never matches and the step is UNREACHABLE; name the control as it reads")
    }

    /// The owner on a `systemTap` is where the runner records which tree it found the control in, so a walkbook writing one is refused (SimWalk#28 review).
    @Test
    func anOwnerWrittenOnASystemTapStepIsRefused() throws {
        let problems = try Self.refusal(screen: #"{"id":"asked","route":[{"systemTap":{"label":"Allow","owner":"springboard"}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [.ownerInSystemTapStep(screenID: "asked", index: 0, stepIndex: 0)])
    }

    /// Declaring `atLaunch` does not make an owner the walkbook's to write (SimWalk#46).
    @Test
    func anOwnerWrittenBesideAtLaunchIsStillRefused() throws {
        let problems = try Self.refusal(screen: #"{"id":"asked","route":[{"systemTap":{"label":"Allow","atLaunch":true,"owner":"appWindow"}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [.ownerInSystemTapStep(screenID: "asked", index: 0, stepIndex: 0)])
    }

    /// `atLaunch` describes the launch, and only a route's first step is taken on the launch's screen, so one declared later is refused naming the step (SimWalk#46).
    @Test
    func atLaunchAfterTheFirstStepIsRefused() throws {
        let problems = try Self.refusal(screen: #"{"id":"asked","route":[{"systemTap":{"label":"UIA.Health.AuthSheet.AllCategoryButton"}},{"systemTap":{"label":"UIA.Health.Allow.Button","atLaunch":true}}],"states":[{"theme":"light"}]}"#)

        #expect(problems == [.atLaunchAfterFirstStep(screenID: "asked", index: 0, stepIndex: 1)])
        #expect(problems.first?.description == "screen 'asked' route step 1 declares a systemTap atLaunch — the declaration says the launch itself raised the sheet, so it can only be a route's first step (step 0); remove it here")
    }

    /// On the first step the declaration loads, and the step carries it.
    @Test
    func atLaunchOnTheFirstStepLoadsClean() throws {
        let walkbook = try WalkbookLoader.load(
            from: Data(Self.walkbook(screen: #"{"id":"asked","route":[{"systemTap":{"label":"UIA.Health.AuthSheet.AllCategoryButton","atLaunch":true}},{"systemTap":{"label":"UIA.Health.Allow.Button"}}],"states":[{"theme":"light"}]}"#).utf8),
            source: "example.json"
        )

        #expect(walkbook.screens[0].route == [
            .systemTap(label: "UIA.Health.AuthSheet.AllCategoryButton", atLaunch: true),
            .systemTap(label: "UIA.Health.Allow.Button"),
        ])
    }

    /// The same placeholder in a `tap` step is the pattern tier's to resolve, and loads clean.
    @Test
    func aPlaceholderInATapStepLoadsClean() throws {
        let walkbook = try WalkbookLoader.load(
            from: Data(Self.walkbook(screen: #"{"id":"week","route":[{"tap":{"label":"Week {n}"}}],"states":[{"theme":"light"}]}"#).utf8),
            source: "example.json"
        )

        #expect(walkbook.screens[0].route == [.tap(label: "Week {n}")])
    }

    /// SimWalk#218: every problem one step can carry is worded for a session without the screen the loader borrows for it.
    ///
    /// `atLaunchAfterFirstStep` is left out: a session step is always step 0, which the check allows.
    @Test
    func everyProblemASessionStepCanCarryIsWordedWithoutTheBorrowedScreen() {
        let steps: [Walkbook.RouteStep] = [
            .tap(label: " "),
            .type(label: "Name", text: "", replace: false),
            .longPress(label: "Row", seconds: 99),
            .swipe(label: nil, direction: "sideways"),
            .tapPoint(label: nil, point: [1]),
            .tapPoint(label: "Chart", point: [2, 0.5]),
            .tapPoint(label: nil, point: [-3, 10]),
            .tapPoint(label: nil, point: [0.5, 0.5]),
            .tab(label: "Week {n}"),
            .systemTap(label: "Allow {n}"),
            .systemTap(label: "Allow", owner: .springboard),
            .openURL(url: "not a url"),
        ]

        for step in steps {
            let refusals = WalkbookLoader.refusals(inSessionStep: step)

            #expect(!refusals.isEmpty, "\(step) carries no problem")
            for refusal in refusals {
                #expect(refusal.hasPrefix("the step "), "\(refusal)")
                #expect(!refusal.contains("session step"), "\(refusal)")
            }
        }
    }

    private static func walkbook(screen: String) -> String {
        #"{"name":"example","appBundleID":"com.example.app","screens":["# + screen + "]}"
    }

    private static func refusal(screen: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [WalkbookProblem] {
        try refusal(json: walkbook(screen: screen), sourceLocation: sourceLocation)
    }

    /// The problems `WalkbookLoader.load` refuses `json` with, recording an issue when it refuses some other way or not at all.
    private static func refusal(json: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [WalkbookProblem] {
        let thrown = try #require(#expect(throws: WalkbookLoadError.self, sourceLocation: sourceLocation) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "example.json")
        }, sourceLocation: sourceLocation)
        guard case let .invalid(_, problems) = thrown else {
            Issue.record("expected one refusal listing every problem, got \(thrown)", sourceLocation: sourceLocation)
            return []
        }
        return problems
    }
}
