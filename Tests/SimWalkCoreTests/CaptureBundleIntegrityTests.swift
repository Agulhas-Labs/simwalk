//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// A bundle may not claim more than it holds.
///
/// There are two ways it could: a manifest that contradicts itself, and a manifest naming artefacts the directory does not have — the second being exactly what an interrupted run leaves behind.
struct CaptureBundleIntegrityTests {
    @Test
    func anInterruptedRunRefusesRatherThanInspectingAsAPass() throws {
        let directory = try TemporaryDirectory()
        let url = try CaptureBundleTests.writtenBundle(in: directory).url
        try FileManager.default.removeItem(at: url.appendingPathComponent("screens/today/dark/screen.png"))

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })

        #expect(thrown.description.contains("screens/today/dark/screen.png"))
        #expect(thrown.description.contains("which is not in the bundle"))
    }

    @Test
    func finalisingRefusesAManifestWhoseArtefactsWereNeverWritten() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("partial.\(CaptureBundleLayout.directoryExtension)")
        let writer = try CaptureBundleWriter(preparingAt: url)
        let manifest = CaptureBundleTests.manifest()
        for capture in manifest.screens[0].captures {
            try writer.prepareDirectory(screenID: manifest.screens[0].id, state: capture.state)
        }

        #expect(throws: CaptureBundleError.self) {
            try writer.finalise(manifest)
        }
    }

    @Test
    func aManifestIsNotWrittenAtAllWhenFinalisingRefuses() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("partial.\(CaptureBundleLayout.directoryExtension)")
        let writer = try CaptureBundleWriter(preparingAt: url)

        #expect(throws: CaptureBundleError.self) {
            try writer.finalise(CaptureBundleTests.manifest())
        }

        #expect(!FileManager.default.fileExists(atPath: CaptureBundle.manifestURL(in: url).path))
    }

    @Test
    func aScreenRecordedAsCapturedWithNoCapturesIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(id: "today", outcome: .captured, routeTaken: [.tab(label: "Today")]),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.capturedWithoutCaptures(screenID: "today")])
    }

    @Test
    func aRefusalCarryingCapturesIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "power-detail",
                outcome: .unreachable(routeTried: [.tab(label: "Workouts")]),
                routeTaken: [.tab(label: "Workouts")],
                captures: [CaptureManifest.StateCapture(screenID: "power-detail", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.refusalWithCaptures(screenID: "power-detail", count: 1)])
    }

    /// The point of refusing a screen whose states cannot all have applied is that none of its evidence is filed; a record carrying some anyway is claiming exactly what the refusal denies.
    @Test
    func astateNotAppliedRefusalCarryingCapturesIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "browse",
                outcome: .stateNotApplied(reason: "states 'light' and 'dark' produced byte-identical screenshots"),
                routeTaken: [.tab(label: "Browse")],
                captures: [CaptureManifest.StateCapture(screenID: "browse", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.refusalWithCaptures(screenID: "browse", count: 1)])
    }

    /// A capture recorded identical to its base can be checked only against the base's own capture, so naming a state the screen did not capture — or itself — is a claim nothing can check (SimWalk#18).
    @Test(arguments: ["dark", "light-loc_en_gb"])
    func acaptureIdenticalToAStateTheScreenDidNotCaptureIsAProblem(names: String) {
        let british = Walkbook.CaptureState(theme: .light, locale: "en_GB")
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "you",
                outcome: .captured,
                routeTaken: [.tab(label: "You")],
                captures: [
                    CaptureManifest.StateCapture(screenID: "you", state: Walkbook.CaptureState(theme: .light)),
                    CaptureManifest.StateCapture(screenID: "you", state: british, identicalTo: names),
                ]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.identicalToUncapturedState(screenID: "you", slug: "light-loc_en_gb", names: names)])
    }

    /// SimWalk#15: a refusal that names the states it refused may file the rest — which is what lets a dark state the device ignored stop taking the light one with it.
    @Test
    func astateNotAppliedRefusalNamingItsRefusedStatesMayCarryTheRest() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
                routeTaken: [.tab(label: "Progress")],
                captures: [CaptureManifest.StateCapture(screenID: "progress", state: Walkbook.CaptureState(theme: .light))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest).isEmpty)
    }

    /// A screen that refused a state does not hold what was asked for, so a passing verdict beside a refusal list is the contradiction the per-state refusal must never be allowed to become.
    @Test
    func refusedStatesUnderAPassingOutcomeIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .captured,
                routeTaken: [.tab(label: "Progress")],
                captures: [CaptureManifest.StateCapture(screenID: "progress", state: Walkbook.CaptureState(theme: .light))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.refusedStatesOutsideRefusal(screenID: "progress")])
    }

    /// One state cannot be both filed and refused — its evidence was either attributable or it was not.
    @Test
    func astateBothCapturedAndRefusedIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
                routeTaken: [.tab(label: "Progress")],
                captures: [CaptureManifest.StateCapture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.stateCapturedAndRefused(screenID: "progress", slug: "dark")])
    }

    /// A decoded `"refusedStates": []` names nothing, so it licenses nothing: the captures beside it are held to the whole-screen rule, and the empty list is itself reported — the writer never produces one.
    @Test
    func anEmptyRefusedStatesListLicensesNoCaptures() throws {
        let written = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
                routeTaken: [.tab(label: "Progress")],
                captures: [CaptureManifest.StateCapture(screenID: "progress", state: Walkbook.CaptureState(theme: .light))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ])
        var json = try #require(JSONSerialization.jsonObject(with: CaptureBundle.encoder().encode(written)) as? [String: Any])
        var screens = try #require(json["screens"] as? [[String: Any]])
        screens[0]["refusedStates"] = [Any]()
        json["screens"] = screens

        let decoded = try CaptureBundle.decoder().decode(CaptureManifest.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.screens[0].refusedStates == [])
        #expect(CaptureManifestValidator.problems(in: decoded) == [
            .refusalWithCaptures(screenID: "progress", count: 1),
            .emptyRefusedStates(screenID: "progress"),
        ])
    }

    /// One state is refused once; a list naming it twice is a record no walk wrote.
    @Test
    func aStateRefusedTwiceIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
                routeTaken: [.tab(label: "Progress")],
                refusedStates: [Walkbook.CaptureState(theme: .dark), Walkbook.CaptureState(theme: .dark)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.duplicateRefusedState(screenID: "progress", slug: "dark", occurrences: 2)])
    }

    /// Refused states arrived in format 4; a format-3 manifest carrying them was not written by any walk of this tool.
    @Test
    func refusedStatesInAFormatBeforeTheirsAreAProblem() {
        let current = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
                routeTaken: [.tab(label: "Progress")],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ])
        let older = CaptureManifest(
            formatVersion: 3,
            walkName: current.walkName,
            appBundleID: current.appBundleID,
            appBuildHash: current.appBuildHash,
            walkbookHash: current.walkbookHash,
            device: current.device,
            startedAt: current.startedAt,
            finishedAt: current.finishedAt,
            screens: current.screens
        )

        #expect(CaptureManifestValidator.problems(in: current).isEmpty)
        #expect(CaptureManifestValidator.problems(in: older) == [.refusedStatesBeforeTheirFormat(screenID: "progress", formatVersion: 3)])
    }

    /// A refusal that names no states is the vacuous verdict in its newest clothes: nothing about it tells an author which two captures collided.
    @Test
    func astateNotAppliedRefusalWithNoReasonIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(id: "browse", outcome: .stateNotApplied(reason: "  "), routeTaken: [.tab(label: "Browse")]),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.blankFailureReason(screenID: "browse")])
    }

    @Test
    func aBuildMismatchCarryingCapturesIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "sleep-detail",
                outcome: .buildMismatch(expected: "a1b2c3d4", found: "58ebbd24"),
                routeTaken: [],
                captures: [CaptureManifest.StateCapture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.refusalWithCaptures(screenID: "sleep-detail", count: 1)])
    }

    @Test
    func twoScreenRecordsWithOneIDIsAProblem() {
        let record = CaptureManifest.ScreenRecord(
            id: "today",
            outcome: .captured,
            routeTaken: [.tab(label: "Today")],
            captures: [CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light))]
        )
        let manifest = Self.manifest(screens: [record, record])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.duplicateScreenID(id: "today", occurrences: 2)])
    }

    /// Two captures of one state derive the same two paths, so the misfiled check compares each stated path to the path it is identical to and the existence check finds the one real file — the bundle claimed two captures over one screenshot and every check agreed.
    @Test
    func aScreenClaimingOneStateTwiceIsAProblem() {
        let state = Walkbook.CaptureState(theme: .light)
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captured,
                routeTaken: [.tab(label: "Today")],
                captures: [
                    CaptureManifest.StateCapture(screenID: "today", state: state),
                    CaptureManifest.StateCapture(screenID: "today", state: state),
                ]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.duplicateCaptureState(screenID: "today", slug: "light", occurrences: 2)])
    }

    /// The walkbook validator reports every one of these; the manifest validator reported none, so a bundle attributable to nothing, holding nothing, that finished before it started, was a clean read.
    @Test
    func aManifestThatAttestsToNothingIsRefusedFieldByField() {
        let manifest = CaptureManifest(
            walkName: " ",
            appBundleID: "",
            appBuildHash: "",
            walkbookHash: "",
            device: CaptureManifest.Device(name: "", udid: "", osVersion: ""),
            startedAt: Date(timeIntervalSince1970: 1_786_867_440),
            finishedAt: Date(timeIntervalSince1970: 1_786_867_200),
            screens: []
        )

        let problems = CaptureManifestValidator.problems(in: manifest)

        #expect(problems == [
            .blankIdentityField(name: "walkName"),
            .blankIdentityField(name: "appBundleID"),
            .blankIdentityField(name: "appBuildHash"),
            .blankIdentityField(name: "walkbookHash"),
            .blankIdentityField(name: "device.name"),
            .blankIdentityField(name: "device.udid"),
            .blankIdentityField(name: "device.osVersion"),
            .noScreens,
            .finishedBeforeStarted(startedAt: manifest.startedAt, finishedAt: manifest.finishedAt),
        ])
    }

    /// A blank screen id derived `screens//light/screen.png`, and resolving it dropped the empty component — so the screen level vanished and a *state* slug stood where a screen belongs, with the stated path equal to the derived one at every check.
    @Test
    func aScreenRecordWithABlankIDIsReportedByItsPosition() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "",
                outcome: .captured,
                routeTaken: [.tab(label: "Today")],
                captures: [CaptureManifest.StateCapture(screenID: "", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.blankScreenID(index: 0)])
    }

    @Test
    func aBlankScreenIDStillDerivesAPathThatKeepsItsScreenLevel() {
        let capture = CaptureManifest.StateCapture(screenID: "", state: Walkbook.CaptureState(theme: .light))
        let resolved = CaptureBundleLayout.url(forRelativePath: capture.screenshotPath, in: URL(fileURLWithPath: "/tmp/b"))

        #expect(!capture.screenshotPath.contains("//"))
        #expect(resolved.path == "/tmp/b/screens/_/light/screen.png")
    }

    /// `routeTaken` is what the runner completed and `routeTried` what it attempted, so the first is the leading part of the second.
    ///
    /// Unconstrained, the manifest answered "what did the runner do" twice and nothing could say which answer was the honest one.
    @Test
    func aCompletedRouteThatIsNotTheStartOfTheAttemptedOneIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "power-detail",
                outcome: .unreachable(routeTried: [.tab(label: "Workouts"), .tap(label: "Power")]),
                routeTaken: [.tab(label: "Today")]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [
            .routeTakenIsNotAPrefixOfRouteTried(
                screenID: "power-detail",
                taken: [.tab(label: "Today")],
                tried: [.tab(label: "Workouts"), .tap(label: "Power")]
            ),
        ])
    }

    /// A bound element names the step that bound it, so the step must be one the screen took (SimWalk#96 item 10).
    @Test
    func aBoundElementOnAStepBeyondTheRouteIsAProblem() {
        let route: [Walkbook.RouteStep] = [.tab(label: "Today"), .tap(label: "Power")]
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "power-detail",
                outcome: .unreachable(routeTried: route),
                routeTaken: route,
                boundElements: [Self.bound(step: 2)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [
            .boundElementStepOutOfRange(screenID: "power-detail", step: 2, routeLength: 2),
        ])
    }

    /// Only a `tap`, `scrollTo`, `type` or `longPress` step binds an element, so a record on a `tab` step was not written by a walk (SimWalk#96 item 10).
    @Test
    func aBoundElementOnAStepThatBindsNothingIsAProblem() {
        let route: [Walkbook.RouteStep] = [.tab(label: "Today"), .tap(label: "Power")]
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "power-detail",
                outcome: .unreachable(routeTried: route),
                routeTaken: route,
                boundElements: [Self.bound(step: 0), Self.bound(step: 1)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [
            .boundElementOnStepThatBindsNothing(screenID: "power-detail", step: 0, routeStep: .tab(label: "Today")),
        ])
    }

    /// A `longPress` binds the element it pressed, so a record on its step is one a walk writes (SimWalk#198).
    @Test
    func aBoundElementOnALongPressStepIsNotAProblem() {
        let route: [Walkbook.RouteStep] = [.longPress(label: "Power", seconds: 1)]
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "power-detail",
                outcome: .unreachable(routeTried: route),
                routeTaken: route,
                boundElements: [Self.bound(step: 0)]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest).isEmpty)
    }

    private static func bound(step: Int) -> CaptureManifest.BoundElement {
        CaptureManifest.BoundElement(step: step, type: "Button", identifier: nil, label: "Power", frame: AXNode.Frame(x: 0, y: 0, width: 10, height: 10))
    }

    /// A capture failure may legitimately carry the states it did record — "reached, got light, failed on dark" holds one capture and the bundle must be free to say so.
    @Test
    func aPartialCaptureIsNotAContradiction() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captureFailed(reason: "state 'dark': no space left on device"),
                routeTaken: [.tab(label: "Today")],
                captures: [CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light))]
            ),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest).isEmpty)
    }

    @Test
    func aCaptureFailureThatNamesNoReasonIsAProblem() {
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(id: "today", outcome: .captureFailed(reason: "  "), routeTaken: [.tab(label: "Today")]),
        ])

        #expect(CaptureManifestValidator.problems(in: manifest) == [.blankFailureReason(screenID: "today")])
    }

    @Test
    func aSelfContradictoryManifestIsRefusedWhenRead() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("vacuous.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let manifest = Self.manifest(screens: [
            CaptureManifest.ScreenRecord(id: "today", outcome: .captured, routeTaken: [.tab(label: "Today")]),
        ])
        try CaptureBundle.encoder().encode(manifest).write(to: CaptureBundle.manifestURL(in: url))

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })

        #expect(thrown.description.contains("a pass with no evidence is not a pass"))
    }

    @Test
    func preparingOverAnExistingBundleRefusesRatherThanValidatingOnThePreviousRun() throws {
        let directory = try TemporaryDirectory()
        let url = try CaptureBundleTests.writtenBundle(in: directory).url

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundleWriter(preparingAt: url)
        })

        #expect(thrown.description.contains("already holds"))
    }

    /// `try? contentsOfDirectory` read an unlistable directory as an empty one, which fails open on exactly what the guard exists to catch — a stale bundle whose artefacts this process cannot see, which `finalise` would then confirm for the wrong walk.
    @Test
    func preparingIntoADirectoryItCannotListRefusesRatherThanReadingItAsEmpty() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("opaque.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o000])
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundleWriter(preparingAt: url)
        })
        guard case .notWritable = thrown else {
            Issue.record("expected a not-writable refusal, got \(thrown)")
            return
        }
    }

    @Test
    func preparingIntoAnEmptyExistingDirectoryIsFine() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("fresh.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        #expect(throws: Never.self) {
            try CaptureBundleWriter(preparingAt: url)
        }
    }

    private static func manifest(screens: [CaptureManifest.ScreenRecord]) -> CaptureManifest {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = screens
        return manifest
    }
}
