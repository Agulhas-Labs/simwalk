//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The `orientation` axis (SimWalk#199): its slug, its decoding, and the root-frame check that holds it to what the app laid out in.
struct OrientationStateTests {
    /// A state that sets no orientation slugs exactly as it did before the axis existed — every bundle on disk keeps its paths.
    @Test
    func aStateWithOnlyTheOlderAxesSlugsExactlyAsBefore() throws {
        let every = Walkbook.CaptureState(
            theme: .dark,
            dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL",
            locale: "en_GB",
            arguments: ["a", "b"],
            environment: ["B": "2", "A": "1"]
        )
        let decoded = try JSONDecoder().decode(Walkbook.CaptureState.self, from: Data(#"{"theme":"light","layoutDirection":"rtl"}"#.utf8))

        #expect(Walkbook.CaptureState(theme: .light).slug == "light")
        #expect(every.slug == "dark-dt_uictcontentsizecategoryaccessibilityl-loc_en_gb-args_facdde7a-env_a6df947a")
        #expect(decoded.orientation == nil)
        #expect(decoded.slug == "light-rtl")
    }

    /// The value itself, after every older axis — `reset_` included — so adding the axis moves no existing directory.
    @Test
    func anOrientationAppendsAfterEveryOlderAxis() {
        var state = Walkbook.CaptureState(
            theme: .light,
            locale: "en_GB",
            layoutDirection: .rtl,
            location: Walkbook.Location(latitude: 51.5, longitude: -0.12),
            resetPermissions: ["photos"]
        )
        let without = state.slug
        state.orientation = .landscape

        #expect(state.slug == "\(without)-landscape")
        #expect(Walkbook.CaptureState(theme: .light, orientation: .portrait).slug == "light-portrait")
    }

    @Test
    func aMisspelledOrientationKeyIsRefusedWithTheLikelyOne() throws {
        let refusal = try Self.refusal(loading: #"{"theme":"light","orientaton":"landscape"}"#)

        #expect(refusal.contains("'orientaton'"))
        #expect(refusal.contains("'orientation'"))
    }

    /// `validate` refuses `"orientation": "sideways"` naming the value, so an author sees what they wrote rather than a decoding failure about some state.
    @Test
    func anUnknownOrientationIsRefusedNamingIt() throws {
        let refusal = try Self.refusal(loading: #"{"theme":"light","orientation":"sideways"}"#)

        #expect(refusal.contains("sideways"))
        #expect(refusal.contains("orientation"))
    }

    /// A portrait-only app asked for landscape keeps its portrait frame: refused, naming the frame it kept, rather than filed as a landscape capture.
    @Test
    func aLandscapeCaptureWhoseRootFrameIsPortraitIsRefusedNamingTheFrame() {
        let landscape = Walkbook.CaptureState(theme: .light, orientation: .landscape)
        let evidence = [StateApplicationCheck.Evidence(state: landscape, screenshot: Data([1]), tree: Self.app(width: 402, height: 874))]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured)
        let reason: String? = if case let .stateNotApplied(reason) = filing.outcome {
            reason
        } else {
            nil
        }

        #expect(reason?.contains("'light-landscape' asked for landscape and the app kept a 402×874 pt frame (portrait)") == true)
        #expect(filing.refused == [landscape])
        #expect(filing.kept.isEmpty)
    }

    @Test
    func aLandscapeCaptureWhoseRootFrameIsLandscapeIsKeptAndVerified() {
        let landscape = Walkbook.CaptureState(theme: .light, orientation: .landscape)
        let evidence = [StateApplicationCheck.Evidence(state: landscape, screenshot: Data([1]), tree: Self.app(width: 874, height: 402))]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured)

        #expect(filing.outcome == .captured)
        #expect(filing.kept == [landscape])
        #expect(filing.unverified.isEmpty)
    }

    /// A square or empty root frame, or no tree at all, has nothing to judge by: filed, and named as set and unverified — never passed.
    @Test(arguments: [
        OrientationStateTests.app(width: 600, height: 600),
        OrientationStateTests.app(width: 0, height: 0),
        nil,
    ])
    func aCaptureWhoseRootFrameCannotJudgeIsFiledUnverified(tree: AXNode?) {
        let landscape = Walkbook.CaptureState(theme: .light, orientation: .landscape)

        let filing = StateApplicationCheck.filing(
            for: [StateApplicationCheck.Evidence(state: landscape, screenshot: Data([1]), tree: tree)],
            instead: .captured
        )

        #expect(filing.outcome == .captured)
        #expect(filing.kept == [landscape])
        #expect(filing.unverified == [StateApplicationCheck.Unverified(state: landscape, axes: ["orientation"])])
    }

    /// The `layoutDirection: nil` against `ltr` trap on this axis: on a portrait device the plain state is already portrait, so `light-portrait` asks for what it got and one picture is the right result — both kept, `light-portrait` identical to its base, nothing refused.
    @Test
    func aPortraitStateTheDeviceIsAlreadyInIsKeptAsIdenticalToItsBase() throws {
        let portrait = Walkbook.CaptureState(theme: .light, orientation: .portrait)
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render, tree: Self.app(width: 402, height: 874)),
            StateApplicationCheck.Evidence(state: portrait, screenshot: render, tree: Self.app(width: 402, height: 874)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        #expect(filing.outcome == .captured)
        #expect(filing.refused.isEmpty)
        #expect(filing.kept == [StateApplicationCheckTests.light, portrait])
        #expect(filing.identicalToBase == [StateApplicationCheck.Equivalence(state: portrait, base: StateApplicationCheckTests.light)])
        #expect(filing.unverified.isEmpty)
    }

    /// A portrait-only app draws one picture under both states, and only the one that asked for landscape is wrong: it is refused by its frame, and the plain state beside it, which asked for nothing it did not get, is kept rather than refused with it as a collision.
    @Test
    func aPortraitOnlyAppRefusesOnlyTheLandscapeStateBesideThePlainOne() throws {
        let landscape = Walkbook.CaptureState(theme: .light, orientation: .landscape)
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render, tree: Self.app(width: 402, height: 874)),
            StateApplicationCheck.Evidence(state: landscape, screenshot: render, tree: Self.app(width: 402, height: 874)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        #expect(filing.refused == [landscape])
        #expect(filing.kept == [StateApplicationCheckTests.light])
        #expect(filing.identicalToBase.isEmpty)
    }

    /// SimWalk#217: a byte-identical pair that differs in theme and in a contradicted orientation is not refused whole — the landscape state's orientation is read as the frame's for the collision, so the appearance finding judges the pair, and `light`, which applied, is kept.
    @Test
    func aDarkLandscapeStateOnAPortraitOnlyAppThatIgnoresDarkIsRefusedAloneBesideLight() throws {
        let darkLandscape = Walkbook.CaptureState(theme: .dark, orientation: .landscape)
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render, tree: Self.app(width: 402, height: 874)),
            StateApplicationCheck.Evidence(state: darkLandscape, screenshot: render, tree: Self.app(width: 402, height: 874)),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        let reason: String? = if case let .stateNotApplied(reason) = filing.outcome {
            reason
        } else {
            nil
        }

        #expect(filing.refused == [darkLandscape])
        #expect(filing.kept == [StateApplicationCheckTests.light])
        #expect(reason?.contains("state the device discarded in silence") == false)
        #expect(filing.identicalToBase.isEmpty)
    }

    @Test
    func theRootFrameIsJudgedByItsShape() {
        #expect(OrientationCheck.judged(AXNode.Frame(x: 0, y: 0, width: 874, height: 402)) == .landscape)
        #expect(OrientationCheck.judged(AXNode.Frame(x: 0, y: 0, width: 402, height: 874)) == .portrait)
        #expect(OrientationCheck.judged(AXNode.Frame(x: 0, y: 0, width: 600, height: 600)) == nil)
        #expect(OrientationCheck.judged(AXNode.Frame(x: 0, y: 0, width: 0, height: 874)) == nil)
    }

    /// The clause a live session's start and a walk's refusal share, and nothing when the frame agrees or cannot judge.
    @Test
    func theRefusalNamesTheFrameOnlyWhenItContradictsTheState() {
        let portrait = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

        #expect(OrientationCheck.refusal(stated: .landscape, frame: portrait) == "asked for landscape and the app kept a 402×874 pt frame (portrait)")
        #expect(OrientationCheck.refusal(stated: .portrait, frame: AXNode.Frame(x: 0, y: 0, width: 1376, height: 1032)) == "asked for portrait and the app kept a 1376×1032 pt frame (landscape)")
        #expect(OrientationCheck.refusal(stated: .portrait, frame: portrait) == nil)
        #expect(OrientationCheck.refusal(stated: .landscape, frame: AXNode.Frame(x: 0, y: 0, width: 600, height: 600)) == nil)
    }

    /// The description of the error loading a one-screen walkbook whose only state is `state` throws.
    private static func refusal(loading state: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let json = #"{"name":"w","appBundleID":"a","screens":[{"id":"s","route":[{"tab":{"label":"A"}}],"states":["# + state + #"]}]}"#
        let error = #expect(throws: WalkbookLoadError.self, sourceLocation: sourceLocation) { try WalkbookLoader.load(from: Data(json.utf8), source: "w") }
        return try "\(#require(error, sourceLocation: sourceLocation))"
    }

    /// An app element whose frame is `width`×`height` points, holding one label — the root a capture's tree hangs from.
    private static func app(width: Double, height: Double) -> AXNode {
        AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: width, height: height), children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 80, height: 20), label: "Home"),
        ])
    }
}
