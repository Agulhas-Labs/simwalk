//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// What a state's launch arguments and environment make of its slug and of the launch itself (SimWalk#44) — built in the core, so the strings the runner hands the app are checked here.
struct CaptureStateLaunchTests {
    /// The hash is the first 8 hex characters of SHA-256 over the arguments, each length-prefixed as `<byte count>:<argument>` (not NUL-joined), so the expected slug is pinned to the value, not merely its shape.
    @Test
    func astateUnderAnArgumentSlugsByItsHash() {
        let state = Walkbook.CaptureState(theme: .light, arguments: ["--seed-sample-data"])

        #expect(state.slug == "light-args_1f297606")
    }

    @Test
    func theSameArgumentsGiveTheSameSlug() {
        let first = Walkbook.CaptureState(theme: .light, arguments: ["-a", "b"])
        let second = Walkbook.CaptureState(theme: .light, arguments: ["-a", "b"])

        #expect(first.slug == second.slug)
    }

    /// Order is part of a launch — `-a b` is not `b -a` — so it is part of the slug.
    @Test
    func argumentsInAnotherOrderGiveAnotherSlug() {
        let first = Walkbook.CaptureState(theme: .light, arguments: ["-a", "b"])
        let second = Walkbook.CaptureState(theme: .light, arguments: ["b", "-a"])

        #expect(first.slug != second.slug)
    }

    /// The collision a reduced-to-letters slug would have had: `-a b` and `-a_b` reduce to one segment.
    @Test
    func argumentsThatWouldReduceToOneSegmentSlugApart() {
        let split = Walkbook.CaptureState(theme: .light, arguments: ["-a", "b"])
        let joined = Walkbook.CaptureState(theme: .light, arguments: ["-a_b"])

        #expect(split.slug != joined.slug)
    }

    @Test
    func statesDifferingOnlyInEnvironmentSlugApart() {
        let first = Walkbook.CaptureState(theme: .light, environment: ["SEED": "1"])
        let second = Walkbook.CaptureState(theme: .light, environment: ["SEED": "2"])

        #expect(first.slug != second.slug)
        #expect(first.slug.hasPrefix("light-env_"))
    }

    /// Theme, then `dt_`, `loc_`, `args_`, `env_`, and `orientation` last of all — the environment hashed over its pairs sorted by key, so the order a dictionary happens to hold them in changes nothing.
    @Test
    func everyAxisSlugsInItsFixedOrder() {
        let state = Walkbook.CaptureState(
            theme: .dark,
            dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL",
            locale: "en_GB",
            arguments: ["a", "b"],
            environment: ["B": "2", "A": "1"],
            orientation: .landscape
        )

        #expect(state.slug == "dark-dt_uictcontentsizecategoryaccessibilityl-loc_en_gb-args_facdde7a-env_a6df947a-landscape")
    }

    /// The length-prefixed encoding is unambiguous where a `key=value` join would collide: an environment key holding `=` and a value holding `=` can spell the same joined string from different pairs.
    @Test
    func anenvironmentKeyHoldingEqualsSlugsApartFromTheSameCharactersInTheValue() {
        let first = Walkbook.CaptureState(theme: .light, environment: ["A=B": "C"])
        let second = Walkbook.CaptureState(theme: .light, environment: ["A": "B=C"])

        #expect(first.slug != second.slug)
    }

    /// The platform's own overrides first, byte-identical to what the runner built before the move, then the state's own arguments verbatim.
    @Test
    func theLaunchArgumentsAreThePlatformOnesFollowedByTheStates() {
        let state = Walkbook.CaptureState(
            theme: .light,
            dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL",
            locale: "en_GB",
            arguments: ["--seed-sample-data", "-x"]
        )

        #expect(state.launchArguments == [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
            "-AppleLocale", "en_GB", "-AppleLanguages", "(en_GB)",
            "--seed-sample-data", "-x",
        ])
    }

    @Test
    func aplainStateLaunchesWithNoArguments() {
        let plain = Walkbook.CaptureState(theme: .dark)

        #expect(plain.launchArguments.isEmpty)
        #expect(plain.launchEnvironment(over: ["KEEP": "1"]) == ["KEEP": "1"])
    }

    @Test
    func astatesEnvironmentIsLaidOverTheBaseAndWinsOnASharedKey() {
        let state = Walkbook.CaptureState(theme: .light, environment: ["SHARED": "state", "OWN": "1"])

        #expect(state.launchEnvironment(over: ["SHARED": "base", "BASE": "1"]) == ["SHARED": "state", "OWN": "1", "BASE": "1"])
    }

    @Test
    func astatesLibrariesJoinTheBasesInsteadOfReplacingThem() {
        let state = Walkbook.CaptureState(theme: .light, environment: ["DYLD_INSERT_LIBRARIES": "/state.dylib"])

        #expect(state.launchEnvironment(over: ["DYLD_INSERT_LIBRARIES": "/base.dylib"]) == ["DYLD_INSERT_LIBRARIES": "/state.dylib:/base.dylib"])
        #expect(state.launchEnvironment(over: [:]) == ["DYLD_INSERT_LIBRARIES": "/state.dylib"])
    }

    @Test
    func anotherSharedKeyStillGoesToTheStateBesideTheJoinedLibraries() {
        let state = Walkbook.CaptureState(theme: .light, environment: ["DYLD_INSERT_LIBRARIES": "/s", "SHARED": "state"])

        #expect(state.launchEnvironment(over: ["DYLD_INSERT_LIBRARIES": "/b", "SHARED": "base"]) == ["DYLD_INSERT_LIBRARIES": "/s:/b", "SHARED": "state"])
    }

    /// A state carrying neither encodes exactly as before SimWalk#44 — its JSON is unchanged, while every manifest this build writes declares the current format.
    @Test
    func astateWithNeitherWritesNeitherKey() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let plain = try String(decoding: encoder.encode(Walkbook.CaptureState(theme: .light, locale: "en_GB")), as: UTF8.self)
        let launched = try String(decoding: encoder.encode(Walkbook.CaptureState(theme: .light, arguments: ["-a"], environment: ["K": "v"])), as: UTF8.self)

        #expect(plain == #"{"locale":"en_GB","theme":"light"}"#)
        #expect(launched == #"{"arguments":["-a"],"environment":{"K":"v"},"theme":"light"}"#)
    }

    /// A state's empty `DYLD_INSERT_LIBRARIES` leaves SimWalk's library in place rather than replacing it (SimWalk#154).
    @Test
    func aStatesEmptyInsertedLibrariesKeepTheBases() {
        let state = Walkbook.CaptureState(theme: .light, environment: ["DYLD_INSERT_LIBRARIES": ""])

        let launched = state.launchEnvironment(over: ["DYLD_INSERT_LIBRARIES": "/libs/animations.dylib"])

        #expect(launched["DYLD_INSERT_LIBRARIES"] == "/libs/animations.dylib")
    }
}
