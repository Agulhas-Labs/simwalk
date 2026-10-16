//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The walkbook model is the contract every face shares, so it must survive a round trip through its wire format.
struct WalkbookCodingTests {
    @Test
    func walkbookRoundTripsThroughJSON() throws {
        let book = Walkbook(
            name: "example-validation",
            appBundleID: "dev.simwalk.route-fixture",
            screens: [
                Walkbook.Screen(
                    id: "today",
                    route: [.tab(label: "Today")],
                    states: [
                        Walkbook.CaptureState(theme: .light),
                        Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "accessibility3"),
                    ],
                    notes: "Power card: verdict the plot area, not the screen."
                ),
                Walkbook.Screen(
                    id: "heart",
                    route: [.tab(label: "Health"), .tap(label: "Heart"), .scrollTo(label: "Resting Heart Rate")],
                    states: [Walkbook.CaptureState(theme: .light)]
                ),
            ]
        )
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(Walkbook.self, from: data)

        #expect(decoded == book)
    }

    @Test
    func routeStepsDecodeInOrder() throws {
        let route: [Walkbook.RouteStep] = [
            .tab(label: "Health"),
            .tap(label: "Steps"),
            .type(label: "Search", text: "resting"),
            .tapPoint(label: "Steps chart", point: [0.8, 0.5]),
            .tapPoint(label: nil, point: [201, 610]),
            .systemTap(label: "Allow"),
            .systemTap(label: "UIA.Health.Allow.Button", owner: .appWindow),
            .openURL(url: "simwalk-fixture://detail"),
            .back,
            .scrollTo(label: "Rows"),
        ]
        let screen = Walkbook.Screen(id: "detail", route: route, states: [Walkbook.CaptureState(theme: .light)])
        let data = try JSONEncoder().encode(screen)
        let decoded = try JSONDecoder().decode(Walkbook.Screen.self, from: data)

        #expect(decoded.route == route)
    }

    /// A `systemTap` in a route names the tree its control came from once the runner has recorded one (SimWalk#28 review).
    @Test
    func asystemTapIsShownWithTheTreeItsControlCameFrom() {
        #expect(Walkbook.RouteStep.systemTap(label: "Allow", owner: .springboard).description == "systemTap 'Allow' in SpringBoard")
        #expect(Walkbook.RouteStep.systemTap(label: "Continue", owner: .appWindow).description == "systemTap 'Continue' in the app's window")
        #expect(Walkbook.RouteStep.systemTap(label: "Allow").description == "systemTap 'Allow'")
    }

    /// A `systemTap` declared `atLaunch` says so wherever its route is shown, before the tree the runner found its control in (SimWalk#46).
    @Test
    func asystemTapDeclaredAtLaunchIsShownSo() {
        #expect(Walkbook.RouteStep.systemTap(label: "Allow", atLaunch: true).description == "systemTap 'Allow' at launch")
        #expect(Walkbook.RouteStep.systemTap(label: "Allow", atLaunch: true, owner: .appWindow).description == "systemTap 'Allow' at launch in the app's window")
    }

    /// An `openURL` step reads as the URL an author wrote, quoted, wherever a route is shown.
    @Test
    func anOpenURLStepIsShownWithItsURL() {
        #expect(Walkbook.RouteStep.openURL(url: "simwalk-fixture://detail").description == "openURL 'simwalk-fixture://detail'")
    }

    /// `atLaunch: false` is the step with no declaration at all: it decodes equal to one without the key, and is written without it, so a walkbook or manifest that never declares one is byte-identical to one written before the key existed (SimWalk#46).
    @Test
    func asystemTapNotDeclaredAtLaunchIsWrittenWithoutTheKey() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let declaredFalse = try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(#"{"systemTap":{"label":"Allow","atLaunch":false}}"#.utf8))
        let absent = try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(#"{"systemTap":{"label":"Allow"}}"#.utf8))

        #expect(declaredFalse == absent)
        #expect(declaredFalse == .systemTap(label: "Allow"))
        #expect(try String(bytes: encoder.encode(declaredFalse), encoding: .utf8) == #"{"systemTap":{"label":"Allow"}}"#)
    }

    /// The literal JSON each step is written as, which is the thing a walkbook author actually types.
    ///
    /// Pinned because the README documented `back` as the bare string `"back"` and the loader refuses it — a walkbook copied from the docs fails to parse with a decoding error about `Dictionary<String, Any>`, which names neither the step nor the fix. Every case is asserted rather than the one that was wrong, because the wire form is synthesised and a case gaining a payload changes it silently.
    @Test(arguments: [
        (Walkbook.RouteStep.tab(label: "Progress"), #"{"tab":{"label":"Progress"}}"#),
        (Walkbook.RouteStep.tap(label: "Heart"), #"{"tap":{"label":"Heart"}}"#),
        (Walkbook.RouteStep.type(label: "Search", text: "resting"), #"{"type":{"label":"Search","text":"resting"}}"#),
        (Walkbook.RouteStep.scrollTo(label: "Rows"), #"{"scrollTo":{"label":"Rows"}}"#),
        (Walkbook.RouteStep.tapPoint(label: "Steps chart", point: [0.8, 0.5]), #"{"tapPoint":{"at":[0.8,0.5],"label":"Steps chart"}}"#),
        (Walkbook.RouteStep.tapPoint(label: nil, point: [201, 610]), #"{"tapPoint":{"at":[201,610]}}"#),
        (Walkbook.RouteStep.systemTap(label: "Allow"), #"{"systemTap":{"label":"Allow"}}"#),
        (Walkbook.RouteStep.systemTap(label: "Allow", owner: .springboard), #"{"systemTap":{"label":"Allow","owner":"springboard"}}"#),
        (Walkbook.RouteStep.systemTap(label: "UIA.Health.Allow.Button", atLaunch: true), #"{"systemTap":{"atLaunch":true,"label":"UIA.Health.Allow.Button"}}"#),
        (Walkbook.RouteStep.systemTap(label: "Allow", atLaunch: true, owner: .appWindow), #"{"systemTap":{"atLaunch":true,"label":"Allow","owner":"appWindow"}}"#),
        (Walkbook.RouteStep.openURL(url: "simwalk-fixture://detail"), #"{"openURL":{"url":"simwalk-fixture://detail"}}"#),
        (Walkbook.RouteStep.back, #"{"back":{}}"#),
    ])
    func aroutestepIsWrittenAsTheJSONTheDocumentationShows(_ step: Walkbook.RouteStep, _ expected: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let written = try #require(String(bytes: encoder.encode(step), encoding: .utf8))

        #expect(written == expected)
        #expect(try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(expected.utf8)) == step)
    }

    /// A screen's own quiet period is authored in the walkbook, so it has to survive the trip through the format an author actually types — and through the loader, which is the only route a runner ever takes.
    @Test
    func aScreenStatesItsOwnQuietPeriodInTheWalkbook() throws {
        let json = """
        {
          "name": "example-validation",
          "appBundleID": "dev.simwalk.route-fixture",
          "screens": [
            { "id": "browse", "route": [{ "tab": { "label": "Browse" } }], "states": [{ "theme": "light" }], "settle": 6000 },
            { "id": "you", "route": [{ "tab": { "label": "You" } }], "states": [{ "theme": "light" }] }
          ]
        }
        """

        let book = try WalkbookLoader.load(from: Data(json.utf8), source: "test")

        #expect(book.screens.map(\.settle) == [6000, nil])
    }

    /// **A screen that does not use it is not written as using it**, which is what keeps every walkbook already on disk hashing exactly as it did — `WalkbookIdentity` is taken over the canonical encoding, so a `"settle":null` appearing on every screen would have changed the identity of every plan at once and made two bundles of the same walk look like two different walks.
    @Test
    func aScreenWithoutItsOwnQuietPeriodDoesNotWriteTheKeyAtAll() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let screen = Walkbook.Screen(id: "browse", route: [.tab(label: "Browse")], states: [Walkbook.CaptureState(theme: .light)])

        let written = try #require(String(bytes: encoder.encode(screen), encoding: .utf8))

        #expect(!written.contains("settle"))
    }

    /// `expect` is authored in the walkbook, so it has to survive the trip through the format an author actually types — and through the loader, which is the only route a runner ever takes.
    @Test
    func aScreenStatingExpectInTheWalkbookSurvivesTheRoundTrip() throws {
        let json = """
        {
          "name": "example-validation",
          "appBundleID": "dev.simwalk.route-fixture",
          "screens": [
            { "id": "browse", "route": [{ "tab": { "label": "Browse" } }], "states": [{ "theme": "light" }], "expect": "browse-root" },
            { "id": "you", "route": [{ "tab": { "label": "You" } }], "states": [{ "theme": "light" }] }
          ]
        }
        """

        let book = try WalkbookLoader.load(from: Data(json.utf8), source: "test")

        #expect(book.screens.map(\.expect) == ["browse-root", nil])
    }

    /// **A screen that does not use `expect` is not written as using it**, for the same reason a screen without its own quiet period is not — `WalkbookIdentity` hashes the canonical encoding, so a stray `"expect":null` on every screen would change the identity of every plan that never asked for the check.
    @Test
    func aScreenWithoutExpectDoesNotWriteTheKeyAtAll() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let screen = Walkbook.Screen(id: "browse", route: [.tab(label: "Browse")], states: [Walkbook.CaptureState(theme: .light)])

        let written = try #require(String(bytes: encoder.encode(screen), encoding: .utf8))

        #expect(!written.contains("expect"))
    }

    /// A point step says which point it is measured against — an element's frame or the screen — in the line an UNREACHABLE verdict prints, since the same two numbers mean different places under each (SimWalk#29).
    @Test
    func apointStepNamesWhatItsPointIsMeasuredAgainst() {
        let route: [Walkbook.RouteStep] = [.tapPoint(label: "Steps chart", point: [0.8, 0.5]), .tapPoint(label: nil, point: [201, 610.5])]

        #expect(route.rendered == "tap 'Steps chart' at 0.8,0.5 of its frame → tap at 201,610.5 pt")
    }

    /// A point step naming no point has nothing to tap, and the loader says so by name.
    @Test
    func apointStepWithoutItsPointIsRefusedByName() throws {
        let json = #"{"name":"w","appBundleID":"com.apple.Health","screens":[{"id":"s","route":[{"tapPoint":{"label":"Steps chart"}}],"states":[{"theme":"light"}]}]}"#

        let thrown = try #require(#expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "test")
        })

        #expect(thrown.description.contains("missing key 'at'"))
    }

    /// The point is two numbers, not the string a route is rendered with (`0.8,0.5`) — the likeliest slip, refused at load rather than read as anything.
    @Test
    func apointWrittenAsAStringIsRefusedAtLoad() {
        let json = #"{"name":"w","appBundleID":"com.apple.Health","screens":[{"id":"s","route":[{"tapPoint":{"label":"Steps chart","at":"0.8,0.5"}}],"states":[{"theme":"light"}]}]}"#

        #expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "test")
        }
    }

    /// An explicit `null` must not decode the same as an absent key (SimWalk#29 review, item 2): a `label` an author deleted the value of but not the key would otherwise silently become the absolute form and tap the status bar rather than a point in the element it still names by its shape.
    @Test
    func atapPointWithAnExplicitNullLabelIsRefused() {
        // A point genuinely on the screen, so nothing about the point itself would refuse this — only
        // the null label can, and only once it is told apart from an absent one.
        let json = #"{"name":"w","appBundleID":"com.apple.Health","screens":[{"id":"s","route":[{"tapPoint":{"label":null,"at":[201,610]}}],"states":[{"theme":"light"}]}]}"#

        #expect(throws: WalkbookLoadError.self) {
            try WalkbookLoader.load(from: Data(json.utf8), source: "test")
        }
    }

    /// A `type` step's text is the half a reader cannot infer, so both halves are in the line an UNREACHABLE verdict prints.
    @Test
    func atypeStepNamesBothTheFieldAndWhatWentIntoIt() {
        let route: [Walkbook.RouteStep] = [.tap(label: "Browse"), .type(label: "Search", text: "resting")]

        #expect(route.rendered == "tap 'Browse' → type 'resting' into 'Search'")
    }
}
