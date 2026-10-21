//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimulatorServices
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `walk --dry-run` (SimWalk#1 item 4): a drifted route is a shortfall — exit 2 — a run with no report is a refusal, and a dry run tells the runner so and never leaves a bundle behind.
struct WalkDryRunTests {
    @Test
    func adryRunWhoseRoutesAllResolvedExitsZeroAndIsLoggedAsADryRun() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let log = Self.log(in: directory)
        let report = try RouteProbeFixture.report(of: Self.book())

        try Self.command().runDryRun(log: log, emit: recorder.emit, emitError: recorder.emitError) {
            WalkDryRun.Outcome(report: report)
        }

        let entry = try #require(UsageReport.entries(at: log.fileURL).entries.first)

        #expect(recorder.out.count == 1)
        #expect(recorder.err.isEmpty)
        #expect(entry.tool == "walk --dry-run")
        #expect(entry.tool == WalkCommand.dryRunLogName)
    }

    @Test(arguments: [RouteProbe.Outcome.drifted(step: 0, reason: "'Progress' matched nothing"), .unreadable(step: 0, reason: "timed out")])
    func adryRunWithARouteThatDidNotResolveExitsWithTheQualifiedCode(outcome: RouteProbe.Outcome) throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let report = try RouteProbeFixture.report(of: Self.book(), outcomes: [outcome])

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command().runDryRun(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) {
                WalkDryRun.Outcome(report: report)
            }
        })

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.out.count == 1)
        #expect(recorder.out.first?.contains("step 1 of 1, tab 'Progress'") == true)
        #expect(recorder.err.isEmpty)
    }

    @Test
    func adryRunThatLeftNoReportRefuses() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let log = Self.log(in: directory)

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command().runDryRun(log: log, emit: recorder.emit, emitError: recorder.emitError) {
                try WalkDryRun.outcome(runnerFailure: nil, handback: nil) {
                    throw RouteProbeError.missing(path: "/nowhere/probe.json", reason: "no such file")
                }
            }
        })

        let entry = try #require(UsageReport.entries(at: log.fileURL).entries.first)

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.count == 1)
        #expect(entry.tool == "walk --dry-run")
        #expect(entry.kind == .runnerFailed)
    }

    /// No readable report is a refusal carrying the handback, and the runner's own failure is the answer when there was one.
    @Test
    func noReadableReportIsARefusalNamingTheRunnersFailure() throws {
        let handback = DeviceHandback(accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored), appearance: .restored(.light))
        let failure = RunnerError.walkFailed(reason: "the app would not launch")

        let thrown = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkDryRun.outcome(runnerFailure: failure, handback: handback) {
                throw RouteProbeError.missing(path: "/nowhere/probe.json", reason: "no such file")
            }
        })

        #expect((thrown.underlying as? RunnerError) == failure)
        #expect(thrown.handback == handback)
    }

    /// SimWalk#50: a dry run's refusal carries the result bundle's digest too, just as a walk's does — `diagnosingRunnerFailure:` is threaded through `WalkDryRun.outcome` the same way.
    @Test
    func adryRunFailureRefusalCarriesTheResultBundleDigest() throws {
        let handback = DeviceHandback(accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored), appearance: .restored(.light))
        let failure = RunnerError.walkFailed(reason: "the app would not launch")
        let digest = RunnerActivityDigest(
            recentActivities: ["Tap \"Progress\" Button"],
            failure: "Failed to get matching snapshot: No matches found",
            earlierFailures: 0,
            triageAttachments: []
        )
        let diagnosis = RunnerFailureDiagnosis.digested(
            resultBundlePath: "/builds/Logs/Test/simwalk-dry-run.xcresult",
            digest: digest,
            hierarchy: .nothingAttached
        )

        let thrown = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkDryRun.outcome(runnerFailure: failure, handback: handback, diagnosingRunnerFailure: { diagnosis }, readingReport: {
                throw RouteProbeError.missing(path: "/nowhere/probe.json", reason: "no such file")
            })
        })

        #expect(thrown.description.contains("result bundle: /builds/Logs/Test/simwalk-dry-run.xcresult"))
        #expect(thrown.description.contains("Tap \"Progress\" Button"))
        #expect(thrown.description.contains("failure: Failed to get matching snapshot: No matches found"))
    }

    /// SimWalk#50, wired through `WalkDryRun.perform` itself (not `outcome` directly): a failing runner's refusal names the result bundle `perform` never got to write, proving `diagnosingRunnerFailure:` is actually threaded from `perform` into `outcome`.
    @Test
    func adryRunPerformNamesTheResultBundleOnARunnerFailure() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkCommandTests.WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("probe.json").path, "--device", "UDID-1", "--dry-run"])

        let thrown = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkDryRun.perform(command, shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { "dry-run-nonce" }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        })

        #expect(thrown.description.contains("the runner's result bundle could not be read — the runner wrote no result bundle:"))
        #expect(thrown.description.contains(".xcresult"))
    }

    /// A dry run reaches the same `prepare` as a walk, and `WalkDryRun.perform` hands it `note`: an empty build directory is told as a cold build (SimWalk#98, #118).
    @Test
    func adryRunOverAnEmptyBuildDirectoryTellsTheCallerItIsAColdBuild() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkCommandTests.WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("probe.json").path, "--device", "UDID-1", "--dry-run"])
        var notes: [String] = []

        _ = try? WalkDryRun.perform(command, shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { "dry-run-nonce" }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), note: { notes.append($0) })

        #expect(notes == ["building the runner (c0ffee00) — a first build takes several minutes"])
    }

    /// The whole sequence against a script: the runner is told it is a dry run and handed a `.json` path, the report it writes is read back, the device is handed back after it — and no bundle exists anywhere.
    @Test
    func adryRunTellsTheRunnerAndNeverCreatesABundle() throws {
        let directory = try TemporaryDirectory()
        let staged = directory.url.appendingPathComponent("staged-report.json")
        let output = directory.url.appendingPathComponent("probe.json")
        let appPath = try Self.fakeApp(in: directory)
        let report = try RouteProbeFixture.report(of: Self.book(), outcomes: [.drifted(step: 0, reason: nil)], buildHash: AppBuildIdentity.hash(ofAppAt: appPath))
        try report.write(to: staged, of: Self.book())
        let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output))
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", output.path, "--device", "UDID-1", "--dry-run"])

        let outcome = try WalkDryRun.perform(command, shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let runnerIndex = try #require(script.calls.firstIndex { $0.arguments.contains("test-without-building") })
        let restoreIndex = try #require(script.calls.firstIndex { $0.arguments.contains("write") })
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.url.path)

        #expect(script.calls[runnerIndex].environment["TEST_RUNNER_SIMWALK_DRY_RUN"] == "1")
        #expect(script.calls[runnerIndex].environment["TEST_RUNNER_SIMWALK_NONCE"] == RouteProbeFixture.nonce)
        #expect(script.outputs == [output.path])
        #expect(runnerIndex < restoreIndex)
        #expect(outcome.report == report)
        #expect(outcome.handback?.accessibility.state == .restored)
        #expect(!contents.contains { $0.hasSuffix(".\(CaptureBundleLayout.directoryExtension)") })
    }

    /// `prepare` provisions a created device for a dry run as for a walk, so the answer carries the device note a walk's does (SimWalk#155).
    @Test
    func adryRunOnACreatedDeviceSaysWhatItDidToTheDevice() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let overrideRoot = directory.url.appendingPathComponent("override-root", isDirectory: true)
        let udid = "11111111-2222-3333-4444-0000000000A1"
        let lease = try leases.acquire(udid: udid, ttl: 60, holderPID: 41, now: Date(timeIntervalSince1970: 0), createdDevice: true, clonedFrom: "SOURCE-1")
        let staged = directory.url.appendingPathComponent("staged-report.json")
        let output = directory.url.appendingPathComponent("probe.json")
        let appPath = try Self.fakeApp(in: directory)
        try RouteProbeFixture.report(of: Self.book(), buildHash: AppBuildIdentity.hash(ofAppAt: appPath)).write(to: staged, of: Self.book())
        let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output), booted: false, udid: udid)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", output.path, "--lease", lease.token, "--app-path", appPath, "--stock", "--dry-run"])

        let outcome = try WalkDryRun.perform(
            command, shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases,
            provisioning: { SlimWalkProvisioning(shell: $0, overrides: DisabledServicesOverride(root: overrideRoot)) }
        )

        #expect(outcome.deviceNote == "device: stock: --stock")
        #expect(outcome.answer().text.contains("device: stock: --stock"))
    }

    /// The report on disk after the runner names another build, or started before this run launched its runner: another dry run's, which a second run to the same path reads when its own runner could not write (SimWalk#36).
    @Test(arguments: [false, true])
    func areportLeftByAnotherRunIsARefusal(sameBuild: Bool) throws {
        let directory = try TemporaryDirectory()
        let appPath = try Self.fakeApp(in: directory)
        let report = try RouteProbeFixture.report(
            of: Self.book(),
            buildHash: sameBuild ? AppBuildIdentity.hash(ofAppAt: appPath) : RouteProbeFixture.buildHash,
            startedAt: sameBuild ? Date(timeIntervalSince1970: -60) : RouteProbeFixture.startedAt
        )

        let thrown = try #require(#expect(throws: WalkCommand.Refusal.self) {
            _ = try Self.performDryRun(Self.walkbook(in: directory), leaving: report, of: Self.book(), appPath: appPath, in: directory)
        })

        guard case let .fromAnotherRun(_, problems)? = thrown.underlying as? RouteProbeError else {
            Issue.record("expected another run's report, got \(thrown.underlying)")
            return
        }

        #expect(problems.count == 1)
        #expect(problems.first?.contains(sameBuild ? "before this run launched its runner" : "the one this run installed") == true)
    }

    /// A screen walked under two locales was probed under the first only, and the dry run of it says so with exit 2 (SimWalk#36).
    @Test
    func adryRunOfAScreenWalkedInTwoLocalesIsQualified() throws {
        let directory = try TemporaryDirectory()
        let appPath = try Self.fakeApp(in: directory)
        let url = directory.url.appendingPathComponent("locales.json")
        try Data(#"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"settings","route":[{"tap":{"label":"Settings"}}],"states":[{"theme":"light","locale":"en"},{"theme":"light","locale":"de"}]}]}"#.utf8).write(to: url)
        let book = try WalkbookLoader.load(contentsOf: url)
        let report = try RouteProbeFixture.report(of: book, buildHash: AppBuildIdentity.hash(ofAppAt: appPath))

        let (outcome, _) = try Self.performDryRun(url.path, leaving: report, of: book, appPath: appPath, in: directory)

        #expect(outcome.launchConditionGaps == [RouteProbeSummary.LaunchConditionGap(screenID: "settings", axis: .locale, probed: "en", unprobed: ["de"])])
        #expect(outcome.answer().verdict.exitCode == AnswerVerdict.qualifiedExitCode)
    }

    /// `--screens` with `--dry-run`: the runner is handed the subset, and the report is held to the subset — a report of the whole walkbook is refused (SimWalk#36 item 3).
    @Test
    func adryRunOfASubsetIsHeldToTheSubset() throws {
        let directory = try TemporaryDirectory()
        let appPath = try Self.fakeApp(in: directory)
        let path = try Self.twoScreenWalkbook(in: directory)
        let full = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: path))
        let subset = try WalkbookSubset.narrow(full, to: ["power"])
        let buildHash = try AppBuildIdentity.hash(ofAppAt: appPath)
        let report = try RouteProbeFixture.report(of: subset, buildHash: buildHash)

        let (outcome, script) = try Self.performDryRun(path, leaving: report, of: subset, appPath: appPath, in: directory, screens: ["power"])

        #expect(outcome.report == report)
        #expect(script.walkedScreens == [["power"]])

        let whole = try RouteProbeFixture.report(of: full, buildHash: buildHash)
        let thrown = try #require(#expect(throws: WalkCommand.Refusal.self) {
            _ = try Self.performDryRun(path, leaving: whole, of: full, appPath: appPath, in: TemporaryDirectory(), screens: ["power"])
        })
        guard case .invalid? = thrown.underlying as? RouteProbeError else {
            Issue.record("expected a report of another walkbook to be refused, got \(thrown.underlying)")
            return
        }
    }

    /// The temporary walkbook `--screens` writes is deleted by `prepare` itself when the runner build throws — the caller never gets a `Prepared` to delete it from (SimWalk#36 item 3).
    @Test
    func prepareDeletesTheTemporaryWalkbookWhenTheBuildFails() throws {
        let directory = try TemporaryDirectory()
        let scratch = directory.url.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let script = try WalkCommandTests.WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let failingBuild = Shell(script: { executable, arguments, environment in
            guard !arguments.contains("build-for-testing") else {
                return Shell.Result(status: 65, standardOutput: "", standardError: "** TEST BUILD FAILED **\n")
            }
            return try script.run(executable, arguments, environment)
        })
        let command = try WalkCommand.parse([Self.twoScreenWalkbook(in: directory), "--output", directory.url.appendingPathComponent("probe.json").path, "--device", "UDID-1", "--screens", "power", "--dry-run"])

        // The control: a build that succeeds leaves the subset in `scratch` for the caller to discard.
        let prepared = try command.prepare(shell: Shell(script: script.run), runner: { Self.runner }, builds: Self.builds(in: directory), leases: LeaseStore(directory: directory.url.appendingPathComponent("leases")), now: Date(), scratch: scratch)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).count == 1)
        // And the lease it took on the device, which is the caller's to release as the temporary walkbook is.
        WalkCommand.discardTemporary(prepared.temporaryWalkbook)
        prepared.lease.release()

        #expect(throws: RunnerError.self) {
            try command.prepare(shell: failingBuild, runner: { Self.runner }, builds: Self.builds(in: directory), leases: LeaseStore(directory: directory.url.appendingPathComponent("leases")), now: Date(), scratch: scratch)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
        #expect(LeaseStore(directory: directory.url.appendingPathComponent("leases")).all().isEmpty)
    }

    /// A walk never tells the runner it is a dry run — the setting is absent, not `0`.
    @Test
    func awalkDoesNotTellTheRunnerItIsADryRun() throws {
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)")
        let script = try WalkCommandTests.WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", output.path, "--device", "UDID-1"])

        _ = try? command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let runner = try #require(script.calls.first { $0.arguments.contains("test-without-building") })

        #expect(runner.environment["TEST_RUNNER_SIMWALK_DRY_RUN"] == nil)
    }

    /// A dry run's output must be a fresh `.json` file, refused before anything is touched — a bundle's name and a file already there alike.
    @Test(arguments: ["walked.simwalk", "existing.json"])
    func adryRunOutputThatIsNotAFreshReportIsRefusedBeforeTheSimulatorIsTouched(name: String) throws {
        let directory = try TemporaryDirectory()
        try Data("{}".utf8).write(to: directory.url.appendingPathComponent("existing.json"))
        let output = directory.url.appendingPathComponent(name)
        let script = try WalkCommandTests.WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", output.path, "--device", "UDID-1", "--dry-run"])

        #expect(throws: RouteProbeError.self) {
            try WalkDryRun.perform(command, shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        }

        #expect(script.calls.isEmpty)
    }

    /// A dry run makes the walkbook's setup as a walk does — a route relying on a grant rather than a `systemTap` would otherwise probe as drifted — and hands it back after the runner, here one that left no report.
    @Test
    func adryRunMakesTheSetupBeforeTheRunnerAndHandsItBackAfter() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("setup.json")
        try Data(#"{"name":"probe","appBundleID":"com.example.probe","setup":{"privacy":{"grant":["location"]}},"screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#.utf8).write(to: url)
        let script = try WalkCommandTests.WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65)
        let command = try WalkCommand.parse([url.path, "--output", directory.url.appendingPathComponent("probe.json").path, "--device", "UDID-1", "--dry-run"])

        let refusal = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkDryRun.perform(command, shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        })

        let calls = script.calls.map(\.arguments)
        let runner = try #require(calls.firstIndex { $0.contains("test-without-building") })

        #expect(try #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "grant", "location", "com.example.probe"])) < runner)
        #expect(try #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "reset", "location", "com.example.probe"])) > runner)
        #expect(refusal.description.contains("setup handed back: location reset"))
    }

    /// The SimWalk#63 review: a dry run's privacy reset, which nothing reads back, is printed under the report and does not qualify it — a walk's does — and the setup's record is on disk while the runner runs and gone once handed back.
    @Test
    func adryRunPrintsAnUnconfirmedResetWithoutQualifyingAndRecordsItsSetupWhileTheRunnerRuns() throws {
        let directory = try TemporaryDirectory()
        let json = #"{"name":"probe","appBundleID":"com.example.probe","setup":{"privacy":{"grant":["location"]}},"screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
        let url = directory.url.appendingPathComponent("setup.json")
        try Data(json.utf8).write(to: url)
        let book = try WalkbookLoader.load(from: Data(json.utf8), source: "setup.json")
        let appPath = try Self.fakeApp(in: directory)
        let (staged, output) = (directory.url.appendingPathComponent("staged-report.json"), directory.url.appendingPathComponent("probe.json"))
        try RouteProbeFixture.report(of: book, buildHash: AppBuildIdentity.hash(ofAppAt: appPath)).write(to: staged, of: book)
        let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output))
        let leases = Self.leases(in: directory)
        var duringRunner: DeviceSetupJournal.Entry?
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                duringRunner = DeviceSetupJournal.beside(leases).entry(onDevice: "UDID-1")
            }
            return try script.run(executable, arguments, environment)
        }
        let command = try WalkCommand.parse([url.path, "--output", output.path, "--device", "UDID-1", "--dry-run"])

        let outcome = try WalkDryRun.perform(command, shell: shell, pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(duringRunner?.applied.parts == ["privacy grant location"])
        #expect(DeviceSetupJournal.beside(leases).entry(onDevice: "UDID-1") == nil)
        #expect(outcome.setup?.handback.unconfirmed.count == 1)
        #expect(outcome.setup?.qualifications == ["a setup change handed back but not confirmed as found"])
        #expect(!outcome.answer().verdict.isQualified)
        #expect(outcome.answer().text.contains("⚠ setup handed back: location reset — not confirmed"))
    }

    /// SimWalk#75: a dry run that makes no setup hands a killed walk's record back only under a lease that still renews, as a walk does — a lapsed lease leaves the record where it is and says why.
    @Test
    func aDryRunWithoutASetupWhoseLeaseCannotBeRenewedLeavesAKilledWalksRecord() throws {
        let directory = try TemporaryDirectory()
        let json = #"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
        let url = directory.url.appendingPathComponent("book.json")
        try Data(json.utf8).write(to: url)
        let book = try WalkbookLoader.load(from: Data(json.utf8), source: "book.json")
        let appPath = try Self.fakeApp(in: directory)
        let (staged, output) = (directory.url.appendingPathComponent("staged-report.json"), directory.url.appendingPathComponent("probe.json"))
        try RouteProbeFixture.report(of: book, buildHash: AppBuildIdentity.hash(ofAppAt: appPath)).write(to: staged, of: book)
        let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output))
        let leases = Self.leases(in: directory)
        let journal = DeviceSetupJournal.beside(leases)
        let killed = #"{"udid":"UDID-1","bundleID":"killed.id","pid":2147483647,"token":"killed","applied":{"privacy":[{"action":"grant","service":"photos"}],"statusBar":false,"statusBarFound":[]}}"#
        try WalkCommandTests.plantSetupRecord(killed, in: journal)
        let shell = Shell { executable, arguments, environment in
            if arguments.starts(with: ["simctl", "ui"]) {
                WalkCommandTests.dropEveryLease(in: leases)
            }
            return try script.run(executable, arguments, environment)
        }
        let command = try WalkCommand.parse([url.path, "--output", output.path, "--device", "UDID-1", "--dry-run"])

        let outcome = try WalkDryRun.perform(command, shell: shell, pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "privacy"]) })
        #expect(try String(contentsOf: journal.directory.appendingPathComponent("UDID-1.json"), encoding: .utf8) == killed)
        #expect(outcome.setupNotMade?.hasPrefix("the lease on UDID-1 could not be renewed: ") == true)
        #expect(outcome.answer().text.contains("the setup an earlier walk left was not handed back"))
        #expect(outcome.answer().verdict.isQualified)
    }

    /// A dry run under a lease that can no longer be renewed when it comes to the setup makes none of it, and its refusal says why.
    @Test
    func adryRunWhoseLeaseCannotBeRenewedBeforeTheSetupMakesNoSetup() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let url = directory.url.appendingPathComponent("setup.json")
        try Data(#"{"name":"probe","appBundleID":"com.example.probe","setup":{"privacy":{"grant":["location"]}},"screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#.utf8).write(to: url)
        let script = try WalkCommandTests.WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65)
        let command = try WalkCommand.parse([url.path, "--output", directory.url.appendingPathComponent("probe.json").path, "--device", "UDID-1", "--dry-run"])
        let shell = Shell { executable, arguments, environment in
            if arguments.starts(with: ["simctl", "ui"]) {
                WalkCommandTests.dropEveryLease(in: leases)
            }
            return try script.run(executable, arguments, environment)
        }

        let refusal = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkDryRun.perform(command, shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        })

        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "privacy"]) })
        #expect(refusal.setup == nil)
        #expect(refusal.description.contains("the lease on UDID-1 could not be renewed: "))
    }

    /// A dry run holds the lease it took on its device while its runner runs, and releases it once the device is handed back.
    @Test
    func adryRunReleasesTheLeaseItTook() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let staged = directory.url.appendingPathComponent("staged-report.json")
        let output = directory.url.appendingPathComponent("probe.json")
        let appPath = try Self.fakeApp(in: directory)
        try RouteProbeFixture.report(of: Self.book(), outcomes: [.resolved], buildHash: AppBuildIdentity.hash(ofAppAt: appPath)).write(to: staged, of: Self.book())
        let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output))
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", output.path, "--device", "UDID-1", "--dry-run"])
        var heldDuringRunner: [String] = []
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                heldDuringRunner = leases.all().map(\.udid)
            }
            return try script.run(executable, arguments, environment)
        }

        _ = try WalkDryRun.perform(command, shell: shell, pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(heldDuringRunner == ["UDID-1"])
        #expect(leases.all().isEmpty)
    }

    /// SimWalk#128: a dry run under a `--lease` lease holds a claim while its runner runs, releases it after, and leaves the lease to its holder.
    @Test
    func adryRunUnderALeaseReleasesItsClaimAndLeavesTheLease() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let lease = try leases.acquire(udid: "UDID-1", ttl: 3600, holderPID: getpid(), now: Date(timeIntervalSince1970: 0))
        let staged = directory.url.appendingPathComponent("staged-report.json")
        let output = directory.url.appendingPathComponent("probe.json")
        let appPath = try Self.fakeApp(in: directory)
        try RouteProbeFixture.report(of: Self.book(), outcomes: [.resolved], buildHash: AppBuildIdentity.hash(ofAppAt: appPath)).write(to: staged, of: Self.book())
        let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output))
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", output.path, "--lease", lease.token, "--dry-run"])
        var walkedDuringRunner: Set<String> = []
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                walkedDuringRunner = WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive)
            }
            return try script.run(executable, arguments, environment)
        }

        _ = try WalkDryRun.perform(command, shell: shell, pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(walkedDuringRunner == ["UDID-1"])
        #expect(WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).isEmpty)
        #expect(try leases.lease(onDevice: "UDID-1") == lease)
    }

    /// A dry run of the walkbook at `path`, narrowed to `screens`, against a script whose runner leaves `report` — a report of `book` — at the output.
    private static func performDryRun(
        _ path: String,
        leaving report: RouteProbeReport,
        of book: Walkbook,
        appPath: String,
        in directory: TemporaryDirectory,
        screens: [String] = []
    ) throws -> (outcome: WalkDryRun.Outcome, script: WalkCommandTests.WalkScript) {
        let staged = directory.url.appendingPathComponent("staged-report.json")
        let output = directory.url.appendingPathComponent("probe.json")
        try report.write(to: staged, of: book)
        let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output))
        let narrowing = screens.isEmpty ? [] : ["--screens", screens.joined(separator: ",")]
        let command = try WalkCommand.parse([path, "--output", output.path, "--device", "UDID-1", "--dry-run"] + narrowing)
        let outcome = try WalkDryRun.perform(command, shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        return (outcome, script)
    }

    /// Two screens, for `--screens` to narrow to one.
    private static func twoScreenWalkbook(in directory: TemporaryDirectory) throws -> String {
        let url = directory.url.appendingPathComponent("two.json")
        try Data(#"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]},{"id":"power","route":[{"tab":{"label":"Workouts"}},{"tap":{"label":"Power"}}],"states":[{"theme":"light"}]}]}"#.utf8).write(to: url)
        return url.path
    }

    /// The one-screen walkbook `walkbook(in:)` writes.
    private static func book() throws -> Walkbook {
        try WalkbookLoader.load(from: Data(walkbookJSON.utf8), source: "book.json")
    }

    private static func walkbook(in directory: TemporaryDirectory) throws -> String {
        let url = directory.url.appendingPathComponent("book.json")
        try Data(walkbookJSON.utf8).write(to: url)
        return url.path
    }

    private static var walkbookJSON: String {
        #"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
    }

    /// An installed app as far as `AppBuildIdentity` is concerned: an `Info.plist` naming an executable that is there.
    private static func fakeApp(in directory: TemporaryDirectory) throws -> String {
        let url = directory.url.appendingPathComponent("Probe.app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Probe"], format: .xml, options: 0)
        try plist.write(to: url.appendingPathComponent("Info.plist"))
        try Data("binary".utf8).write(to: url.appendingPathComponent("Probe"))
        return url.path
    }

    /// The leases these runs see — the test's own scratch store, with every holder alive, never the machine's own `~/.simwalk/leases`.
    private static func leases(in directory: TemporaryDirectory) -> LeaseStore {
        LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
    }

    private static func builds(in directory: TemporaryDirectory) -> RunnerBuilds {
        RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
    }

    private static var runner: RunnerSource {
        RunnerSource(
            projectPath: "/Users/x/.simwalk/runner/snapshots/c0ffee/Runner/SimWalkRunner.xcodeproj",
            commit: "c0ffee0000000000000000000000000000000000",
            origin: .installed
        )
    }

    private static func command() throws -> WalkCommand {
        try WalkCommand.parse(["book.json", "--output", "probe.json", "--dry-run"])
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }
}
