//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// SimWalk#10: an unrecognised key in a walkbook step or state used to decode silently.
///
/// `{"theme":"light","textSize":"accessibility5"}` filed the device's default size under a slug asserting `accessibility5`, and `walk` reported `0 state-not-applied` because nothing had asked the runner to apply an axis it never saw. A step's own payload has the identical hole (a `tap` typo'd as `{"tabl":{"label":"Progress"}}` decodes as a step naming no label), so both refuse now.
struct StrictKeyDecodingTests {
    @Test
    func amisspelledStateKeyRefusesNamingItAndTheNearestKnownOne() throws {
        let json = #"{"theme":"light","textSize":"accessibility5"}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("textSize"))
        #expect(sentence.contains("dynamicTypeSize"))
    }

    @Test
    func astateNamingOnlyKnownKeysDecodesCleanly() throws {
        let json = #"{"theme":"dark","dynamicTypeSize":"UICTContentSizeCategoryAccessibilityXL","locale":"en_GB"}"#

        let decoded = try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))

        #expect(decoded == Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityXL", locale: "en_GB"))
    }

    @Test
    func astateMissingItsRequiredThemeStillNamesTheMissingKey() throws {
        let json = #"{"locale":"en_GB"}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("theme"))
    }

    @Test
    func amisspelledRouteStepFieldRefusesNamingItAndTheNearestKnownOne() throws {
        let json = #"{"tab":{"labl":"Progress"}}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("labl"))
        #expect(sentence.contains("label"))
    }

    /// `type` is the one step with two fields, so a typo on either has its own nearest match.
    @Test
    func amisspelledTypeStepTextFieldNamesTextAsTheNearestKey() throws {
        let json = #"{"type":{"label":"Search","txt":"resting"}}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("txt"))
        #expect(sentence.contains("text"))
    }

    /// `openURL` takes one key, so a transposed `ulr` names `url` as the near miss.
    @Test
    func amisspelledOpenURLFieldNamesURLAsTheNearestKey() throws {
        let json = #"{"openURL":{"ulr":"simwalk-fixture://detail"}}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("ulr"))
        #expect(sentence.contains("url"))
    }

    /// `back` takes no keys at all, so an extra one has nothing to be a near miss of — it is refused on its own terms rather than offered a suggestion that would be a guess.
    @Test
    func aBackStepCarryingAnyKeyRefusesRatherThanIgnoringIt() throws {
        let json = #"{"back":{"label":"Progress"}}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("label"))
    }

    /// The exact shapes the README documents, still decoding: strictness closes a hole, it does not narrow the vocabulary.
    @Test
    func everyDocumentedRouteStepShapeStillDecodes() throws {
        let steps: [(json: String, step: Walkbook.RouteStep)] = [
            (#"{"tab":{"label":"Progress"}}"#, .tab(label: "Progress")),
            (#"{"tap":{"label":"Heart"}}"#, .tap(label: "Heart")),
            (#"{"type":{"label":"Search","text":"resting"}}"#, .type(label: "Search", text: "resting")),
            (#"{"scrollTo":{"label":"Rows"}}"#, .scrollTo(label: "Rows")),
            (#"{"back":{}}"#, .back),
        ]

        for (json, step) in steps {
            #expect(try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8)) == step)
        }
    }

    /// The repo's own shipped fixture is real-world evidence the stricter parse costs it nothing.
    @Test
    func theExampleFixtureStillDecodesUnderTheStricterParse() throws {
        let url = try #require(Bundle.module.url(forResource: "example-walk", withExtension: "json", subdirectory: "Fixtures"))

        #expect(throws: Never.self) {
            try WalkbookLoader.load(contentsOf: url)
        }
    }

    // MARK: - Round 2, finding 2: Screen, Walkbook and a route step's outer object decode strictly too.

    /// The spec's own wording: `expect` misspelled once as `expects` used to decode with `expect` left `nil`, turning the check silently off.
    @Test
    func amisspelledScreenKeyRefusesNamingItAndTheNearestKnownOne() throws {
        let json = #"{"id":"you","route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}],"expects":"you-root"}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.Screen.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("expects"))
        #expect(sentence.contains("expect"))
    }

    /// SimWalk#111: `expectMenu` round-trips, a screen without it encodes without it (so an existing walkbook's hash is unchanged), and the plural is an unknown key.
    @Test
    func expectMenuRoundTripsIsOmittedWhenAbsentAndItsMisspellingIsRefused() throws {
        let json = #"{"id":"menus","route":[{"tab":{"label":"Menus"}}],"states":[{"theme":"light"}],"expectMenu":["Endurance","Walking"]}"#
        let screen = try JSONDecoder().decode(Walkbook.Screen.self, from: Data(json.utf8))

        #expect(screen.expectMenu == ["Endurance", "Walking"])
        #expect(try JSONDecoder().decode(Walkbook.Screen.self, from: JSONEncoder().encode(screen)) == screen)

        let plain = Walkbook.Screen(id: "menus", route: [], states: [Walkbook.CaptureState(theme: .light)])
        #expect(try !String(decoding: JSONEncoder().encode(plain), as: UTF8.self).contains("expectMenu"))

        let misspelled = json.replacingOccurrences(of: "expectMenu", with: "expectMenus")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.Screen.self, from: Data(misspelled.utf8))
        }
    }

    /// `"setle"` for `"settle"`: the same silent-discard shape on a different screen key.
    @Test
    func amisspelledScreenSettleKeyIsRefused() throws {
        let json = #"{"id":"you","route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}],"setle":6000}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.Screen.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("setle"))
        #expect(sentence.contains("settle"))
    }

    /// An unknown key at the walkbook's own top level, beside `name`, `appBundleID` and `screens`.
    @Test
    func anUnknownTopLevelWalkbookKeyIsRefused() throws {
        let json = #"{"name":"w","appBundleID":"com.example.app","screens":[],"walk":true}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.self, from: Data(json.utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("walk"))
    }

    /// The spec's exact wording ("`expect` … on a walkbook step") read literally puts the key beside the case name instead of on the screen — the outer route-step object used to drop it silently because its container was keyed by the case names alone.
    @Test
    func expectMisplacedInsideARouteStepIsRefusedRatherThanDropped() throws {
        let json = #"{"tab":{"label":"You"},"expect":"x"}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("expect"))
    }

    /// A typo'd case name (`tabb`) is refused today, but the message used to name neither the key nor a near miss — this is finding 2's message-quality ask.
    @Test
    func atypoedCaseNameNamesItselfAndItsNearestCaseName() throws {
        let json = #"{"tabb":{"label":"Progress"}}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("tabb"))
        #expect(sentence.contains("tab"))
    }

    /// Two valid case names in one step is not "an unknown key" — it is a step that does not say which of them it is, and the message says so rather than complaining about a key that is not actually wrong.
    @Test
    func aRouteStepNamingTwoCasesAtOnceIsRefused() throws {
        let json = #"{"tab":{"label":"Progress"},"tap":{"label":"Heart"}}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("tab"))
        #expect(sentence.contains("tap"))
    }

    /// An empty route-step object names none of the five cases, and says so rather than complaining about a key that does not exist.
    @Test
    func anEmptyRouteStepObjectNamesNone() throws {
        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data("{}".utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("none"))
    }

    /// Seeded aliases (finding 5): `appearance` is `XCUIDevice.shared.appearance`'s own name for the axis `theme` decodes, and the generic longest-common-substring measure pointed it at `dynamicTypeSize` instead — exactly the wrong direction SimWalk#10 was about.
    @Test
    func appearanceSuggestsThemeRatherThanDynamicTypeSize() throws {
        let json = #"{"appearance":"light"}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("theme"))
    }

    /// `dark` is a `theme`'s own value; the generic measure pointed it at `locale`.
    @Test
    func darkSuggestsThemeRatherThanLocale() throws {
        let json = #"{"dark":true}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("theme"))
    }

    /// Only the first of several unknown keys used to be named — a container with two typos was reported as though it had one.
    @Test
    func everyUnknownKeyInAContainerIsNamedNotOnlyTheFirst() throws {
        let json = #"{"theme":"light","textSize":"accessibility5","setle":6000}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("textSize"))
        #expect(sentence.contains("setle"))
    }

    /// Round 3 nit: a key sharing only a letter with everything this container takes has no near miss, and suggesting the least-far one (`version` → `screens`) sends a reader into a second error.
    @Test(arguments: [
        ("version", ["name", "appBundleID", "screens"]),
        ("language", ["theme", "dynamicTypeSize", "locale"]),
        ("x", ["id", "route", "states", "settle", "expect", "notes"]),
    ])
    func akeyWithNoNearMissIsOfferedNone(key: String, known: [String]) {
        #expect(StrictKeyDecoding.nearest(to: key, among: known) == nil)
    }

    /// Every typo this format has been seen with still gets its match through the floor.
    @Test(arguments: [
        ("them", "theme"), ("labl", "label"), ("tabb", "tab"), ("nam", "name"), ("rout", "route"),
        ("setle", "settle"), ("txt", "text"), ("textSize", "dynamicTypeSize"), ("expects", "expect"),
    ])
    func everySeenTypoStillGetsItsMatch(key: String, meant: String) {
        let vocabularies = [
            ["name", "appBundleID", "screens"], ["id", "route", "states", "settle", "expect", "notes"],
            ["theme", "dynamicTypeSize", "locale"], ["label", "text"], ["tab", "tap", "type", "scrollTo", "back"],
        ]
        let known = vocabularies.first { $0.contains(meant) } ?? []

        #expect(StrictKeyDecoding.nearest(to: key, among: known) == meant)
    }

    /// The same on a bare decode: no suggestion clause at all, rather than a far one.
    @Test
    func anUnknownKeyWithNoNearMissIsNamedWithoutASuggestion() throws {
        let json = #"{"name":"w","appBundleID":"com.example.app","screens":[],"version":2}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("'version'"))
        #expect(!sentence.contains("did you mean"))
    }

    /// Round 3 nit: `expect` beside a step's case name drew "did you mean 'type'?" — it is told where it belongs instead.
    @Test
    func expectBesideACaseNameIsToldItBelongsOnTheScreen() throws {
        let json = #"{"tab":{"label":"You"},"expect":"x"}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("'expect' (it belongs on the screen"))
        #expect(!sentence.contains("did you mean"))
    }

    /// A well-formed JSON document that merely names a key this format does not recognise is not "malformed JSON" — only Foundation's own parse failures earn that word.
    @Test
    func anUnknownKeyIsNotReportedAsMalformedJSON() throws {
        let json = #"{"theme":"light","textSize":"accessibility5"}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))
        })

        #expect(!DecodingReason.sentence(for: thrown).contains("malformed JSON"))
    }

    /// Genuinely torn bytes are still reported as malformed JSON — the wording split is about which case earns the word, not about removing it.
    @Test
    func tornBytesAreStillReportedAsMalformedJSON() throws {
        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.self, from: Data("{ not json".utf8))
        })

        #expect(DecodingReason.sentence(for: thrown).contains("malformed JSON"))
    }

    /// A value its field cannot take is Foundation's `dataCorrupted` with no `underlyingError` — the JSON parsed — so it reads as Foundation's own sentence at its path, never as malformed JSON.
    @Test
    func avalueItsFieldCannotTakeIsNotReportedAsMalformedJSON() throws {
        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(#"{"theme":"purple"}"#.utf8))
        })
        guard case let .dataCorrupted(context) = thrown else {
            Issue.record("expected Foundation's dataCorrupted, got \(thrown)")
            return
        }

        #expect(context.underlyingError == nil)
        #expect(!DecodingReason.sentence(for: thrown).contains("malformed JSON"))
        #expect(DecodingReason.sentence(for: thrown).contains("purple"))
    }

    @Test
    func aMisspelledBudgetKeyRefusesNamingItAndTheNearestKnownOne() throws {
        let json = #"{"settleMS":1500}"#

        let thrown = try #require(#expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Walkbook.Budgets.self, from: Data(json.utf8))
        })

        let sentence = DecodingReason.sentence(for: thrown)

        #expect(sentence.contains("settleMS"))
        #expect(sentence.contains("settleMs"))
    }

    @Test
    func aScreenKnowsItsBudgetsAndDecodesBothKeys() throws {
        let json = #"{"id":"a","route":[],"states":[{"theme":"light"}],"budgets":{"settleMs":1500,"layoutShifts":0}}"#

        let decoded = try JSONDecoder().decode(Walkbook.Screen.self, from: Data(json.utf8))

        #expect(decoded.budgets == Walkbook.Budgets(settleMs: 1500, layoutShifts: 0))
    }
}
