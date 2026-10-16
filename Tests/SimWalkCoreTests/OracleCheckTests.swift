//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// Checking a bundle's figures against a value oracle: a real app's headline as one line, every other answer as its own, and a bundle without capture times refused.
struct OracleCheckTests {
    /// A real app's finding (Brief §2.3, measured on its walkbook, 2026-08-20): Steps 2,703 on screen, 3,326 midnight-anchored — the figure tracks the rolling window, and the line says so beside the value it was expected to have.
    @Test
    func theExampleFigureMatchesTheRollingWindowWithMidnightShown() throws {
        let directory = try TemporaryDirectory()
        let bundle = try FigureFixture.figureBundle(in: directory)
        let oracle = RecordingOracle(.reply(values: ["midnight": 3326, "rolling24h": 2703], unit: "count", attribution: nil))

        let checks = try OracleCheck.checks(of: bundle, against: FigureFixture.figureWalkbook(), oracle: oracle)

        #expect(checks.map(\.rendered) == ["today/light-loc_en_us steps-today: 2,703 matches rolling24h (exact) — midnight 3326, rolling24h 2703 count"])
        #expect(oracle.requests.map(\.figure) == ["steps-today"])
        #expect(oracle.requests.first?.locale == "en_US")
    }

    @Test
    func aFigureNoWindowExplainsListsEveryWindowBesideIt() throws {
        let directory = try TemporaryDirectory()
        let bundle = try FigureFixture.figureBundle(in: directory)
        let oracle = RecordingOracle(.reply(values: ["midnight": 3326, "rolling24h": 2750], unit: nil, attribution: "seeded corpus"))

        let checks = try OracleCheck.checks(of: bundle, against: FigureFixture.figureWalkbook(), oracle: oracle)

        #expect(checks.map(\.rendered) == ["today/light-loc_en_us steps-today: 2,703 matches none — midnight 3326, rolling24h 2750 — seeded corpus"])
    }

    /// Not on screen is answered without asking the oracle anything.
    @Test
    func aFigureNotOnScreenIsItsOwnAnswer() throws {
        let directory = try TemporaryDirectory()
        let bundle = try FigureFixture.figureBundle(in: directory)
        let oracle = RecordingOracle(.reply(values: ["midnight": 0, "rolling24h": 0], unit: nil, attribution: nil))

        let checks = try OracleCheck.checks(of: bundle, against: FigureFixture.figureWalkbook(element: "steps-week"), oracle: oracle)

        #expect(checks.map(\.outcome) == [.notOnScreen(element: "steps-week")])
        #expect(oracle.requests.isEmpty)
    }

    @Test
    func anOracleFailureIsNeitherAMatchNorAMismatch() throws {
        let directory = try TemporaryDirectory()
        let bundle = try FigureFixture.figureBundle(in: directory)

        let failed = try OracleCheck.checks(of: bundle, against: FigureFixture.figureWalkbook(), oracle: RecordingOracle(.failed(reason: "it exited 3: store not seeded")))
        let partial = try OracleCheck.checks(of: bundle, against: FigureFixture.figureWalkbook(), oracle: RecordingOracle(.reply(values: ["midnight": 3326], unit: nil, attribution: nil)))

        #expect(failed.map(\.rendered) == ["today/light-loc_en_us steps-today: oracle failed — it exited 3: store not seeded"])
        #expect(partial.map(\.outcome) == [.oracleFailed(reason: "its reply has no value for window 'rolling24h'")])
    }

    /// A figure printed to one place matches within half of it, and says so.
    @Test
    func aDecimalFigureMatchesWithinItsPrintedPrecision() throws {
        let directory = try TemporaryDirectory()
        let bundle = try FigureFixture.figureBundle(in: directory, text: "4,2 km", locale: "de_DE")
        var walkbook = FigureFixture.figureWalkbook()
        walkbook.screens[0].states = [Walkbook.CaptureState(theme: .light, locale: "de_DE")]

        let checks = try OracleCheck.checks(of: bundle, against: walkbook, oracle: RecordingOracle(.reply(values: ["midnight": 4.23, "rolling24h": 3.9], unit: "km", attribution: nil)))

        #expect(checks.map(\.rendered) == ["today/light-loc_de_de steps-today: 4,2 km matches midnight (±0.05) — midnight 4.23, rolling24h 3.9 km"])
    }

