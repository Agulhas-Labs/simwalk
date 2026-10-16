//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// What `walk --dry-run` writes and reads back (SimWalk#1 item 4): a report the reader accepts is exactly one the writer would write, and one that does not describe a dry run of the walkbook the runner was handed is refused on both sides, naming every way it does not.
struct RouteProbeReportTests {
    @Test
    func areportWrittenIsReadBackUnchanged() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.walkbook()
        let report = try RouteProbeFixture.report(of: book, outcomes: [.resolved, .drifted(step: 1, reason: "'Power' matched nothing")])

        try report.write(to: url, of: book)
        let read = try Self.read(url, of: book)

        #expect(read == report)
    }

    /// A cause a future binary named that this one does not decodes as `nil` rather than failing the probe's decode (SimWalk#58 item 3).
    @Test
    func adriftedProbesUnknownCauseDecodesAsNil() throws {
        let json = #"{"drifted":{"step":1,"reason":"'Heart' matched nothing","cause":"somethingFuture"}}"#

        let decoded = try JSONDecoder().decode(RouteProbe.Outcome.self, from: Data(json.utf8))

        #expect(decoded == .drifted(step: 1, reason: "'Heart' matched nothing", cause: nil))
    }

    /// A probe outcome naming two cases is corrupt and refused, as synthesized decoding refused it, never settled by whichever key comes first (SimWalk#61 item 3).
    @Test
    func aprobeOutcomeNamingTwoCasesIsRefused() {
        let json = #"{"resolved":{},"unreadable":{"step":1,"reason":"the read failed"}}"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RouteProbe.Outcome.self, from: Data(json.utf8))
        }
    }

    /// A cause this binary knows survives the round trip, so a reloaded report still counts a snapshot-blind drift apart (the #58 review).
    @Test
    func adriftedProbesKnownCauseRoundTrips() throws {
        let outcome = RouteProbe.Outcome.drifted(step: 1, reason: "not in the snapshot", cause: .snapshotBlind)
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(RouteProbe.Outcome.self, from: data)

        #expect(decoded == outcome)
    }

    @Test
    func areportOfAnotherWalkbookIsRefusedByItsHash() throws {
        let book = try Self.walkbook()
        let report = try Self.report(of: book) { RouteProbeReport(walkName: $0.walkName, appBundleID: $0.appBundleID, appBuildHash: $0.appBuildHash, walkbookHash: "deadbeef0000", runnerCommit: nil, device: $0.device, startedAt: $0.startedAt, nonce: $0.nonce, probes: $0.probes) }

        let problems = try report.problems(against: book)

        #expect(problems.count == 1)
        #expect(problems.first?.contains("it is of walkbook deadbeef") == true)
    }

    @Test
    func areportOfAnotherAppIsRefused() throws {
        let book = try Self.walkbook()
        let report = try Self.report(of: book) { RouteProbeReport(walkName: $0.walkName, appBundleID: "com.example.other", appBuildHash: $0.appBuildHash, walkbookHash: $0.walkbookHash, runnerCommit: nil, device: $0.device, startedAt: $0.startedAt, nonce: $0.nonce, probes: $0.probes) }

        let problems = try report.problems(against: book)

        #expect(problems == ["it followed routes in com.example.other, where the walkbook names com.example.probe"])
    }

    @Test
    func areportWhoseScreensAreOutOfOrderIsRefused() throws {
        let book = try Self.walkbook()
        let report = try Self.report(of: book) { RouteProbeReport(walkName: $0.walkName, appBundleID: $0.appBundleID, appBuildHash: $0.appBuildHash, walkbookHash: $0.walkbookHash, runnerCommit: nil, device: $0.device, startedAt: $0.startedAt, nonce: $0.nonce, probes: $0.probes.reversed()) }

        let problems = try report.problems(against: book)

        #expect(problems == ["it probes [power, today], where the walkbook lists [today, power]"])
    }

    @Test
    func areportCarryingARouteOtherThanTheWalkbooksIsRefused() throws {
        let book = try Self.walkbook()
        let report = try Self.report(of: book) { report in
            let probes = [report.probes[0], RouteProbe(screenID: "power", route: [.tab(label: "Workouts")], outcome: .resolved)]
            return RouteProbeReport(walkName: report.walkName, appBundleID: report.appBundleID, appBuildHash: report.appBuildHash, walkbookHash: report.walkbookHash, runnerCommit: nil, device: report.device, startedAt: report.startedAt, nonce: report.nonce, probes: probes)
        }

        let problems = try report.problems(against: book)

        #expect(problems == ["'power' carries the route tab 'Workouts', where the walkbook states tab 'Workouts' → tap 'Power' → tap 'Heart'"])
    }

    @Test
    func areportStoppingAtAStepTheRouteDoesNotHaveIsRefused() throws {
        let book = try Self.walkbook()
        let report = try RouteProbeFixture.report(of: book, outcomes: [.resolved, .unreadable(step: 3, reason: "timed out")])

        let problems = try report.problems(against: book)

        #expect(problems == ["'power' stops at step 4 of a 3-step route"])
    }

    /// A dry run through a system sheet records the tree its `systemTap` found the control in, as a walk's `routeTaken` does — and the report still reads back against a walkbook that never writes one.
    @Test
    func areportThroughASystemSheetIsReadBackWithTheOwnerItRecorded() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.sheetWalkbook()
        let followed: [Walkbook.RouteStep] = [.tap(label: "Connect"), .systemTap(label: "Allow", owner: .springboard), .tap(label: "Heart")]
        let report = try Self.report(of: book) { RouteProbeReport(walkName: $0.walkName, appBundleID: $0.appBundleID, appBuildHash: $0.appBuildHash, walkbookHash: $0.walkbookHash, runnerCommit: nil, device: $0.device, startedAt: $0.startedAt, nonce: $0.nonce, probes: [RouteProbe(screenID: "heart", route: followed, outcome: .resolved)]) }

        try report.write(to: url, of: book)
        let read = try Self.read(url, of: book)

        #expect(read == report)
        #expect(read.probes.first?.resolvedSteps == followed)
    }

    /// A landed `systemTap` declared `atLaunch` keeps the declaration beside the owner the runner recorded, and reads back against the walkbook that declared it (SimWalk#46).
    @Test
    func areportThroughASheetDeclaredAtLaunchReadsBackAgainstItsWalkbook() throws {
        let json = #"{"name":"sheet","appBundleID":"com.example.probe","screens":[{"id":"heart","route":[{"systemTap":{"label":"Allow","atLaunch":true}},{"tap":{"label":"Heart"}}],"states":[{"theme":"light"}]}]}"#
        let book = try WalkbookLoader.load(from: Data(json.utf8), source: "sheet.json")
        let followed: [Walkbook.RouteStep] = [.systemTap(label: "Allow", atLaunch: true, owner: .appWindow), .tap(label: "Heart")]
        let report = try Self.report(of: book) { RouteProbeReport(walkName: $0.walkName, appBundleID: $0.appBundleID, appBuildHash: $0.appBuildHash, walkbookHash: $0.walkbookHash, runnerCommit: nil, device: $0.device, startedAt: $0.startedAt, nonce: $0.nonce, probes: [RouteProbe(screenID: "heart", route: followed, outcome: .resolved)]) }

        #expect(try report.problems(against: book).isEmpty)
    }

    /// An owner is what the runner saw doing a step, so one on the step a probe stopped at claims a tree nobody read.
    @Test
    func areportRecordingAnOwnerOnAStepThatNeverLandedIsRefused() throws {
        let book = try Self.sheetWalkbook()
        let followed: [Walkbook.RouteStep] = [.tap(label: "Connect"), .systemTap(label: "Allow", owner: .appWindow), .tap(label: "Heart")]
        let report = try Self.report(of: book) { RouteProbeReport(walkName: $0.walkName, appBundleID: $0.appBundleID, appBuildHash: $0.appBuildHash, walkbookHash: $0.walkbookHash, runnerCommit: nil, device: $0.device, startedAt: $0.startedAt, nonce: $0.nonce, probes: [RouteProbe(screenID: "heart", route: followed, outcome: .drifted(step: 1, reason: nil))]) }

        let problems = try report.problems(against: book)

        #expect(problems == ["'heart' records where step 2 found its control, but that step never landed"])
    }

    /// The writer refuses what the reader would, so an invalid report never reaches the disk.
    @Test
    func aninvalidReportIsNeitherWrittenNorRead() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.walkbook()
        let report = try RouteProbeFixture.report(of: book, outcomes: [.drifted(step: 5, reason: nil)])

        #expect(throws: RouteProbeError.invalid(path: url.path, problems: ["'today' stops at step 6 of a 1-step route"])) {
            try report.write(to: url, of: book)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))

        try CaptureBundle.encoder().encode(report).write(to: url)

        #expect(throws: RouteProbeError.invalid(path: url.path, problems: ["'today' stops at step 6 of a 1-step route"])) {
            try Self.read(url, of: book)
        }
    }

    @Test
    func noReportAtThePathIsMissingNotMalformed() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")

        let thrown = try #require(#expect(throws: RouteProbeError.self) {
            try Self.read(url, of: Self.walkbook())
        })

        guard case .missing = thrown else {
            Issue.record("expected a missing report, got \(thrown)")
            return
        }
    }

    @Test
    func areportInAFormatThisBuildDoesNotReadIsRefused() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.walkbook()
        let report = try Self.report(of: book) { RouteProbeReport(formatVersion: 99, walkName: $0.walkName, appBundleID: $0.appBundleID, appBuildHash: $0.appBuildHash, walkbookHash: $0.walkbookHash, runnerCommit: nil, device: $0.device, startedAt: $0.startedAt, nonce: $0.nonce, probes: $0.probes) }
        try JSONEncoder().encode(report).write(to: url)

        #expect(throws: RouteProbeError.unsupportedFormatVersion(path: url.path, found: 99, supported: RouteProbeReport.currentFormatVersion)) {
            try Self.read(url, of: book)
        }
    }

    /// Two dry runs to one path pass `requireFresh` together; the one whose runner could not write reads the other's report — refused when it names another build (SimWalk#36).
    @Test
    func areportOfAnotherBuildIsAnotherRunsNotThisOnes() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.walkbook()
        try RouteProbeFixture.report(of: book, buildHash: "0therbu1ld00").write(to: url, of: book)

        #expect(throws: RouteProbeError.fromAnotherRun(path: url.path, problems: ["it was followed against build 0therbu1, not 58ebbd24, the one this run installed"])) {
            try Self.read(url, of: book)
        }
    }

    /// The same race on one build: a report whose runner started before this run launched its own is another run's, with the second's slack a walk's manifest is given (SimWalk#36).
    @Test
    func areportThatStartedBeforeThisRunLaunchedItsRunnerIsAnotherRuns() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.walkbook()
        let report = try RouteProbeFixture.report(of: book)
        try report.write(to: url, of: book)
        let launched = report.startedAt.addingTimeInterval(60)

        #expect(throws: RouteProbeError.fromAnotherRun(path: url.path, problems: ["it started at 2026-08-16T08:00:00.125Z, before this run launched its runner at 2026-08-16T08:01:00.125Z"])) {
            try RouteProbeReport.read(at: url, of: book, buildHash: RouteProbeFixture.buildHash, runnerLaunchedAt: launched, nonce: RouteProbeFixture.nonce)
        }
        #expect(try RouteProbeReport.read(at: url, of: book, buildHash: RouteProbeFixture.buildHash, runnerLaunchedAt: report.startedAt.addingTimeInterval(0.9), nonce: RouteProbeFixture.nonce) == report)
        #expect(RouteProbeError.fromAnotherRun(path: url.path, problems: []).usageFailureKind == .inputRefused)
    }

    /// The overlap the build hash and start-time checks alone miss — a second run launched before the first's runner starts probing, whose report is of the same build and started after the second's own launch — caught instead by the nonce this run generated and the runner echoed (SimWalk#36).
    @Test
    func areportOfTheSameBuildStartedAfterLaunchButCarryingAnotherNonceIsAnotherRuns() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.walkbook()
        let report = try RouteProbeFixture.report(of: book, nonce: "another-runs-nonce")
        try report.write(to: url, of: book)

        #expect(throws: RouteProbeError.fromAnotherRun(path: url.path, problems: ["it carries another run's nonce — an overlapping run of this build wrote it"])) {
            try RouteProbeReport.read(at: url, of: book, buildHash: RouteProbeFixture.buildHash, runnerLaunchedAt: report.startedAt.addingTimeInterval(-60), nonce: RouteProbeFixture.nonce)
        }
    }

    /// A report of the format before `startedAt` lacks it, and is named by its format rather than called torn.
    @Test
    func areportOfTheFormatBeforeTheStartTimeIsRefusedByItsVersion() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("probe.json")
        let book = try Self.walkbook()
        let data = try CaptureBundle.encoder().encode(RouteProbeFixture.report(of: book))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = 1
        object["startedAt"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        #expect(throws: RouteProbeError.unsupportedFormatVersion(path: url.path, found: 1, supported: RouteProbeReport.currentFormatVersion)) {
            try Self.read(url, of: book)
        }
    }

    /// A dry run's output is a fresh `.json` file: a bundle's name is refused, and so is anything already there.
    @Test
    func anoutputPathThatIsNotAFreshJSONFileIsRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = directory.url.appendingPathComponent("example.simwalk")
        let existing = directory.url.appendingPathComponent("probe.json")
        try Data("{}".utf8).write(to: existing)

        #expect(throws: RouteProbeError.misnamed(path: bundle.path, expectedExtension: "json")) {
            try RouteProbeReport.requireFresh(bundle)
        }
        #expect(throws: RouteProbeError.alreadyExists(path: existing.path)) {
            try RouteProbeReport.requireFresh(existing)
        }
        #expect(RouteProbeError.alreadyExists(path: existing.path).usageFailureKind == .inputRefused)
    }

    /// Two screens: one a single tab away, one three steps deep.
    static func walkbook() throws -> Walkbook {
        let json = #"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"today","route":[{"tab":{"label":"Today"}}],"states":[{"theme":"light"}]},{"id":"power","route":[{"tab":{"label":"Workouts"}},{"tap":{"label":"Power"}},{"tap":{"label":"Heart"}}],"states":[{"theme":"light"}]}]}"#
        return try WalkbookLoader.load(from: Data(json.utf8), source: "probe.json")
    }

    /// One screen behind a system sheet: a tap raises it, a `systemTap` answers it.
    static func sheetWalkbook() throws -> Walkbook {
        let json = #"{"name":"sheet","appBundleID":"com.example.probe","screens":[{"id":"heart","route":[{"tap":{"label":"Connect"}},{"systemTap":{"label":"Allow"}},{"tap":{"label":"Heart"}}],"states":[{"theme":"light"}]}]}"#
        return try WalkbookLoader.load(from: Data(json.utf8), source: "sheet.json")
    }

    /// The report at `url`, read as the run that made the fixture's would read it.
    private static func read(_ url: URL, of book: Walkbook) throws -> RouteProbeReport {
        try RouteProbeReport.read(at: url, of: book, buildHash: RouteProbeFixture.buildHash, runnerLaunchedAt: RouteProbeFixture.startedAt, nonce: RouteProbeFixture.nonce)
    }

    /// A report of `book` with every route resolved, rebuilt by `change`.
    private static func report(of book: Walkbook, _ change: (RouteProbeReport) -> RouteProbeReport) throws -> RouteProbeReport {
        try change(RouteProbeFixture.report(of: book))
    }
}
