//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import ImageIO
@testable import SimWalkCore
import Testing
import UniformTypeIdentifiers

/// The gate over the tool's one unforgivable failure class: a capture filed under a state the device discarded in silence.
///
/// Every case here is a real specimen. iOS 26.5 reports `simctl ui appearance dark` set and changes nothing, so the 2026-08-20 app round filed a whole dark dimension of light renders under passing outcomes; `accessibility2` and `zz_NONSENSE` do the same for the other two axes, each verified byte-identical to an unset capture, screenshot and tree both.
struct StateApplicationCheckTests {
    /// The specimen: a screen walked light and dark, coming back with one picture.
    @Test
    func twoStatesThatProducedOnePictureAreRefused() throws {
        let render = Data("the light render".utf8)

        let reason = try #require(StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
        ]))

        #expect(reason.contains("'light' and 'dark'"))
        #expect(reason.contains("byte-identical"))
    }

    /// States that genuinely applied are not refused — the check proves discard, it never certifies application.
    ///
    /// Real renders since the round-2 review's finding 5: a dark capture whose bytes do not decode is now refused, so two stand-in strings no longer describe a screen that applied both states.
    @Test
    func statesThatProducedDifferentPicturesAreNotRefused() throws {
        let refusal = try StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.06)),
        ])

        #expect(refusal == nil)
    }

    /// One state cannot collide with anything, and a screen asking for one state is the common case — it must cost no comparison and produce no refusal.
    @Test
    func asingleStateIsNeverRefused() {
        let refusal = StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Data("the light render".utf8)),
        ])

        #expect(refusal == nil)
    }

    /// It knows nothing about what an axis means, which is what lets one rule cover theme, Dynamic Type, locale — and the next axis for free.
    @Test
    func adynamicTypeSizeTheDeviceDiscardedIsCaughtByTheSameRule() throws {
        let render = Data("the default-size render".utf8)

        let reason = try #require(StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light, dynamicTypeSize: "accessibility2"), screenshot: render),
        ]))

        #expect(reason.contains("'light' and 'light-dt_accessibility2'"))
    }

    /// A screen with two independent collisions has made one mistake in one walkbook; four refusals describe it no better than one, and every group is named so an author can find both.
    @Test
    func everyCollidingGroupIsNamedInOneRefusal() throws {
        let first = Data("render A".utf8)
        let second = Data("render B".utf8)

        let reason = try #require(StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: first),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light, locale: "fr_FR"), screenshot: second),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: first),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .dark, locale: "fr_FR"), screenshot: second),
        ]))

        #expect(reason.contains("'light' and 'dark'"))
        #expect(reason.contains("'light-loc_fr_fr' and 'dark-loc_fr_fr'"))
    }

    /// Groups are reported in capture order, both within a group and between them — a refusal that reshuffles itself between identical runs cannot be diffed.
    @Test
    func groupsAreReportedInCaptureOrder() throws {
        let first = Data("render A".utf8)
        let second = Data("render B".utf8)
        let evidence = [
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light, locale: "a1"), screenshot: first),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light, locale: "b1"), screenshot: second),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light, locale: "a2"), screenshot: first),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light, locale: "b2"), screenshot: second),
        ]

        let reasons = try (0 ..< 8).map { _ in try #require(StateApplicationCheck.refusal(for: evidence)) }

        #expect(Set(reasons).count == 1)
        #expect(try #require(reasons.first).contains("'light-loc_a1' and 'light-loc_a2'; 'light-loc_b1' and 'light-loc_b2'"))
    }

    /// The measured hole the byte comparison alone leaves: a `dark` capture that is a light render, differing from its `light` sibling only by the status-bar clock.
    ///
    /// The specimen is an app's Browse screen on 2026-08-20 — 41 bytes apart in 249 KB, mean colour identical to the byte. Byte identity says nothing here; the brightness does.
    @Test
    func adarkCaptureNoDarkerThanItsLightSiblingIsRefused() throws {
        let reason = try #require(try StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93, tick: true)),
        ]))

        #expect(reason.contains("state 'dark' is no darker than 'light'"))
        #expect(reason.contains("mean brightness"))
    }

    /// An appearance that genuinely applied is not refused — this is what the gate has to leave alone on every honest walk.
    @Test
    func adarkCaptureThatIsActuallyDarkIsNotRefused() throws {
        let refusal = try StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.06)),
        ])

        #expect(refusal == nil)
    }

    /// A screen carrying several of each has to have moved every one of them: the brightest dark is compared with the dimmest light, so one state left behind is still caught.
    @Test
    func theBrightestDarkIsComparedWithTheDimmestLight() throws {
        let reason = try #require(try StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .light, dynamicTypeSize: "xxl"), screenshot: Self.png(white: 0.88)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.06)),
            StateApplicationCheck.Evidence(state: Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "xxl"), screenshot: Self.png(white: 0.9)),
        ]))

        #expect(reason.contains("state 'dark-dt_xxl' is no darker than 'light-dt_xxl'"))
    }

    /// Having no light sibling is not itself a reason to refuse: a screen walked only in dark, drawing dark, is filed.
    ///
    /// This used to hold a 0.93 render — a light one — and expect it filed, on the grounds that with nothing to compare against a refusal would be guessing. That was the hole SimWalk#26 fell through: a device reporting `dark` and drawing light filed its light render as `captured`. A light render on its own is now refused (`adarkCaptureWithNoLightCaptureBesideItThatDrawsLightIsRefused`); what this still pins is that the absence of a sibling costs a dark render nothing.
    @Test
    func adarkOnlyScreenIsNotRefusedForHavingNoLightSibling() throws {
        let refusal = try StateApplicationCheck.refusal(for: [
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.12)),
        ])

        #expect(refusal == nil)
    }

    /// The path the gate was originally missing: a screen that failed reading its third state still had two written, and they were filed unchecked.
    ///
    /// A partial walk is where an unapplied state is most likely rather than least — whatever broke the third state was in the same environment as the first two — so a `captureFailed` verdict over evidence that cannot be attributed is refused like any other.
    @Test
    func evidenceThatCannotBeAttributedIsRefusedEvenWhenTheScreenAlsoFailedMidCapture() throws {
        let render = Data("the light render".utf8)
        let intended = ScreenOutcome.captureFailed(reason: "state 'dark-dt_xxl': out of space")

        let refused = try #require(StateApplicationCheck.refusedOutcome(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
            ],
            instead: intended
        ))
        guard case let .stateNotApplied(reason) = refused else {
            Issue.record("expected a state-not-applied refusal, got \(refused)")
            return
        }

        #expect(reason.contains("'light' and 'dark'"))
        // Neither fact is dropped: the screen has two things wrong with it and the record says both.
        #expect(reason.contains("out of space"))
    }

    /// Round 2, finding 3: a state refusal used to overwrite `unexpectedScreen` with a plain `stateNotApplied`, discarding `expected`/`found` for a screen that was, independently, also the wrong one.
    ///
    /// Both facts now survive: the shape stays `unexpectedScreen` and the state finding rides in its own `reason`.
    @Test
    func aStateRefusalDoesNotOverwriteAScreenMismatchButJoinsIt() throws {
        let render = Data("the light render".utf8)
        let intended = ScreenOutcome.unexpectedScreen(expected: "activity-detail-root", found: ["workouts-list-root"])

        let refused = try #require(StateApplicationCheck.refusedOutcome(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
            ],
            instead: intended
        ))
        guard case let .unexpectedScreen(expected, found, reason) = refused else {
            Issue.record("expected an unexpectedScreen refusal, got \(refused)")
            return
        }

        #expect(expected == "activity-detail-root")
        #expect(found == ["workouts-list-root"])
        #expect(reason?.contains("'light' and 'dark'") == true)
    }

    /// A capture failure over evidence nothing can be shown to be wrong with stays a capture failure — the gate refuses what it can prove and never repaints an unrelated verdict.
    @Test
    func acaptureFailureOverAttributableEvidenceIsLeftAlone() {
        let refused = StateApplicationCheck.refusedOutcome(
            for: [StateApplicationCheck.Evidence(state: Self.light, screenshot: Data("the light render".utf8))],
            instead: .captureFailed(reason: "state 'dark': out of space")
        )

        #expect(refused == nil)
    }

    /// The ordinary path: a clean screen is not refused, and nothing is invented to put in front of `captured`.
    ///
    /// Real renders since the round-2 review's finding 5, which refuses a dark capture whose bytes do not decode.
    @Test
    func acleanScreenKeepsTheVerdictItEarned() throws {
        let refused = try StateApplicationCheck.refusedOutcome(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.06)),
            ],
            instead: .captured
        )

        #expect(refused == nil)
    }

    /// SimWalk#15, the specimen: a screen walked light and dark on iOS 26.5, the dark state discarded and drawn light, clock ticked between the two.
    ///
    /// On a device the host read as light, the dark state goes; the light one is filed, and the screen is still not a pass.
    @Test
    func adarkStateTheDeviceIgnoredCostsOnlyThatState() throws {
        let filing = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93, tick: true)),
            ],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept == [Self.light])
        #expect(filing.refused == [Self.dark])
        guard case let .stateNotApplied(reason) = filing.outcome else {
            Issue.record("a screen that refused a state must not keep a passing outcome, got \(filing.outcome)")
            return
        }
        #expect(reason.contains("state 'dark' is no darker than 'light'"))
    }

    /// The same specimen with the two shots inside one minute, which is the common case: the status-bar clock agrees, so a discarded appearance comes back byte-identical rather than 41 bytes apart.
    ///
    /// The picture still measures, so the appearance finding — not a wholesale identity refusal — decides which state goes.
    @Test
    func alightAndDarkPairTakenInsideOneMinuteStillKeepsTheLightState() throws {
        let render = try Self.png(white: 0.93)

        let filing = StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
            ],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept == [Self.light])
        #expect(filing.refused == [Self.dark])
    }

    /// Every state on the screen the finding does not implicate is filed — a real app's `progress` screen asks for light, dark, and dark at an accessibility size, and both dark states were ignored.
    @Test
    func everyDarkStateTheDeviceIgnoredIsRefusedAndOnlyThose() throws {
        let largeDark = Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL")

        let filing = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93, tick: true)),
                StateApplicationCheck.Evidence(state: largeDark, screenshot: Self.png(white: 0.91)),
            ],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept == [Self.light])
        #expect(filing.refused == [Self.dark, largeDark])
    }

    /// The review's failing case for the brightness floor this replaced: a dark device whose light setting was ignored, on an image-heavy screen whose dark render is brighter than mid-grey.
    ///
    /// Both captures are the device's own dark render, and no picture measurement can say so — the device's appearance does, so both states go and the reason claims nothing it cannot know.
    @Test
    func adarkDeviceRefusesBothSidesEvenWhenTheRenderMeasuresBright() throws {
        let evidence = try [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.62)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.62, tick: true)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .dark)
        let reason = try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .dark))

        #expect(filing.kept.isEmpty)
        #expect(filing.refused == [Self.light, Self.dark])
        #expect(reason.contains("was dark before the walk"))
        #expect(!reason.contains("the doubt is the dark state's alone"))
    }

    /// A device whose appearance could not be read gives nothing to attribute by, so a failed comparison refuses both sides — the default when nothing is passed, because the default has to be the answer that refuses more.
    @Test
    func anUnreadDeviceAppearanceRefusesBothSides() throws {
        let evidence = try [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93, tick: true)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured)

        #expect(filing.refused == [Self.light, Self.dark])
        #expect(try #require(StateApplicationCheck.refusal(for: evidence)).contains("could not be read before the walk"))
    }

    /// An identical pair that is also dim, on a device found light: that is what two dark renders look like, and a reset to light that did not hold would produce exactly it — so the device's word alone does not keep the light state.
    ///
    /// **Flipped in the last review round, because the rule changed**: keeping a light state now takes the device found light *and* light captures that measure as light renders. The first cut kept this pair on the device's word; the reset it relies on uses the very setter in doubt.
    @Test
    func adimIdenticalPairOnALightDeviceRefusesBoth() throws {
        let render = try Self.png(white: 0.2)
        let evidence = [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)
        let reason = try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light))

        #expect(filing.refused == [Self.light, Self.dark])
        #expect(reason.contains("no brighter than mid-grey"))
        #expect(!reason.contains("the doubt falls on the dark state"))
    }

    /// The review's swapped pair: the light capture a 0.1 render, the dark one 0.93.
    ///
    /// "Much brighter" is not "no darker" — no light device draws that — so both sides go, whatever the device was read as.
    @Test
    func adarkCaptureBrighterThanItsLightSiblingRefusesBothSides() throws {
        let evidence = try [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.1)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)

        #expect(filing.kept.isEmpty)
        #expect(filing.refused == [Self.light, Self.dark])
        #expect(try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light)).contains("brighter than 'light'"))
    }

    /// The inverted signature refuses both even where the light capture alone would pass as a light render — the one case the brightness floor cannot catch.
    @Test
    func aninvertedPairIsRefusedEvenWhenTheLightCaptureMeasuresLight() throws {
        let refused = try StateApplicationCheck.refusedStates(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.6)),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.9)),
            ],
            deviceAppearance: .light
        )

        #expect(refused == [Self.light, Self.dark])
    }

    /// The inverted signature is read per pair, not across the screen (SimWalk#19): a dark state is held against the light state it differs from in appearance alone.
    ///
    /// The case the screen-wide comparison got wrong: a British-locale light state that renders dimmer than the plain one. Against *that*, a dark capture measured brighter and the reason asserted a dark device; against its own sibling it is plainly darker. It is still no darker than the dimmest light — the screen-wide test for "did not apply" is unchanged — so it goes, alone, on a device found light.
    @Test
    func adarkStateIsHeldAgainstItsOwnLightSiblingNotTheDimmestLight() throws {
        let british = Walkbook.CaptureState(theme: .light, locale: "en_GB")
        let evidence = try [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.95)),
            StateApplicationCheck.Evidence(state: british, screenshot: Self.png(white: 0.6)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.7)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light)
        let reason = try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light))

        #expect(filing.refused == [Self.dark])
        #expect(filing.kept == [Self.light, british])
        #expect(!reason.contains("taken on a dark device"))
    }

    /// A dark state with no light sibling of its own is set against the dimmest light, as before, and the reason says that is the comparison it made.
    @Test
    func adarkStateWithNoLightSiblingIsHeldAgainstTheDimmestLightAndSaysSo() throws {
        let british = Walkbook.CaptureState(theme: .light, locale: "en_GB")
        let evidence = try [
            StateApplicationCheck.Evidence(state: british, screenshot: Self.png(white: 0.6)),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.9)),
        ]

        let reason = try #require(StateApplicationCheck.refusal(for: evidence, deviceAppearance: .light))

        #expect(StateApplicationCheck.refusedStates(for: evidence, deviceAppearance: .light) == [british, Self.dark])
        #expect(reason.contains("brighter than 'light-loc_en_gb', the dimmest light capture, since it has no light sibling of its own"))
    }

    /// A light capture under mid-grey on a device found light has two explanations, and the refusal names both (SimWalk#19): a reset that did not hold, or a screen that is dark by design.
    ///
    /// The floor's gap was measured on two apps; a dark-branded app, a photograph or a map lands under it honestly, and a refusal naming only the reset would send its reader after a device fault that is not there.
    @Test
    func amidGreyRefusalNamesAScreenDarkByDesignAsWellAsAFailedReset() throws {
        let render = try Self.png(white: 0.3)

        let reason = try #require(StateApplicationCheck.refusal(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
            ],
            deviceAppearance: .light
        ))

        #expect(reason.contains("a reset to light that did not hold"))
        #expect(reason.contains("a screen dark by design"))
    }

    /// Either side of the floor, on a device found light: just under mid-grey refuses both, just over keeps the light state.
    ///
    /// An exact 0.5 is not a value the 8-bit measurement can return.
    @Test(arguments: [(0.45, false), (0.55, true)])
    func thelightRenderFloorDecidesOnlyOnADeviceFoundLight(white: Double, keepsLight: Bool) throws {
        let render = try Self.png(white: white)

        let filing = StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
            ],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept == (keepsLight ? [Self.light] : []))
    }

    /// The same dim identical pair on a dark device refuses both: a dim picture is exactly what a dark device draws whichever state was asked for.
    @Test
    func adimIdenticalPairOnADarkDeviceRefusesBoth() throws {
        let render = try Self.png(white: 0.2)

        let refused = StateApplicationCheck.refusedStates(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
            ],
            deviceAppearance: .dark
        )

        #expect(refused == [Self.light, Self.dark])
    }

    /// A collision across an axis nothing measures still refuses both states — there is no picture to ask which is honest — and nothing else on the screen.
    @Test
    func acollisionAcrossAnUnmeasuredAxisRefusesTheGroupAndOnlyTheGroup() throws {
        let render = try Self.png(white: 0.93)
        let large = Walkbook.CaptureState(theme: .light, dynamicTypeSize: "accessibility2")

        let filing = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: large, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.06)),
            ],
            instead: .captured
        )

        #expect(filing.kept == [Self.dark])
        #expect(filing.refused == [Self.light, large])
    }

    /// Two identical pictures that cannot be measured leave nothing to attribute by, so a light and dark pair is refused whole — the finding that cannot see the picture never guesses which half to keep.
    @Test
    func anUnmeasurableCollisionIsRefusedWhole() {
        let render = Data("the light render".utf8)

        let refused = StateApplicationCheck.refusedStates(for: [
            StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
            StateApplicationCheck.Evidence(state: Self.dark, screenshot: render),
        ])

        #expect(refused == [Self.light, Self.dark])
    }

    /// Nothing refused, nothing moved: the verdict earned is the verdict filed, and every state is kept.
    ///
    /// Real renders since the round-2 review's finding 5, which refuses a dark capture whose bytes do not decode.
    @Test
    func acleanFilingKeepsEveryState() throws {
        let filing = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.06)),
            ],
            instead: .captured
        )

        #expect(filing == StateApplicationCheck.Filing(outcome: .captured, kept: [Self.light, Self.dark], refused: []))
    }

    /// SimWalk#26: a screen walked only in `dark` has no light capture to be compared with, and its dark capture used to be filed unjudged — so a device that reported `dark` and drew light filed a light render as `captured`.
    ///
    /// Measured on its own instead: brighter than mid-grey is a light render, refused with both explanations named.
    @Test
    func adarkCaptureWithNoLightCaptureBesideItThatDrawsLightIsRefused() throws {
        let filing = try StateApplicationCheck.filing(
            for: [StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93))],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept.isEmpty)
        #expect(filing.refused == [Self.dark])
        guard case let .stateNotApplied(reason) = filing.outcome else {
            Issue.record("a light render labelled dark must not keep a passing outcome, got \(filing.outcome)")
            return
        }
        #expect(reason.contains("state 'dark' has no light capture on this screen to be compared with"))
        #expect(reason.contains("0.929"))
        #expect(reason.contains("a screen bright by design"))
    }

    /// The same screen drawing dark is filed: the ceiling refuses a light render, and a dark one has nothing against it.
    ///
    /// Two dark states, one of each, so the refusal is shown to cost only the state it names.
    @Test
    func anunpairedDarkCaptureThatDrawsDarkIsKeptAndOnlyTheLightOneRefused() throws {
        let large = Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "accessibility3")

        let filing = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.12)),
                StateApplicationCheck.Evidence(state: large, screenshot: Self.png(white: 0.93)),
            ],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept == [Self.dark])
        #expect(filing.refused == [large])
    }

    /// A light capture that does not decode leaves the dark one beside it with nothing to be compared with — measured on its own, like a dark-only screen, never waved through for want of a partner.
    @Test
    func adarkCaptureBesideALightOneThatDoesNotDecodeIsStillHeldToTheCeiling() throws {
        let filing = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: Data("not a png".utf8)),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93)),
            ],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept == [Self.light])
        #expect(filing.refused == [Self.dark])
        guard case let .stateNotApplied(reason) = filing.outcome else {
            Issue.record("a light render labelled dark must not keep a passing outcome, got \(filing.outcome)")
            return
        }
        #expect(reason.contains("state 'dark' has no light capture on this screen to be compared with"))
    }

    /// The review's case for SimWalk#26: the trap drew the dark state light, and the launch's content came out a little dimmer than the light capture's — 0.87 against 0.93, inside the margin's reach, so the comparison passes it.
    ///
    /// Held to the ceiling as well, on every device: a light render is refused under a dark label whether the device was found light, dark or unread, and the light capture beside it — which passed the comparison — is kept.
    @Test(arguments: [Walkbook.Theme.light, .dark, nil])
    func adarkCaptureThatPassesTheComparisonAndStillMeasuresLightIsRefused(found: Walkbook.Theme?) throws {
        let filing = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93)),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.87)),
            ],
            instead: .captured,
            deviceAppearance: found
        )

        #expect(filing.kept == [Self.light])
        #expect(filing.refused == [Self.dark])
        guard case let .stateNotApplied(reason) = filing.outcome else {
            Issue.record("a light render labelled dark must not keep a passing outcome, got \(filing.outcome)")
            return
        }
        #expect(reason.contains("state 'dark' is darker than the light captures beside it and still measures brighter than mid-grey"))
        #expect(reason.contains("0.871"))
        #expect(reason.contains("a screen bright by design"))
    }

    /// SimWalk#26: the filing says which refusals the appearance check made — the ones a settle of the device can cure — as a field, never left to the refusal's wording.
    ///
    /// A collision over a Dynamic Type size is refused and not named; a dark state no darker than its light one, and a dark render brighter than mid-grey, are named; on one screen holding all three, the field names exactly the appearance check's.
    @Test
    func theappearanceCheckRefusalsAreNamedApartFromACollisionOverAnotherAxis() throws {
        let render = try Self.png(white: 0.93)
        let large = Walkbook.CaptureState(theme: .light, dynamicTypeSize: "xxl")
        let largeDark = Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "xxl")

        let collision = StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: large, screenshot: render),
            ],
            instead: .captured,
            deviceAppearance: .light
        )
        let mixed = try StateApplicationCheck.filing(
            for: [
                StateApplicationCheck.Evidence(state: Self.light, screenshot: render),
                StateApplicationCheck.Evidence(state: large, screenshot: render),
                StateApplicationCheck.Evidence(state: Self.dark, screenshot: Self.png(white: 0.93, tick: true)),
                StateApplicationCheck.Evidence(state: largeDark, screenshot: Self.png(white: 0.6)),
            ],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(collision.refused == [Self.light, large])
        #expect(collision.refusedOnAppearance.isEmpty)
        #expect(mixed.refused == [Self.light, large, Self.dark, largeDark])
        #expect(mixed.refusedOnAppearance == [Self.dark, largeDark])
        #expect(mixed.foldingWriteFailure("disk full").refusedOnAppearance == [Self.dark, largeDark])
    }

    /// The round-2 review's finding 5: a dark capture whose screenshot does not decode took part in neither appearance test, and was filed `captured` whatever the device drew.
    ///
    /// Now refused, beside a light capture or alone. Not on appearance: a settle cannot make a file decode, so it costs no reboot.
    @Test(arguments: [true, false])
    func adarkCaptureWhoseScreenshotDoesNotDecodeIsRefusedAndCostsNoSettle(withLightSibling: Bool) throws {
        let light = try [StateApplicationCheck.Evidence(state: Self.light, screenshot: Self.png(white: 0.93))]

        let filing = StateApplicationCheck.filing(
            for: (withLightSibling ? light : []) + [StateApplicationCheck.Evidence(state: Self.dark, screenshot: Data("not a png".utf8))],
            instead: .captured,
            deviceAppearance: .light
        )

        #expect(filing.kept == (withLightSibling ? [Self.light] : []))
        #expect(filing.refused == [Self.dark])
        #expect(filing.refusedOnAppearance.isEmpty)
        guard case let .stateNotApplied(reason) = filing.outcome else {
            Issue.record("a dark capture nothing shows to be dark must not keep a passing outcome, got \(filing.outcome)")
            return
        }
        #expect(reason.contains("state 'dark' has a screenshot that could not be decoded as an image"))
    }

    static let light = Walkbook.CaptureState(theme: .light)
    static let dark = Walkbook.CaptureState(theme: .dark)

    /// A solid PNG of a given brightness — the two artefacts a real screen produces, reduced to the one property this check reads.
    ///
    /// `tick` alters a single pixel, which is the status-bar clock: enough to make the files differ, nowhere near enough to change what the screen depicts. It is what separates this test from the byte-comparison ones above.
    static func png(white: Double, tick: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            sourceLocation: sourceLocation
        )
        context.setFillColor(red: white, green: white, blue: white, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        if tick {
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let image = try #require(context.makeImage(), sourceLocation: sourceLocation)
        let encoded = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil),
            sourceLocation: sourceLocation
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination), sourceLocation: sourceLocation)
        return encoded as Data
    }
}
