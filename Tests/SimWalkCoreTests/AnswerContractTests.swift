//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The shape every answer takes, pinned where it is decided rather than at each face: the header first, the verdict word second and mapped to the exit code a pipeline reads, the residue after it, and what the answer saved on the last line.
///
/// The contract itself is written down in the sift repository's `Docs/AnswerContract.md`; these are its clauses as this tool implements them.
struct AnswerContractTests {
    /// The verdict word and the exit code are one value, so a face cannot print "qualified" and exit as though nothing were.
    @Test
    func eachVerdictWordMapsToTheExitCodeTheReadmeDefines() {
        #expect(AnswerVerdict.unqualified("1 of 1 screens captured · 3 captures").line == "ok — 1 of 1 screens captured · 3 captures")
        #expect(AnswerVerdict.unqualified("").exitCode == 0)

        let qualified = AnswerVerdict.qualified(["2 captures taken before the tree settled", "1 screen unreachable"], detail: "1 of 2 screens captured · 2 captures")
        #expect(qualified.line == "qualified — 2 captures taken before the tree settled; 1 screen unreachable · 1 of 2 screens captured · 2 captures")
        #expect(qualified.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(qualified.isQualified)

        #expect(AnswerVerdict.refused("no manifest here").line == "refused — no manifest here")
        #expect(AnswerVerdict.refused("").exitCode == AnswerVerdict.refusedExitCode)
        #expect(!AnswerVerdict.refused("").isQualified)
    }

    /// "No qualifications" and "ok" are the same fact, so one constructor decides it rather than every face deciding it again.
    @Test
    func ananswerWithNoQualificationsIsOkAndOneWithAnyIsQualified() {
        #expect(AnswerVerdict.reporting(qualifications: [], detail: "d") == .unqualified("d"))
        #expect(AnswerVerdict.reporting(qualifications: ["x"], detail: "d") == .qualified(["x"], detail: "d"))
    }

    /// The header names what the answer was measured against — the plan by name, the app, the build, the plan's hash, the device — and never a date or a machine name, which is the contract's wording rule and the reason a bundle read a week later on another machine still reads.
    @Test
    func abundleHeaderNamesThePlanTheAppTheBuildTheDeviceAndWhatSettled() {
        let header = CaptureBundleHeader.line(CaptureBundleTests.manifest())

        #expect(header == "\(Self.header)  settled: unrecorded")
    }

    /// The device placeholder is not a build hash, and the header must not cut it to `device-u` as if it were.
    @Test
    func aDeviceBundlesHeaderSaysTheBuildIsUnread() {
        var manifest = CaptureBundleTests.manifest()
        manifest.appBuildHash = AppBuildIdentity.unreadOnDevice

        let header = CaptureBundleHeader.line(manifest)

        #expect(header.contains("build: unread (device)  walkbook:"))
        #expect(!header.contains("device-u"))
    }

    /// A hash tells two runs apart; it does not tell a reader *what they are looking at*.
    ///
    /// Two bundles of different apps briefly answered identically but for a hash nobody can read as a name.
    @Test
    func twoBundlesOfDifferentAppsDoNotAnswerAlike() {
        var other = CaptureBundleTests.manifest()
        other.appBundleID = "dev.simwalk.permission-fixture"

        let mine = CaptureBundleHeader.line(CaptureBundleTests.manifest())
        let theirs = CaptureBundleHeader.line(other)

        #expect(mine != theirs)
        #expect(mine.contains("app: dev.simwalk.route-fixture"))
        #expect(theirs.contains("app: dev.simwalk.permission-fixture"))
    }

    /// And two walks of one app under different plans are told apart by name, not only by a hash.
    @Test
    func twoWalksOfOneAppAreNamedRatherThanOnlyHashed() {
        var other = CaptureBundleTests.manifest()
        other.walkName = "example-smoke"

        #expect(CaptureBundleHeader.line(CaptureBundleTests.manifest()).contains("walk: 'example-validation'"))
        #expect(CaptureBundleHeader.line(other).contains("walk: 'example-smoke'"))
    }

