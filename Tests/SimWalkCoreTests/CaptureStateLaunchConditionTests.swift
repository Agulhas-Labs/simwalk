//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A state's own launch arguments and environment, as a walkbook writes them (SimWalk#44): decoded strictly beside the other axes, and refused at validate when they state nothing.
struct CaptureStateLaunchConditionTests {
    /// SimWalk#44, the field case: an app's `--seed-sample-data` raises HealthKit's write-authorization sheet, so the state launching under it is written with the argument.
    @Test
    func astateCarryingArgumentsAndEnvironmentDecodesThem() throws {
        let json = #"{"theme":"light","arguments":["--seed-sample-data","-flag"],"environment":{"SEED":"1","MODE":"walk"}}"#

        let state = try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(json.utf8))

        #expect(state == Walkbook.CaptureState(
            theme: .light,
            arguments: ["--seed-sample-data", "-flag"],
            environment: ["SEED": "1", "MODE": "walk"]
        ))
    }

    /// The two new keys widen the allowlist and nothing else: a misspelling beside them is still a refusal naming the key (SimWalk#10).
    @Test
    func anUnknownKeyBesideArgumentsAndEnvironmentIsStillRefused() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","arguments":["--seed-sample-data"],"environment":{"SEED":"1"},"argumentz":["-x"]}"#)

        #expect(problems == [.unknownKey(path: "screens[0].states[0]", key: "argumentz", suggestion: "arguments")])
    }

    /// An empty list launches exactly as an absent one does while slugging as a different state, so it is refused rather than read as absent.
    @Test
    func anEmptyArgumentsListIsRefusedAtValidate() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","arguments":[]}"#)

        #expect(problems == [.emptyLaunchCondition(screenID: "today", index: 0, key: "arguments")])
        #expect(problems.map(\.description) == ["screen 'today' requests arguments [] — an empty list launches the app exactly as its absence does, so omit the key"])
    }

    @Test
    func anEmptyEnvironmentObjectIsRefusedAtValidate() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","environment":{}}"#)

        #expect(problems == [.emptyLaunchCondition(screenID: "today", index: 0, key: "environment")])
    }

    /// Each argument and each environment name must name something; the value of a variable may be empty, which is a real setting.
    @Test
    func ablankArgumentOrEnvironmentNameIsRefusedAndAnEmptyValueIsNot() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","arguments":["--seed-sample-data",""],"environment":{"":"1","EMPTY":""}}"#)

        #expect(problems == [
            .blankLaunchCondition(screenID: "today", index: 0, key: "arguments"),
            .blankLaunchCondition(screenID: "today", index: 0, key: "environment"),
        ])
    }

    /// Two states of one screen under the same theme and the same arguments are one state to the bundle, and the existing slug rule refuses the second.
    @Test
    func twoStatesWithTheSameThemeAndArgumentsAreRefusedAsOneSlug() throws {
        let problems = try Self.problems(loading: #"{"theme":"light","arguments":["--seed-sample-data"]},{"theme":"light","arguments":["--seed-sample-data"]}"#)

        #expect(problems == [.duplicateCaptureState(screenID: "today", index: 0, slug: "light-args_1f297606")])
    }

    /// The problems `WalkbookLoader.load` reports for a one-screen walkbook whose `states` list holds `states`, written as JSON.
    private static func problems(loading states: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [WalkbookProblem] {
        let json = #"{"name":"w","appBundleID":"com.example.app","screens":[{"id":"today","route":[{"tab":{"label":"Today"}}],"states":["# + states + #"]}]}"#
        let thrown = try #require(
            #expect(throws: WalkbookLoadError.self, sourceLocation: sourceLocation) {
                try WalkbookLoader.load(from: Data(json.utf8), source: "memory")
            },
            sourceLocation: sourceLocation
        )
        guard case let .invalid(_, problems) = thrown else {
            Issue.record("expected an invalid refusal, got \(thrown)", sourceLocation: sourceLocation)
            return []
        }
        return problems
    }
}