    /// A figure in a state the walk refused has a line of its own and qualifies: the light state matching says nothing about the dark one nobody checked.
    @Test
    func aFigureInAStateThatWasNotCapturedHasItsOwnLineAndQualifies() throws {
        let directory = try TemporaryDirectory()
        let light = Walkbook.CaptureState(theme: .light, locale: "en_US")
        let dark = Walkbook.CaptureState(theme: .dark, locale: "en_US")
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(
                id: "today",
                outcome: .stateNotApplied(reason: "dark rendered as light"),
                captures: [CaptureBundleFixture.Capture(screenID: "today", state: light, tree: FigureFixture.screen(text: "2,703"))],
                refusedStates: [dark]
            ),
        ])
        var walkbook = FigureFixture.figureWalkbook()
        walkbook.screens[0].states = [light, dark]
        let checks = try OracleCheck.checks(of: bundle, against: walkbook, oracle: RecordingOracle(.reply(values: ["midnight": 3326, "rolling24h": 2703], unit: nil, attribution: nil)))

        let answer = try OracleSummary(checks, of: bundle, against: walkbook).answer()

        #expect(answer.residue.contains("today/dark-loc_en_us steps-today: state not captured (refused, state not applied)"))
        #expect(answer.verdict.isQualified)
        #expect(answer.verdict.line.contains("1 figure in a state that was not captured"))
        #expect(answer.verdict.line.contains("1 of 2 figure checks matched"))
    }

    /// A capture carries the moment it was read, and the writer keeps it: the screen's states are filed together after the last is read, so the moment they were filed is not when any of them was on screen.
    @Test
    func theWriterKeepsTheReadTimeEachCaptureCarries() throws {
        let directory = try TemporaryDirectory()
        let filed = Date(timeIntervalSince1970: 1_790_000_020.456)
        let read = Date(timeIntervalSince1970: 1_789_999_980.123_456)
        let writer = try CaptureBundleWriter(preparingAt: directory.url.appendingPathComponent("stamp.simwalk"), clock: { filed })
        let record = try Self.filing(CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light), capturedAt: read), with: writer)

        let written = try writer.finalise(Self.manifest(captures: [record]))
        let reread = try CaptureBundle.read(at: written.url)

        #expect(reread.manifest.screens.first?.captures.first?.capturedAt == Date(timeIntervalSince1970: 1_789_999_980.123))
        #expect(reread.manifest == written.manifest)
    }

    /// A capture that arrives without its read time is stamped with the moment its directory was prepared — the fallback, so a bundle still records a time the oracle can refuse or use.
    @Test
    func theWriterStampsTheMomentItFiledACaptureOnlyWhenItCarriesNoTime() throws {
        let directory = try TemporaryDirectory()
        let filed = Date(timeIntervalSince1970: 1_790_000_000.123_456)
        let writer = try CaptureBundleWriter(preparingAt: directory.url.appendingPathComponent("stamp.simwalk"), clock: { filed })
        let record = try Self.filing(CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light)), with: writer)

        let written = try writer.finalise(Self.manifest(captures: [record]))
        let reread = try CaptureBundle.read(at: written.url)

        #expect(reread.manifest.screens.first?.captures.first?.capturedAt == Date(timeIntervalSince1970: 1_790_000_000.123))
        #expect(reread.manifest == written.manifest)
    }

    /// A bundle written before `capturedAt` existed still reads, and the oracle refuses it rather than guessing a moment.
    @Test
    func aManifestWithoutCaptureTimesDecodesAndIsRefusedByTheOracle() throws {
        let directory = try TemporaryDirectory()
        let bundle = try FigureFixture.figureBundle(in: directory)
        let manifestURL = CaptureBundle.manifestURL(in: bundle.url)
        let text = try String(contentsOf: manifestURL, encoding: .utf8)
        let old = text.replacingOccurrences(of: #""capturedAt" *: *"[^"]*",?"#, with: "", options: .regularExpression)
        try Data(old.utf8).write(to: manifestURL)

        let reread = try CaptureBundle.read(at: bundle.url)

        #expect(text != old)
        #expect(reread.manifest.screens.first?.captures.first?.capturedAt == nil)
        #expect(throws: OracleCheckError.noCaptureTime(screenID: "today", stateSlug: "light-loc_en_us")) {
            try OracleCheck.checks(of: reread, against: FigureFixture.figureWalkbook(), oracle: RecordingOracle(.failed(reason: "unasked")))
        }
    }

    /// Prepares `record`'s directory with `writer` and files both its artefacts, returning it.
    private static func filing(_ record: CaptureManifest.StateCapture, with writer: CaptureBundleWriter) throws -> CaptureManifest.StateCapture {
        try writer.prepareDirectory(screenID: "today", state: record.state)
        try CaptureBundleFixture.screenshot(width: 10, height: 10).write(to: CaptureBundleLayout.url(forRelativePath: record.screenshotPath, in: writer.url))
        try JSONEncoder().encode(FigureFixture.screen(text: "1")).write(to: CaptureBundleLayout.url(forRelativePath: record.axTreePath, in: writer.url))
        return record
    }

    private static func manifest(captures: [CaptureManifest.StateCapture]) -> CaptureManifest {
        CaptureManifest(
            walkName: "stamp",
            appBundleID: "com.example.app",
            appBuildHash: "a1b2c3d4",
            walkbookHash: String(repeating: "0f", count: 32),
            device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "9E7F0C2A-0000-4000-8000-000000000001", osVersion: "26.0"),
            startedAt: Date(timeIntervalSince1970: 1_789_999_990),
            finishedAt: Date(timeIntervalSince1970: 1_790_000_010),
            screens: [CaptureManifest.ScreenRecord(id: "today", outcome: .captured, routeTaken: [.tab(label: "Today")], captures: captures)]
        )
    }
}

private extension OracleCheckTests {
    /// An oracle answering every request alike, keeping what it was asked.
    final class RecordingOracle: ValueOracle {
        private let answer: OracleAnswer
        private(set) var requests: [OracleRequest] = []

        init(_ answer: OracleAnswer) {
            self.answer = answer
        }

        func answers(to requests: [OracleRequest]) -> [OracleAnswer] {
            self.requests += requests
            return requests.map { _ in answer }
        }
    }
}