    /// A bundle that recorded settling states the fraction; one that recorded it for only some of its captures states both figures, because an unrecorded capture is neither settled nor unsettled and folding it into either number is the silent under-report §6 forbids.
    @Test
    func theHeaderCountsWhatSettledAndDeclaresWhatWasNeverRecorded() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captured,
                routeTaken: [.tab(label: "Today")],
                captures: [
                    CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light), axTreeSettled: true),
                    CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .dark), axTreeSettled: false),
                ]
            ),
        ]

        #expect(CaptureBundleHeader.line(manifest).contains("settled: 1/2"))

        var withUnrecorded = manifest
        withUnrecorded.screens = [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captured,
                routeTaken: [.tab(label: "Today")],
                captures: manifest.screens[0].captures + [
                    CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL")),
                ]
            ),
        ]
        #expect(CaptureBundleHeader.line(withUnrecorded).contains("settled: 1/3 (1 unrecorded)"))
    }

    /// The animation state sits between the device and the settle count when the bundle records it, and is absent when it does not (SimWalk#154).
    @Test
    func theHeaderNamesTheAnimationStateOnlyWhenRecorded() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = []

        #expect(!CaptureBundleHeader.line(manifest).contains("animations"))

        manifest.animations = .disabled
        #expect(CaptureBundleHeader.line(manifest).contains("device: iPhone 17 Pro (26.0)  animations: off  settled: no captures"))

        manifest.animations = .enabled
        #expect(CaptureBundleHeader.line(manifest).contains("device: iPhone 17 Pro (26.0)  animations: on  settled: no captures"))
    }

    /// A bundle holding no captures at all is not a bundle whose captures failed to settle.
    @Test
    func aBundleWithNoCapturesSaysSoRatherThanReportingNoneSettled() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [CaptureManifest.ScreenRecord(id: "today", outcome: .unreachable(routeTried: []), routeTaken: [])]

        #expect(CaptureBundleHeader.line(manifest).contains("settled: no captures"))
    }

    /// The four parts in their four places, over a bundle that is really on disk so the last line is really measured.
    @Test
    func abundleAnswerIsHeaderThenVerdictThenResidueThenTheSaving() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])

        let lines = CaptureBundleSummary(bundle).render().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // The fixture writes its own walk name; everything after it is the same header shape.
        #expect(lines[0] == "walk: 'audit'  app: dev.simwalk.route-fixture  build: a1b2c3d4  walkbook: 0f1e2d3c  device: iPhone 17 Pro (26.0)  settled: 1/1")
        #expect(lines[1] == "ok — 1 of 1 screens captured · 1 capture")
        #expect(lines[2] == "  1 progress — captured [light] via tab 'Progress'")
        #expect(lines.last?.contains("tokens saved — 1 screenshot (~4.1k at the 2576 px cap)") == true)
        #expect(lines.last?.hasSuffix("A floor: only what this answer stood in for is counted.") == true)
    }

    /// The served figure is the answer's own size *including the line that states it and the newline a face writes after it*, so a reader checking the arithmetic against `wc -c` finds the number they were given.
    ///
    /// It was a byte under, which is small and is wrong in the flattering direction — and it made a claim the README and the Brief both make ("matches `wc -c`") literally false.
    @Test
    func theSavingIsPricedAgainstTheAnswerAsAfaceWritesIt() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark), tree: CaptureBundleFixture.plainScreen()),
        ])
        let answer = CaptureBundleSummary(bundle).answer()

        let saving = try #require(answer.saving)

        // Exactly what `StandardStreams.emit` puts on the wire, which is what `wc -c` counts.
        #expect(saving.servedBytes == (answer.text + "\n").utf8.count)
        #expect(answer.text.contains("against \(ByteSize.short(saving.servedBytes)) served"))
    }

    /// The manifest fixture's own header, up to the field each case asserts for itself.
    private static var header: String {
        "walk: 'example-validation'  app: dev.simwalk.route-fixture  build: a1b2c3d4  walkbook: 0f1e2d3c  device: iPhone 17 Pro (26.0)"
    }

    /// An answer that stands in for nothing carries no last line at all, rather than one claiming a saving of zero.
    @Test
    func ananswerThatStandsInForNothingCarriesNoContextLine() {
        let answer = Answer(header: "walkbook: abcd1234  screens: 1  steps: 1", verdict: .unqualified("nothing to weigh"))

        #expect(answer.saving == nil)
        #expect(answer.text == "walkbook: abcd1234  screens: 1  steps: 1\nok — nothing to weigh")
    }
}
