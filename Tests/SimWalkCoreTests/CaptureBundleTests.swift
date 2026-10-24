//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// The capture bundle is the contract on both sides of the runner boundary (Brief §5), so it must round-trip exactly — and refuse, rather than default, when what it is handed is not one.
struct CaptureBundleTests {
    @Test
    func aBundleRoundTripsThroughDisk() throws {
        let directory = try TemporaryDirectory()
        let written = try Self.writtenBundle(in: directory)
        let url = written.url

        let read = try CaptureBundle.read(at: url)

        // What `finalise` wrote is what reads back — which is the manifest handed to it with each capture's
        // time stamped by the writer, the one field the runner does not state.
        #expect(read.manifest == written.manifest)
        #expect(read.manifest.screens.flatMap(\.captures).allSatisfy { $0.capturedAt != nil })
        #expect(read.manifest.screens.map(\.id) == Self.manifest().screens.map(\.id))
        #expect(read.url == url)
    }

    /// A qualification only qualifies anything if it survives being written down: the two flags a capture carries are what the summary calls out and what moves the walk's exit code, and both are read back out of the manifest rather than remembered.
    @Test
    func acapturesTwoQualificationsSurviveTheTripThroughABundle() throws {
        let directory = try TemporaryDirectory()
        let written = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(
                screenID: "browse",
                state: Walkbook.CaptureState(theme: .light),
                tree: CaptureBundleFixture.loadingScreen(),
                settled: true,
                hasContent: false
            ),
        ])

        let read = try CaptureBundle.read(at: written.url)

        #expect(read.manifest.chromeOnlyCaptures.map(\.screenID) == ["browse"])
        #expect(read.manifest.unsettledCaptures.isEmpty)
        #expect(read.manifest.screens.first?.captures.first?.axTreeHasContent == false)
    }

    /// A bundle written before the check existed says nothing about it, rather than being read as a screen that held nothing.
    @Test
    func abundleWrittenWithoutTheContentFlagClaimsNothingAboutIt() throws {
        let directory = try TemporaryDirectory()
        let url = try Self.writtenBundle(in: directory).url

        let read = try CaptureBundle.read(at: url)

        #expect(read.manifest.screens.first?.captures.first?.axTreeHasContent == nil)
        #expect(read.manifest.chromeOnlyCaptures.isEmpty)
    }

    @Test
    func aRoundTripPreservesSubSecondTimestamps() throws {
        let directory = try TemporaryDirectory()
        let url = try Self.writtenBundle(in: directory).url

        let read = try CaptureBundle.read(at: url)

        #expect(read.manifest.startedAt == Self.manifest().startedAt)
        #expect(read.manifest.startedAt.timeIntervalSince1970 != Self.manifest().startedAt.timeIntervalSince1970.rounded(.down))
    }

    @Test
    func aRoundTripIsExactForATimestampThatIsNotAlreadyMillisecondPrecise() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest = CaptureManifest(
            walkName: manifest.walkName,
            appBundleID: manifest.appBundleID,
            appBuildHash: manifest.appBuildHash,
            walkbookHash: manifest.walkbookHash,
            device: manifest.device,
            startedAt: Date(timeIntervalSince1970: 1_786_867_200.123_456_7),
            finishedAt: Date(timeIntervalSince1970: 1_786_867_440.987_654_3),
            screens: manifest.screens
        )
        let url = try Self.writtenBundle(in: directory, manifest: manifest).url

        let read = try CaptureBundle.read(at: url)

        #expect(read.manifest.startedAt == manifest.startedAt)
        #expect(read.manifest.finishedAt == manifest.finishedAt)
    }

    @Test
    func aWholeSecondTimestampIsStillReadableRatherThanRefusedAsTorn() throws {
        let directory = try TemporaryDirectory()
        let url = try Self.writtenBundle(in: directory).url
        let manifestURL = CaptureBundle.manifestURL(in: url)
        let text = try String(contentsOf: manifestURL, encoding: .utf8)
            .replacingOccurrences(of: "T08:00:00.125Z", with: "T08:00:00Z")
        try Data(text.utf8).write(to: manifestURL)

        let read = try CaptureBundle.read(at: url)

        #expect(read.manifest.startedAt == Date(timeIntervalSince1970: 1_786_867_200))
    }

    @Test
    func writingLaysOutADirectoryForEveryCapturedStateAndNoneForARefusal() throws {
        let directory = try TemporaryDirectory()
        let url = try Self.writtenBundle(in: directory).url

        let fileManager = FileManager.default

        #expect(fileManager.fileExists(atPath: url.appendingPathComponent("screens/today/light").path))
        #expect(fileManager.fileExists(atPath: url.appendingPathComponent("screens/today/dark").path))
        #expect(!fileManager.fileExists(atPath: url.appendingPathComponent("screens/power_detail").path))
        #expect(!fileManager.fileExists(atPath: url.appendingPathComponent("screens/sleep_detail").path))
    }

    @Test
    func aCaptureDerivesBothArtefactPathsFromTheLayoutRatherThanRestatingThem() {
        let state = Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "accessibility3")
        let capture = CaptureManifest.StateCapture(screenID: "today", state: state)

        #expect(capture.screenshotPath == "screens/today/dark-dt_accessibility3/screen.png")
        #expect(capture.axTreePath == "screens/today/dark-dt_accessibility3/ax-tree.json")
    }

    @Test
    func aBundleResolvesACapturesArtefactsAgainstItsOwnDirectory() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.writtenBundle(in: directory)
        let capture = try #require(bundle.manifest.screens.first?.captures.first)

        #expect(bundle.screenshotURL(for: capture) == bundle.url.appendingPathComponent("screens/today/light/screen.png"))
        #expect(bundle.axTreeURL(for: capture) == bundle.url.appendingPathComponent("screens/today/light/ax-tree.json"))
    }

    @Test
    func readingADirectoryThatIsNotABundleRefusesRatherThanInventingAManifest() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("empty.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })
        guard case let .manifestMissing(bundlePath, expectedPath) = thrown else {
            Issue.record("expected a missing-manifest refusal, got \(thrown)")
            return
        }

        #expect(bundlePath == url.path)
        #expect(expectedPath.hasSuffix(CaptureBundleLayout.manifestFileName))
    }

    @Test
    func readingAMissingPathRefusesAsNotABundle() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("absent.\(CaptureBundleLayout.directoryExtension)")

        #expect(throws: CaptureBundleError.notABundle(path: url.path)) {
            try CaptureBundle.read(at: url)
        }
    }

    @Test
    func readingATornManifestRefusesAsTornRatherThanAsEmpty() throws {
        let directory = try TemporaryDirectory()
        let url = try Self.writtenBundle(in: directory).url
        let manifestURL = CaptureBundle.manifestURL(in: url)
        let whole = try Data(contentsOf: manifestURL)
        try whole.prefix(whole.count / 2).write(to: manifestURL)

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })
        guard case let .manifestMalformed(path, _) = thrown else {
            Issue.record("expected a torn-manifest refusal, got \(thrown)")
            return
        }

        #expect(path == manifestURL.path)
    }

    @Test
    func readingAManifestOfAnUnknownFormatVersionRefusesNamingBothVersions() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest.formatVersion = CaptureManifest.currentFormatVersion + 1
        let url = try Self.writtenBundle(in: directory, manifest: manifest).url

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })

        #expect(thrown.description.contains("\(manifest.formatVersion)"))
        #expect(thrown.description.contains("\(CaptureManifest.currentFormatVersion)"))
    }

    /// The version guard used to run *after* the full decode, which made it unreachable for every change that would need it.
    ///
    /// A later format that renames or adds a required key fails this build's decode first and was reported as a torn manifest. Every incompatible change is by definition one this shape cannot decode, so the version has to be answerable without decoding the rest.
    @Test
    func aLaterFormatThisBuildCannotDecodeRefusesByVersionRatherThanAsTorn() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("future.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let unknown = CaptureManifest.currentFormatVersion + 1
        let json = #"{ "formatVersion": \#(unknown), "walk": { "name": "example-validation" } }"#
        try Data(json.utf8).write(to: CaptureBundle.manifestURL(in: url))

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })
        guard case let .unsupportedFormatVersion(_, found, supported) = thrown else {
            Issue.record("expected an unsupported-version refusal, got \(thrown)")
            return
        }

        #expect(found == unknown)
        #expect(supported == CaptureManifest.readableFormatVersions)
    }

    /// Format 6 is a route step an older build has no case for: `tapPoint` (SimWalk#29 review, item 4).
    ///
    /// A manifest whose `routeTaken` names one declares the current format — 6 or later — by default (`currentFormatVersion`), and a reader of the formats before it refuses by version rather than failing to decode the step and reporting a good manifest as torn.
    @Test
    func aReaderOfTheFormatsBeforeTapPointRefusesABundleHoldingOneByName() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captured,
                routeTaken: [.tapPoint(label: "Steps chart", point: [0.8, 0.5])],
                captures: [CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light))]
            ),
        ]
        let data = try Data(contentsOf: CaptureBundle.manifestURL(in: Self.writtenBundle(in: directory, manifest: manifest).url))
        let formatFiveReader = [5, 4, 3, 2, 1]

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.requireReadableFormat(of: data, at: "manifest.json", readable: formatFiveReader)
        })
        guard case let .unsupportedFormatVersion(_, found, supported) = thrown else {
            Issue.record("expected a refusal by format version, got \(thrown)")
            return
        }

        #expect(found == CaptureManifest.currentFormatVersion)
        #expect(supported == formatFiveReader)
    }

    /// Format 7 is another such step: `systemTap` (SimWalk#28 review, item 7), which a format-6 reader refuses by version rather than as a torn manifest.
    @Test
    func aReaderOfTheFormatsBeforeSystemTapRefusesABundleHoldingOneByName() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captured,
                routeTaken: [.systemTap(label: "Allow", owner: .springboard)],
                captures: [CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light))]
            ),
        ]
        let data = try Data(contentsOf: CaptureBundle.manifestURL(in: Self.writtenBundle(in: directory, manifest: manifest).url))
        let formatSixReader = [6, 5, 4, 3, 2, 1]

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.requireReadableFormat(of: data, at: "manifest.json", readable: formatSixReader)
        })
        guard case let .unsupportedFormatVersion(_, found, supported) = thrown else {
            Issue.record("expected a refusal by format version, got \(thrown)")
            return
        }

        #expect(found == CaptureManifest.currentFormatVersion)
        #expect(supported == formatSixReader)
    }

    /// Format 11 is the `drag` route step (SimWalk#148), after format 10's state `orientation` (SimWalk#199) and format 9's route steps `longPress`, `swipe` and `type`'s `replace` (SimWalk#198): this build reads 11 and every format before it, and refuses 12 by name.
    @Test
    func formatElevenIsTheCurrentFormatAndTwelveIsNotReadable() {
        #expect(CaptureManifest.currentFormatVersion == 11)
        #expect(CaptureManifest.readableFormatVersions == [11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1])
        #expect(!CaptureManifest.readableFormatVersions.contains(12))
    }

    /// Format 8 is a state's own launch arguments and environment (SimWalk#44): a format-7 reader decodes a state strictly and would meet `arguments` as an unknown key, so it refuses by version instead — and this build reads the state back exactly as it was written.
    @Test
    func aReaderOfTheFormatsBeforeLaunchArgumentsRefusesABundleHoldingThemByName() throws {
        let directory = try TemporaryDirectory()
        let seeding = Walkbook.CaptureState(theme: .light, arguments: ["--seed-sample-data"], environment: ["SEED": "1"])
        var manifest = Self.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captured,
                routeTaken: [.systemTap(label: "Allow", owner: .springboard)],
                captures: [CaptureManifest.StateCapture(screenID: "today", state: seeding)]
            ),
        ]
        let bundle = try Self.writtenBundle(in: directory, manifest: manifest)
        let data = try Data(contentsOf: CaptureBundle.manifestURL(in: bundle.url))
        let formatSevenReader = [7, 6, 5, 4, 3, 2, 1]

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.requireReadableFormat(of: data, at: "manifest.json", readable: formatSevenReader)
        })
        guard case let .unsupportedFormatVersion(_, found, supported) = thrown else {
            Issue.record("expected a refusal by format version, got \(thrown)")
            return
        }

        #expect(found == CaptureManifest.currentFormatVersion)
        #expect(supported == formatSevenReader)
        #expect(try CaptureBundle.read(at: bundle.url).manifest.screens[0].captures[0].state == seeding)
    }

    /// Format 10 is a state's `orientation` (SimWalk#199): a format-9 reader decodes a state strictly and would meet `orientation` as an unknown key, so it refuses by version instead — and this build reads the state back exactly as it was written.
    @Test
    func aReaderOfTheFormatsBeforeOrientationRefusesABundleHoldingOneByName() throws {
        let directory = try TemporaryDirectory()
        let landscape = Walkbook.CaptureState(theme: .light, orientation: .landscape)
        var manifest = Self.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captured,
                routeTaken: [],
                captures: [CaptureManifest.StateCapture(screenID: "today", state: landscape)]
            ),
        ]
        let bundle = try Self.writtenBundle(in: directory, manifest: manifest)
        let data = try Data(contentsOf: CaptureBundle.manifestURL(in: bundle.url))
        let formatNineReader = [9, 8, 7, 6, 5, 4, 3, 2, 1]

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.requireReadableFormat(of: data, at: "manifest.json", readable: formatNineReader)
        })
        guard case let .unsupportedFormatVersion(_, found, supported) = thrown else {
            Issue.record("expected a refusal by format version, got \(thrown)")
            return
        }

        #expect(found == CaptureManifest.currentFormatVersion)
        #expect(supported == formatNineReader)
        #expect(try CaptureBundle.read(at: bundle.url).manifest.screens[0].captures[0].state == landscape)
    }

    @Test
    func aManifestWithNoVersionAtAllIsStillRefusedAsTorn() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("torn.\(CaptureBundleLayout.directoryExtension)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(#"{ "walkName": "example-validation" }"#.utf8).write(to: CaptureBundle.manifestURL(in: url))

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })
        guard case .manifestMalformed = thrown else {
            Issue.record("expected a torn-manifest refusal, got \(thrown)")
            return
        }
    }

    /// The extension is the bundle's only marker — "recognisable without opening it" — and nothing applied or checked it, so a runner was free to write `example/` and a reader to adopt any directory that happened to hold a manifest.
    @Test
    func aDirectoryNotNamedAsABundleIsRefusedAsMisnamedRatherThanForItsContents() throws {
        let directory = try TemporaryDirectory()
        let url = try Self.writtenBundle(in: directory).url
        let renamed = directory.url.appendingPathComponent("example")
        try FileManager.default.moveItem(at: url, to: renamed)

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: renamed)
        })

        #expect(thrown == .misnamedBundle(path: renamed.path, expectedExtension: CaptureBundleLayout.directoryExtension))
    }

    /// SimWalk#107: the writer's half of the suffix rule — completed only where nothing exists, so the refusal still guards a directory somebody else made.
    @Test
    func anOutputIsNamedByAddingTheSuffixOnlyWhereNothingExists() throws {
        let directory = try TemporaryDirectory()
        let named = directory.url.appendingPathComponent("a.simwalk")
        let absent = directory.url.appendingPathComponent("band8.bundle")
        let existing = directory.url.appendingPathComponent("taken")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        #expect(CaptureBundleLayout.resolvingOutput(named) == CaptureBundleLayout.Resolution(url: named, suffixAdded: false))
        #expect(CaptureBundleLayout.resolvingOutput(absent) == CaptureBundleLayout.Resolution(url: absent.appendingPathExtension("simwalk"), suffixAdded: true))
        #expect(CaptureBundleLayout.resolvingOutput(existing) == CaptureBundleLayout.Resolution(url: existing, suffixAdded: false))
        #expect(throws: CaptureBundleError.self) {
            try CaptureBundleWriter.requireFresh(existing)
        }
    }

    /// SimWalk#107: the reader's half — the suffixed sibling is opened only when the asked path is absent, and the header says so; any other misnamed path is refused as before.
    @Test
    func aReaderOpensTheSuffixedSiblingOfAnAbsentUnnamedPathAndSaysSo() throws {
        let directory = try TemporaryDirectory()
        let written = try Self.writtenBundle(in: directory)
        let unnamed = written.url.deletingPathExtension()

        let read = try CaptureBundle.read(at: unnamed)

        #expect(read.url == written.url)
        #expect(read.pathNote == "(read example.simwalk: suffix added)")
        #expect(CaptureBundleHeader.line(of: read).hasSuffix("  (read example.simwalk: suffix added)"))
        #expect(CaptureBundleHeader.line(of: written) == CaptureBundleHeader.line(written.manifest))

        let present = directory.url.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        let elsewhere = directory.url.appendingPathComponent("unrelated")
        #expect(CaptureBundleLayout.resolvingForRead(present) == CaptureBundleLayout.Resolution(url: present, suffixAdded: false))
        #expect(CaptureBundleLayout.resolvingForRead(elsewhere) == CaptureBundleLayout.Resolution(url: elsewhere, suffixAdded: false))
    }

    @Test
    func aWriterRefusesToProduceADirectoryNothingCouldRecogniseAsABundle() throws {
        let directory = try TemporaryDirectory()

        #expect(throws: CaptureBundleError.self) {
            try CaptureBundleWriter(preparingAt: directory.url.appendingPathComponent("example"))
        }
    }

    @Test
    func aRefusedScreenSurvivesTheRoundTripCarryingItsEvidence() throws {
        let directory = try TemporaryDirectory()
        let url = try Self.writtenBundle(in: directory).url

        let read = try CaptureBundle.read(at: url)
        let unreachable = try #require(read.manifest.screens.first { $0.id == "power-detail" })
        let mismatch = try #require(read.manifest.screens.first { $0.id == "sleep-detail" })

        #expect(unreachable.outcome == .unreachable(routeTried: [.tab(label: "Workouts"), .tap(label: "Power")]))
        #expect(mismatch.outcome == .buildMismatch(expected: "a1b2c3d4", found: "58ebbd24"))
        #expect(unreachable.captures.isEmpty)
        #expect(mismatch.captures.isEmpty)
    }

    /// SimWalk#15 end to end on disk: a screen that refused one state and kept another is written, accepted by `finalise`, and read back naming both — and a manifest with no refusal in it does not grow the field.
    @Test
    func aScreenThatRefusedOneStateSurvivesTheRoundTripHoldingTheOther() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest.screens[0] = CaptureManifest.ScreenRecord(
            id: "today",
            outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
            routeTaken: [.tab(label: "Today")],
            captures: [CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light))],
            refusedStates: [Walkbook.CaptureState(theme: .dark)]
        )

        let read = try CaptureBundle.read(at: Self.writtenBundle(in: directory, manifest: manifest).url)

        #expect(read.manifest.screens[0].captures.map(\.state) == [Walkbook.CaptureState(theme: .light)])
        #expect(read.manifest.screens[0].refusedStates == [Walkbook.CaptureState(theme: .dark)])
        #expect(try !#require(String(bytes: JSONEncoder().encode(Self.manifest()), encoding: .utf8)).contains("refusedStates"))
    }

    /// SimWalk#18 and #16 on disk: a capture identical to its base says so, the device's locale says why, and the runner commit that wrote the bundle rides with it.
    ///
    /// A bundle with none of them does not grow the fields.
    @Test
    func acaptureIdenticalToItsBaseSurvivesTheRoundTripSayingSo() throws {
        let directory = try TemporaryDirectory()
        let british = Walkbook.CaptureState(theme: .light, locale: "en_GB")
        var manifest = Self.manifest()
        manifest.device.locale = "en_GB"
        manifest.runnerCommit = "c80e027000000000000000000000000000000000"
        manifest.screens[0] = CaptureManifest.ScreenRecord(
            id: "today",
            outcome: .captured,
            routeTaken: [.tab(label: "Today")],
            captures: [
                CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light)),
                CaptureManifest.StateCapture(screenID: "today", state: british, identicalTo: "light"),
            ]
        )

        let read = try CaptureBundle.read(at: Self.writtenBundle(in: directory, manifest: manifest).url)

        #expect(read.manifest.screens[0].captures.map(\.identicalTo) == [nil, "light"])
        #expect(read.manifest.device.locale == "en_GB")
        // And which runner wrote it (SimWalk#16).
        #expect(read.manifest.runnerCommit == "c80e027000000000000000000000000000000000")
        let plain = try #require(String(bytes: JSONEncoder().encode(Self.manifest()), encoding: .utf8))
        #expect(!plain.contains("identicalTo"))
        #expect(!plain.contains("locale"))
        #expect(!plain.contains("runnerCommit"))
        let summary = CaptureBundleSummary(read).answer().text
        #expect(summary.contains("runner: c80e0270"))
        #expect(summary.contains("captured [light, light-loc_en_gb (= light)]"))
    }

    /// A capture recorded identical to its base is held to it on disk: two screenshots that differ refuse the bundle rather than letting the claim stand (SimWalk#18).
    @Test
    func acaptureIdenticalToABaseItDiffersFromIsRefused() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest.screens[0] = CaptureManifest.ScreenRecord(
            id: "today",
            outcome: .captured,
            routeTaken: [.tab(label: "Today")],
            captures: [
                CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light)),
                CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light, locale: "en_GB"), identicalTo: "light"),
            ]
        )
        let url = try Self.writtenBundle(in: directory, manifest: manifest).url
        try Data("another picture".utf8).write(to: url.appendingPathComponent("screens/today/light-loc_en_gb/screen.png"))

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try CaptureBundle.read(at: url)
        })

        #expect(thrown.description.contains("says it is identical to 'light', and the two screenshots on disk differ"))
    }

    /// SimWalk#17 on disk: an UNREACHABLE carries what its last step's label matched, and the summary prints it — so a label taken by a navigation bar does not read like a missing route.
    @Test
    func anUnreachableScreenCarriesWhatItsLabelMatched() throws {
        let directory = try TemporaryDirectory()
        let reason = "tapped a NavigationBar identified 'Sleep', and the screen did not change"
        var manifest = Self.manifest()
        manifest.screens[1] = CaptureManifest.ScreenRecord(
            id: "power-detail",
            outcome: .unreachable(routeTried: [.tab(label: "Browse"), .tap(label: "Sleep")], reason: reason),
            routeTaken: [.tab(label: "Browse")]
        )

        let read = try CaptureBundle.read(at: Self.writtenBundle(in: directory, manifest: manifest).url)

        #expect(read.manifest.screens[1].outcome == .unreachable(routeTried: [.tab(label: "Browse"), .tap(label: "Sleep")], reason: reason))
        #expect(CaptureBundleSummary(read).answer().text.contains("UNREACHABLE, route tried: tab 'Browse' → tap 'Sleep'; completed: tab 'Browse' — \(reason)"))
    }

    /// A bundle written before the walk carried a nonce (SimWalk#41) has no `nonce` key at all; it still reads, with nothing claimed, so `bundle inspect` and its siblings keep serving what is already on disk.
    @Test
    func aManifestWrittenBeforeTheNonceStillReadsWithNoneRecorded() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest.nonce = "walk-1"
        let url = try Self.writtenBundle(in: directory, manifest: manifest).url
        let manifestURL = CaptureBundle.manifestURL(in: url)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        #expect(object.removeValue(forKey: "nonce") as? String == "walk-1")
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)

        let read = try CaptureBundle.read(at: url)

        #expect(read.manifest.nonce == nil)
        #expect(read.manifest.walkName == manifest.walkName)
    }

    /// Format 1 wrote the flag as `settled`; dropping that key would turn a recorded warning into "never recorded" on every bundle already on disk.
    @Test
    func aFormatOneCapturesSettlingIsStillReadUnderItsOldSpelling() throws {
        let directory = try TemporaryDirectory()
        var manifest = Self.manifest()
        manifest.screens[0] = CaptureManifest.ScreenRecord(
            id: "today",
            outcome: .captured,
            routeTaken: [.tab(label: "Today")],
            captures: [CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light), axTreeSettled: false)]
        )
        let url = try Self.writtenBundle(in: directory, manifest: manifest).url
        let manifestURL = CaptureBundle.manifestURL(in: url)
        let text = try String(contentsOf: manifestURL, encoding: .utf8)
            .replacingOccurrences(of: "\"axTreeSettled\"", with: "\"settled\"")
        try Data(text.utf8).write(to: manifestURL)

        let read = try CaptureBundle.read(at: url)

        #expect(read.manifest.screens[0].captures[0].axTreeSettled == false)
        #expect(read.manifest.unsettledCaptures == [CaptureManifest.CaptureReference(screenID: "today", stateSlug: "light")])
    }

    /// A capture whose bundle never recorded settling makes no claim either way, so it is not counted among the ones that were still moving.
    @Test
    func aCaptureThatNeverRecordedSettlingIsNotCountedAsUnsettled() {
        #expect(Self.manifest().unsettledCaptures.isEmpty)
    }

    @Test
    func aScreenIDCannotClimbOutOfTheBundle() {
        let capture = CaptureManifest.StateCapture(screenID: "../../../../tmp/simwalk-pwned", state: Walkbook.CaptureState(theme: .light))

        #expect(capture.screenshotPath == "screens/____________tmp_simwalk_pwned/light/screen.png")
        #expect(!capture.screenshotPath.contains(".."))
    }

    @Test
    func aScreenIDDifferingOnlyByCaseIsTheSameDirectory() {
        #expect(CaptureBundleLayout.screenDirectory(screenID: "Today") == CaptureBundleLayout.screenDirectory(screenID: "today"))
    }

    /// Writes a bundle the way the executor will: directories first, artefacts, manifest last.
    static func writtenBundle(in directory: TemporaryDirectory, manifest: CaptureManifest? = nil) throws -> CaptureBundle {
        let manifest = manifest ?? Self.manifest()
        let url = directory.url.appendingPathComponent("example.\(CaptureBundleLayout.directoryExtension)")
        let writer = try CaptureBundleWriter(preparingAt: url)
        for screen in manifest.screens {
            for capture in screen.captures {
                try writer.prepareDirectory(screenID: screen.id, state: capture.state)
                try Self.placeArtefacts(for: capture, in: url)
            }
        }
        return try writer.finalise(manifest)
    }

    static func placeArtefacts(for capture: CaptureManifest.StateCapture, in bundleURL: URL) throws {
        for path in [capture.screenshotPath, capture.axTreePath] + [capture.appleAudit?.path].compactMap(\.self) {
            try Data("stub".utf8).write(to: CaptureBundleLayout.url(forRelativePath: path, in: bundleURL))
        }
    }

    static func manifest() -> CaptureManifest {
        CaptureManifest(
            walkName: "example-validation",
            appBundleID: "dev.simwalk.route-fixture",
            appBuildHash: "a1b2c3d4",
            walkbookHash: "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0",
            device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "9E7F0C2A-0000-4000-8000-000000000001", osVersion: "26.0"),
            startedAt: Date(timeIntervalSince1970: 1_786_867_200.125),
            finishedAt: Date(timeIntervalSince1970: 1_786_867_440.5),
            screens: [
                CaptureManifest.ScreenRecord(
                    id: "today",
                    outcome: .captured,
                    routeTaken: [.tab(label: "Today")],
                    captures: [
                        CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light)),
                        CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .dark)),
                    ]
                ),
                CaptureManifest.ScreenRecord(
                    id: "power-detail",
                    outcome: .unreachable(routeTried: [.tab(label: "Workouts"), .tap(label: "Power")]),
                    routeTaken: [.tab(label: "Workouts")]
                ),
                CaptureManifest.ScreenRecord(
                    id: "sleep-detail",
                    outcome: .buildMismatch(expected: "a1b2c3d4", found: "58ebbd24"),
                    routeTaken: []
                ),
            ]
        )
    }
}
