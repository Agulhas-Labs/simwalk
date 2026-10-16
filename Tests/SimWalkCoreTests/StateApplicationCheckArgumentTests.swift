//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A state's own launch arguments and environment are not judged by the identity rule, and are by the sibling pairing (SimWalk#44).
///
/// Its own suite for the reason `StateApplicationCheckLocaleTests` is: it is one question — what a state launched under, as far as each rule judges it.
struct StateApplicationCheckArgumentTests {
    private static let seeding = Walkbook.CaptureState(theme: .light, arguments: ["--seed-sample-data"])

    /// SimWalk#44, the field case: `--seed-sample-data` raises a sheet the route answers, and the screen it lands on is the plain state's.
    ///
    /// One picture is a legitimate result, so both are kept and the argument state is filed as identical to the plain one.
    @Test
    func astateUnderAnArgumentThatDrewThePlainPictureIsKeptAsIdenticalToIt() throws {
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
            StateApplicationCheck.Evidence(state: Self.seeding, screenshot: render),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)

        #expect(filing.outcome == .captured)
        #expect(filing.refused.isEmpty)
        #expect(filing.kept == [StateApplicationCheckTests.light, Self.seeding])
        #expect(filing.identicalToBase == [StateApplicationCheck.Equivalence(state: Self.seeding, base: StateApplicationCheckTests.light)])
    }

    /// The same for environment alone, and whichever was captured first: the base is the state that added nothing of its own.
    @Test
    func theBaseIsThePlainStateWhicheverWasCapturedFirst() throws {
        let configured = Walkbook.CaptureState(theme: .light, environment: ["SEED": "1"])
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: configured, screenshot: render),
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)

        #expect(filing.refused.isEmpty)
        #expect(filing.identicalToBase == [StateApplicationCheck.Equivalence(state: configured, base: StateApplicationCheckTests.light)])
    }

    /// An argument does not excuse the other axes: a locale the device discarded still collides with the plain state, argument or not.
    @Test
    func anArgumentDoesNotExcuseADiscardedLocale() throws {
        let britishSeeding = Walkbook.CaptureState(theme: .light, locale: "en_GB", arguments: ["--seed-sample-data"])
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
            StateApplicationCheck.Evidence(state: britishSeeding, screenshot: render),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        #expect(filing.refused == [StateApplicationCheckTests.light, britishSeeding])
    }

    /// A dark state under an argument is held against the light state under the same argument, not the plain light (the shape of `adarkStateIsHeldAgainstItsOwnLightSiblingNotTheDimmestLight`).
    ///
    /// Against the plain light (0.6) the dark capture (0.7) measures brighter, and the reason would assert a dark device and refuse every state; against its own sibling (0.95) it is plainly darker, and it is still no darker than the dimmest light — so it goes, alone, on a device found light.
    @Test
    func adarkStateUnderAnArgumentPairsWithTheLightUnderTheSameArgument() throws {
        let seedingDark = Walkbook.CaptureState(theme: .dark, arguments: ["--seed-sample-data"])
        let evidence = try [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: StateApplicationCheckTests.png(white: 0.6)),
            StateApplicationCheck.Evidence(state: Self.seeding, screenshot: StateApplicationCheckTests.png(white: 0.95)),
            StateApplicationCheck.Evidence(state: seedingDark, screenshot: StateApplicationCheckTests.png(white: 0.7)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)
        let reason = try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light))

        #expect(filing.refused == [seedingDark])
        #expect(filing.kept == [StateApplicationCheckTests.light, Self.seeding])
        #expect(!reason.contains("taken on a dark device"))
    }

    /// The same for environment: a dark state under an environment variable is held against the light state under the same one, not the plain light.
    @Test
    func adarkStateUnderAnEnvironmentVariablePairsWithTheLightUnderTheSameOne() throws {
        let seedingEnv = Walkbook.CaptureState(theme: .light, environment: ["SEED": "1"])
        let seedingDarkEnv = Walkbook.CaptureState(theme: .dark, environment: ["SEED": "1"])
        let evidence = try [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: StateApplicationCheckTests.png(white: 0.6)),
            StateApplicationCheck.Evidence(state: seedingEnv, screenshot: StateApplicationCheckTests.png(white: 0.95)),
            StateApplicationCheck.Evidence(state: seedingDarkEnv, screenshot: StateApplicationCheckTests.png(white: 0.7)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)
        let reason = try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light))

        #expect(filing.refused == [seedingDarkEnv])
        #expect(filing.kept == [StateApplicationCheckTests.light, seedingEnv])
        #expect(!reason.contains("taken on a dark device"))
    }
}
