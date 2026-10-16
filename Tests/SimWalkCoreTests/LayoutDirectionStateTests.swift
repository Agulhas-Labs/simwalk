//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// The `layoutDirection` axis: its slug, its launch, and the artefact check that holds it to what the tree shows.
struct LayoutDirectionStateTests {
    /// G3: a state setting only the axes that existed before the three new ones slugs exactly as it did — every bundle on disk keeps its paths.
    @Test
    func aStateWithOnlyTheOldAxesSlugsExactlyAsBefore() {
        let plain = Walkbook.CaptureState(theme: .light)
        let every = Walkbook.CaptureState(
            theme: .dark,
            dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL",
            locale: "en_GB",
            arguments: ["a", "b"],
            environment: ["B": "2", "A": "1"]
        )

        #expect(plain.slug == "light")
        #expect(every.slug == "dark-dt_uictcontentsizecategoryaccessibilityl-loc_en_gb-args_facdde7a-env_a6df947a")
    }

    @Test
    func aDirectionAppendsAfterTheOldAxes() {
        let state = Walkbook.CaptureState(theme: .light, locale: "en_GB", layoutDirection: .rtl)

        #expect(state.slug == "light-loc_en_gb-rtl")
        #expect(Walkbook.CaptureState(theme: .light, layoutDirection: .ltr).slug == "light-ltr")
    }

    /// Both overrides, because on iOS 27 either one alone left an HStack running left to right.
    @Test
    func rightToLeftLaunchesWithBothOverrides() {
        let state = Walkbook.CaptureState(theme: .light, arguments: ["--seed"], layoutDirection: .rtl)

        #expect(state.launchArguments == ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES", "--seed"])
    }

    @Test
    func aMisspelledDirectionKeyIsRefusedWithTheLikelyOne() throws {
        let json = #"{"name":"w","appBundleID":"a","screens":[{"id":"s","route":[{"tab":{"label":"A"}}],"states":[{"theme":"light","layoutDirecton":"rtl"}]}]}"#

        let error = #expect(throws: WalkbookLoadError.self) { try WalkbookLoader.load(from: Data(json.utf8), source: "w") }

        let refusal = try "\(#require(error))"

        #expect(refusal.contains("'layoutDirecton'"))
        #expect(refusal.contains("'layoutDirection'"))
    }

    /// G5: an RTL-labelled capture whose tab buttons run left to right in tree order drew the device's own layout, and is refused rather than filed as a mirror.
    @Test
    func anRTLCaptureWhoseTabsRunLeftToRightIsRefused() {
        let rtl = Walkbook.CaptureState(theme: .light, layoutDirection: .rtl)
        let evidence = [StateApplicationCheck.Evidence(state: rtl, screenshot: Data([1]), tree: Self.tabBar(xs: [0, 134, 268]))]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured)
        let reason: String? = if case let .stateNotApplied(reason) = filing.outcome {
            reason
        } else {
            nil
        }

