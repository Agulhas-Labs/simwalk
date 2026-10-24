//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A screen whose walkbook entry says the app, not the device, picks its appearance (SimWalk#19).
///
/// Not pinned here: that a device which really failed to switch is still caught on a screen that does not state `fixedAppearance`; the existing appearance suites hold that.
struct FixedAppearanceTests {
    private static let accessibilityXL = Walkbook.CaptureState(theme: .light, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityXL")

    /// The specimen: an onboarding screen drawn dark whatever the system's, refused without the key and not with it.
    ///
    /// Its light and dark captures measure 0.203 each on a light device.
    @Test
    func aDarkByDesignScreenIsNotRefusedOnAppearanceWhenItsAppearanceIsFixed() throws {
        let evidence = try [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: StateApplicationCheckTests.png(white: 0.2)),
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.dark, screenshot: StateApplicationCheckTests.png(white: 0.2, tick: true)),
        ]

        let without = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)
        let with = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, fixedAppearance: .dark)

        #expect(!without.refused.isEmpty)
        #expect(with.refused.isEmpty)
        #expect(with.refusedOnAppearance.isEmpty)
        #expect(with.kept == evidence.map(\.state))
        #expect(with.outcome == .captured)
    }

    /// A fixed `light` screen drawn light in dark mode: the dark capture at 0.9 is not a refused light render.
    @Test
    func aDarkCaptureBrighterThanMidGreyIsNotRefusedOnAScreenFixedLight() throws {
        let evidence = try [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: StateApplicationCheckTests.png(white: 0.95)),
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.dark, screenshot: StateApplicationCheckTests.png(white: 0.9)),
        ]

        let without = StateApplicationCheck.refusedStates(for: evidence, deviceAppearance: .light)
        let with = StateApplicationCheck.refusedStates(for: evidence, deviceAppearance: .light, fixedAppearance: .light)

        #expect(!without.isEmpty)
        #expect(with.isEmpty)
    }

    /// Two states differing in `theme` alone drawing one picture is the screen's own, not a discarded state.
    @Test
    func aLightAndDarkPairDrawingOnePictureIsNoCollisionWhenAppearanceIsFixed() throws {
        let render = try StateApplicationCheckTests.png(white: 0.2)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.dark, screenshot: render),
        ]

        let refusal = StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light, fixedAppearance: .dark)

        #expect(refusal == nil)
    }

    /// A pair differing in another condition still collides: fixing the appearance excuses `theme` alone.
    @Test
    func aPairDifferingInDynamicTypeSizeStillCollidesWhenAppearanceIsFixed() throws {
        let render = try StateApplicationCheckTests.png(white: 0.2)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render),
            StateApplicationCheck.Evidence(state: Self.accessibilityXL, screenshot: render),
        ]

        let reason = try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light, fixedAppearance: .dark))

        #expect(reason.contains("byte-identical"))
    }

    @Test
    func aScreensFixedAppearanceDecodesAndRoundTrips() throws {
        let data = Data(#"{"id":"home","route":[],"states":[{"theme":"light"}],"fixedAppearance":"dark"}"#.utf8)

        let screen = try JSONDecoder().decode(Walkbook.Screen.self, from: data)
        let again = try JSONDecoder().decode(Walkbook.Screen.self, from: JSONEncoder().encode(screen))

        #expect(screen.fixedAppearance == .dark)
        #expect(again == screen)
    }

    @Test
    func anAppearanceThatIsNeitherLightNorDarkIsRefused() {
        let data = Data(#"{"id":"home","route":[],"states":[{"theme":"light"}],"fixedAppearance":"dim"}"#.utf8)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Walkbook.Screen.self, from: data) }
    }

    /// The hash was computed on the commit before the key existed: a walkbook that does not use it is the same walk to the manifest.
    @Test
    func aWalkbookWithoutTheKeyKeepsItsHash() throws {
        let data = Data(#"{"name":"w","appBundleID":"a","screens":[{"id":"home","route":[],"states":[{"theme":"light"}],"notes":"n"}]}"#.utf8)

        let hash = try WalkbookIdentity.hash(of: JSONDecoder().decode(Walkbook.self, from: data))

        #expect(hash == "b0e5c385cfe251d612f393c0ffaa2b52020810fc3bba3551343afd645e4f94b5")
    }

    /// The walk's line for the screen says the comparison was not made, and a screen without the key says nothing of it.
    @Test
    func theWalkLineSaysTheAppearanceComparisonWasNotMade() {
        let fixed = CaptureManifest.ScreenRecord(id: "intro", outcome: .captured, routeTaken: [], fixedAppearance: .dark)
        let plain = CaptureManifest.ScreenRecord(id: "intro", outcome: .captured, routeTaken: [])

        #expect(CaptureBundleSummary.screenLine(fixed, position: 1).hasSuffix("· appearance fixed dark by the walkbook, light and dark not compared"))
        #expect(!CaptureBundleSummary.screenLine(plain, position: 1).contains("appearance fixed"))
    }
}
