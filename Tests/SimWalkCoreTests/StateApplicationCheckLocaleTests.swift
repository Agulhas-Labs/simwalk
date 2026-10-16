//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// A state asking for the locale the device is already in draws what the plain state draws, and that is not a discard (SimWalk#18).
///
/// Its own suite because it is its own question — which conditions a state *launched* under, once the device is taken into account — and because the identity and appearance cases beside it already fill one.
struct StateApplicationCheckLocaleTests {
    /// SimWalk#18, the field case: an app's `you` screen on `detail-3`, a device already in `en_GB`, walked `light`, `light-loc_en_gb` and `dark`.
    ///
    /// The locale state launched under the conditions the plain one did, so one picture is the right result: both are kept, the locale state is recorded as identical to its base, and nothing is refused. Identity used to read it as a discarded locale and refuse both light states.
    @Test
    func alocaleStateTheDeviceIsAlreadyInIsKeptAsIdenticalToItsBase() throws {
        let british = Walkbook.CaptureState(theme: .light, locale: "en_GB")
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = try [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
            StateApplicationCheck.Evidence(state: british, screenshot: render),
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.dark, screenshot: StateApplicationCheckTests.png(white: 0.06)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_GB")

        #expect(filing.outcome == .captured)
        #expect(filing.refused.isEmpty)
        #expect(filing.kept == [StateApplicationCheckTests.light, british, StateApplicationCheckTests.dark])
        #expect(filing.identicalToBase == [StateApplicationCheck.Equivalence(state: british, base: StateApplicationCheckTests.light)])
    }

    /// The same pair on a device in another locale is still a discard, and still refused whole: the locale state asked for something the device was not, and came back as the device's own render.
    @Test
    func alocaleStateOnADeviceInAnotherLocaleIsStillRefused() throws {
        let british = Walkbook.CaptureState(theme: .light, locale: "en_GB")
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
            StateApplicationCheck.Evidence(state: british, screenshot: render),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        #expect(filing.refused == [StateApplicationCheckTests.light, british])
        #expect(filing.identicalToBase.isEmpty)
        #expect(StateApplicationCheck.refusedStates(for: evidence, deviceAppearance: .light) == [StateApplicationCheckTests.light, british])
    }

    /// A dark state on a device already in its locale is judged by appearance alone: `dark-loc_en_gb` identical to `light` on an `en_GB` device differs from it in appearance and nothing else, so the appearance finding decides — the light state kept, the dark one refused — rather than the identity rule refusing both.
    @Test
    func adarkLocaleStateTheDeviceIgnoredIsLeftToTheAppearanceFinding() throws {
        let britishDark = Walkbook.CaptureState(theme: .dark, locale: "en_GB")
        let render = try StateApplicationCheckTests.png(white: 0.93)

        let filing = StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
                StateApplicationCheck.Evidence(state: britishDark, screenshot: render),
            ],
            instead: .captured,
            deviceAppearance: .light,
            deviceLocale: "en_GB"
        )

        #expect(filing.kept == [StateApplicationCheckTests.light])
        #expect(filing.refused == [britishDark])
    }
}