        #expect(reason?.contains("'light-rtl' asked to lay out right to left") == true)
        #expect(filing.refused == [rtl])
        #expect(filing.kept.isEmpty)
    }

    @Test
    func anRTLCaptureWhoseTabsRunRightToLeftIsKeptAndVerified() {
        let rtl = Walkbook.CaptureState(theme: .light, layoutDirection: .rtl)
        let ltr = Walkbook.CaptureState(theme: .light, layoutDirection: .ltr)
        let evidence = [
            StateApplicationCheck.Evidence(state: ltr, screenshot: Data([1]), tree: Self.tabBar(xs: [0, 134, 268])),
            StateApplicationCheck.Evidence(state: rtl, screenshot: Data([2]), tree: Self.tabBar(xs: [268, 134, 0])),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured)

        #expect(filing.outcome == .captured)
        #expect(filing.kept == [ltr, rtl])
        #expect(filing.unverified.isEmpty)
    }

    /// A screen with nothing side by side has nothing to judge by: filed, and named as set and unverified — never passed.
    @Test
    func anRTLCaptureWithNoHorizontalRunIsFiledUnverified() {
        let rtl = Walkbook.CaptureState(theme: .light, layoutDirection: .rtl)
        let column = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 100, width: 80, height: 20), label: "One"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 20, y: 140, width: 80, height: 20), label: "Two"),
        ])

        let filing = StateApplicationCheck.filing(
            for: [StateApplicationCheck.Evidence(state: rtl, screenshot: Data([1]), tree: column)],
            instead: .captured
        )

        #expect(filing.outcome == .captured)
        #expect(filing.unverified == [StateApplicationCheck.Unverified(state: rtl, axes: ["layoutDirection"])])
    }

    /// SimWalk#18 on the direction axis: on an `en_US` device the plain state already lays out left to right, so `light-ltr` asks for what it got and one picture is the right result — both kept, `light-ltr` identical to its base, nothing refused.
    @Test
    func anLTRStateTheDeviceAlreadyLaysOutIsKeptAsIdenticalToItsBase() throws {
        let ltr = Walkbook.CaptureState(theme: .light, layoutDirection: .ltr)
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render, tree: Self.tabBar(xs: [0, 134, 268])),
            StateApplicationCheck.Evidence(state: ltr, screenshot: render, tree: Self.tabBar(xs: [0, 134, 268])),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        #expect(filing.outcome == .captured)
        #expect(filing.refused.isEmpty)
        #expect(filing.kept == [StateApplicationCheckTests.light, ltr])
        #expect(filing.identicalToBase == [StateApplicationCheck.Equivalence(state: ltr, base: StateApplicationCheckTests.light)])
    }

    /// A mirror-symmetric screen draws one picture both ways round, so identity cannot judge the direction: the plain state is kept, and `light-rtl` is left to its frames — with nothing side by side, filed unverified rather than refused beside the plain state.
    @Test
    func anRTLStateOnAMirrorSymmetricScreenIsFiledUnverifiedBesideThePlainOne() throws {
        let rtl = Walkbook.CaptureState(theme: .light, layoutDirection: .rtl)
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: StateApplicationCheckTests.light, screenshot: render, tree: Self.centred),
            StateApplicationCheck.Evidence(state: rtl, screenshot: render, tree: Self.centred),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        #expect(filing.outcome == .captured)
        #expect(filing.refused.isEmpty)
        #expect(filing.kept == [StateApplicationCheckTests.light, rtl])
        #expect(filing.identicalToBase.isEmpty)
        #expect(filing.unverified == [StateApplicationCheck.Unverified(state: rtl, axes: ["layoutDirection"])])
    }

    /// An unset direction is the language's, not always left to right: an Arabic state lays out right to left, so its `-ltr` sibling asked for something else and one picture does not make it identical to its base — it is left to its frames, and filed unverified.
    @Test
    func anLTRStateBesideARightToLeftLocaleIsNotIdenticalToItsBase() throws {
        let arabic = Walkbook.CaptureState(theme: .light, locale: "ar_SA")
        let ltr = Walkbook.CaptureState(theme: .light, locale: "ar_SA", layoutDirection: .ltr)
        let render = try StateApplicationCheckTests.png(white: 0.93)
        let evidence = [
            StateApplicationCheck.Evidence(state: arabic, screenshot: render, tree: Self.centred),
            StateApplicationCheck.Evidence(state: ltr, screenshot: render, tree: Self.centred),
        ]

        let filing = StateApplicationCheck.filing(for: evidence, instead: .captured, deviceAppearance: .light, deviceLocale: "en_US")

        #expect(filing.identicalToBase.isEmpty)
        #expect(filing.unverified == [StateApplicationCheck.Unverified(state: ltr, axes: ["layoutDirection"])])
    }

    /// A screen whose only content is one centred label: nothing side by side, so no run to judge a direction by.
    private static let centred = AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [
        AXNode(type: "StaticText", frame: AXNode.Frame(x: 161, y: 420, width: 80, height: 20), label: "Centred"),
    ])

    /// A tab bar of three buttons at `xs`, listed in that tree order.
    private static func tabBar(xs: [Double]) -> AXNode {
        AXNode(type: "TabBar", frame: AXNode.Frame(x: 0, y: 790, width: 402, height: 84), children: xs.enumerated().map { index, x in
            AXNode(type: "Button", frame: AXNode.Frame(x: x, y: 800, width: 134, height: 50), label: "Tab \(index)")
        })
    }
}
