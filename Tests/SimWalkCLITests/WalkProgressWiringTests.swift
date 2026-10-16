//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// The host's half of the progress file (`Docs/SIMWALK-PROGRESS.md` §2, §3): the phases a walk and a dry run write from `booting` to `done` or `failed`, the timings of each segment, and the result a walk ends with — each seen against a scripted walk, through the file a reader polls.
struct WalkProgressWiringTests {
    /// What the runner writes while the host waits on it survives the host's own write as that wait ends — the smoke walk showed the host's older copy of the file overwriting the runner's step and counts.
    @Test
    func theRunnersCountsSurviveTheHostsWriteWhenItsWalkReturns() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("progress.json")
        let telemetry = WalkTelemetry(writer: ProgressWriter(url: url, clock: { Date() }, pid: 1), resultURL: nil)
        telemetry.begin(tool: "walk")

        telemetry.measured(\.runMs) {
            let runner = ProgressWriter.adopting(url: url)
            runner.commit {
                $0.phase = .running
                $0.matches = WalkProgress.Matches(planned: 2)
                $0.matches?.passed = 1
            }
        }

        let file = try #require(try? WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: url)))

        #expect(file.matches?.passed == 1)
        #expect(file.phase == .running)
        #expect(file.summary?.runMs != nil)
    }

    /// The final counts are the final bundle's, not the first pass's: an appearance retry can fold a screen the runner counted as failed, and the file must not end saying so while the result says `passed`.
    @Test
    func theEndingCountsComeFromTheFinalBundleNotTheRunnersFirstPass() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("progress.json")
        let telemetry = WalkTelemetry(writer: ProgressWriter(url: url, clock: { Date() }, pid: 1), resultURL: nil)
        telemetry.begin(tool: "walk")
        telemetry.writer.commit { $0.matches = WalkProgress.Matches(planned: 1) }
        telemetry.writer.commit { $0.matches?.failed = 1 }
        telemetry.writer.commit { $0.matches?.pending = 0 }
        let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874))
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [CaptureBundleFixture.Capture(screenID: "s", state: Walkbook.CaptureState(theme: .light), tree: tree)])

        telemetry.finish(walk: bundle, logPath: nil)

        let file = try #require(try? WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: url)))

        #expect(file.matches?.passed == 1)
        #expect(file.matches?.failed == 0)
        #expect(file.phase == .done)
    }

    /// A full walk passes through every host phase in the spec's order, read off the file at each child the walk runs, and ends `done` naming its result.
    @Test
    func aWalkWritesEveryHostPhaseInOrderAndEndsDoneNamingItsResult() throws {
        let walk = try Walk()

        let outcome = try walk.perform(["--app-path", walk.appPath])

        #expect(walk.watch.phases == [.booting, .installing, .building, .launching, .matching])
        let final = try #require(walk.progress())
        #expect(final.phase == .done)
        #expect(final.error == nil)
        #expect(final.resultPath == walk.resultURL.path)
        #expect(outcome.resultPath == walk.resultURL.path)
        #expect(final.device == WalkProgress.Device(name: "iPhone 17 Pro", udid: "UDID-1", osVersion: "26.5"))
        #expect(final.app == "com.example.probe")
    }

    /// Each segment is timed on the host's clock alone: boot, install, the runner's build and its walk come out distinct, in the progress file's summary and in the result's timings both.
    @Test
    func eachSegmentIsTimedApartInTheSummaryAndTheResult() throws {
        let walk = try Walk()

        _ = try walk.perform(["--app-path", walk.appPath])

        let expected = PhaseTimings(bootMs: 1000, installMs: 2000, buildMs: 3000, runMs: 4000, totalMs: 10000)
        #expect(walk.progress()?.summary == expected)
        let result = try WalkResult.decoder().decode(WalkResult.self, from: Data(contentsOf: walk.resultURL))
        #expect(result.timings == expected)
        #expect(result.verdict == .passed)
        #expect(result.tool == "walk")
    }

    /// The usage log is named in the progress file while the walk runs, not only in the result at its end: a reader polling sees it at `launching`.
    @Test(arguments: [false, true])
    func theProgressFileNamesTheUsageLogOnceTheHostKnowsIt(dryRun: Bool) throws {
        let walk = try Walk()
        let logPath = UsageLog.standard().fileURL.path

        if dryRun {
            let book = try WalkbookLoader.load(from: Data(Walk.oneScreenJSON.utf8), source: "book.json")
            let report = try RouteProbeFixture.report(of: book, outcomes: [], buildHash: AppBuildIdentity.hash(ofAppAt: walk.appPath))
            _ = try walk.performDryRun(leaving: report, of: book)
        } else {
            _ = try walk.perform(["--app-path", walk.appPath])
        }

        #expect(walk.progress()?.logPath == logPath)
        #expect(walk.watch.first?.logPath == logPath)
        if !dryRun {
            let result = try WalkResult.decoder().decode(WalkResult.self, from: Data(contentsOf: walk.resultURL))
            #expect(result.logPath == logPath)
        }
    }

    /// A walk refused while preparing — the runner's build fails — still names the usage log in its `failed` file: the host knew it when the call started.
    @Test
    func aRefusalWhilePreparingStillNamesTheUsageLog() throws {
        let walk = try Walk(buildFails: true)

        #expect(throws: (any Error).self) { try walk.perform(["--app-path", walk.appPath]) }

        let final = try #require(walk.progress())
        #expect(final.phase == .failed)
        #expect(final.logPath == UsageLog.standard().fileURL.path)
    }

    /// A segment only the host writes reads nothing back: a runner left over from an earlier host, writing into the slot during a dry run, does not become this run's `tool` or `phase`.
    @Test
    func aSegmentTheRunnerDoesNotOwnLeavesTheFileAlone() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("progress.json")
        let telemetry = WalkTelemetry(writer: ProgressWriter(url: url, clock: { Date() }, pid: 1), resultURL: nil)
        telemetry.begin(tool: "walk --dry-run")

        WalkTelemetry.measure(telemetry, \.runMs, runnerOwnsFile: false) {
            ProgressWriter.adopting(url: url).commit {
                $0.tool = "walk"
                $0.phase = .matching
            }
        }

        let file = try #require(try? WalkProgress.decoder().decode(WalkProgress.self, from: Data(contentsOf: url)))

        #expect(file.tool == "walk --dry-run")
        #expect(file.phase != .matching)
    }

    /// A dry run times its probe as `runMs`, as a walk times its runner.
    @Test
    func aDryRunRecordsRunMs() throws {
        let walk = try Walk()
        let book = try WalkbookLoader.load(from: Data(Walk.oneScreenJSON.utf8), source: "book.json")
        let report = try RouteProbeFixture.report(of: book, outcomes: [], buildHash: AppBuildIdentity.hash(ofAppAt: walk.appPath))

        _ = try walk.performDryRun(leaving: report, of: book)

        #expect(walk.progress()?.summary?.runMs == 4000)
    }

    /// A walk refused partway through preparing — the app is not on the device — ends the file `failed`, carrying the refusal's own text.
    @Test
    func aRefusalWhilePreparingEndsFailedWithTheRefusalsText() throws {
        let walk = try Walk(appInstalled: false)

        #expect(throws: SimulatorError.self) { try walk.perform([]) }

        let final = try #require(walk.progress())
        #expect(final.phase == .failed)
        #expect(final.error == String(describing: SimulatorError.appNotInstalled(bundleID: "com.example.probe", udid: "UDID-1")))
        #expect(final.resultPath == nil)
        #expect(!FileManager.default.fileExists(atPath: walk.resultURL.path))
    }

    /// No telemetry is today's walk exactly: the same answer, the runner handed no progress file, and nothing written.
    @Test
    func aWalkWithNoTelemetryAnswersAsItAlwaysDid() throws {
        let walk = try Walk()

        let unwatched = try walk.perform([], watched: false)
        try FileManager.default.removeItem(at: walk.output)
        let watched = try walk.perform([])

        #expect(unwatched.answer() == watched.answer())
        #expect(unwatched.resultPath == nil)
        #expect(walk.runnerEnvironments.count == 2)
        #expect(walk.runnerEnvironments.first?["TEST_RUNNER_SIMWALK_PROGRESS"] == nil)
        #expect(walk.runnerEnvironments.last?["TEST_RUNNER_SIMWALK_PROGRESS"] == walk.progressURL.path)
    }

    /// A `--screens` subset is planned as it runs: the counts and the step total are the subset's, written before the runner is built.
    @Test
    func aSubsetIsPlannedAsTheScreensItRuns() throws {
        let walk = try Walk(twoScreens: true)

        _ = try walk.perform(["--screens", "progress"])

        let planned = try #require(walk.watch.atBuild)

        #expect(planned.matches == WalkProgress.Matches(planned: 1))
        #expect(planned.currentStep == WalkProgress.CurrentStep(index: 0, total: 1))
    }

    /// `--motion` reaches the runner, and a walk without it tells the runner nothing (SimWalk#67); beside `--dry-run`, which captures nothing to record it on, it is refused rather than ignored.
    @Test
    func motionReachesTheRunnerOnlyWhenAskedAndIsRefusedBesideADryRun() throws {
        let walk = try Walk()

        _ = try walk.perform(["--motion"])
        try FileManager.default.removeItem(at: walk.output)
        _ = try walk.perform([])

        #expect(walk.runnerEnvironments.first?[MotionOptIn.hostEnvironmentKey] == MotionOptIn.walkWideValue)
        #expect(walk.runnerEnvironments.last?[MotionOptIn.hostEnvironmentKey] == nil)
        #expect(throws: (any Error).self) { try WalkCommand.parse(["book.json", "--output", "probe.json", "--dry-run", "--motion"]) }
    }

    /// The runner is told where the progress file is only when there is one.
    @Test(arguments: [nil, "/scratch/progress/session.json"])
    func theRunnerIsHandedTheProgressPathOnlyWhenThereIsOne(path: String?) throws {
        var environments: [[String: String]] = []
        let shell = Shell(script: { executable, _, environment in
            if executable.hasSuffix("xcodebuild") {
                environments.append(environment)
            }
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: "/runner/dd", shell: shell)
        let simulator = Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true)

        try runner.walk(walkbookPath: "/book.json", outputPath: "/out.simwalk", buildHash: "a1b2", logFilePath: nil, progressPath: path, on: simulator)

        let environment = try #require(environments.first)

        #expect(environment["TEST_RUNNER_SIMWALK_PROGRESS"] == path)
    }

    /// A dry run writes the same phases through preparing, `running` while it probes, and ends `done` — or `failed` for a route that drifted — with no result file.
    @Test(arguments: [false, true])
    func aDryRunEndsByItsDriftWithNoResultFile(drifted: Bool) throws {
        let walk = try Walk()
        let book = try WalkbookLoader.load(from: Data(Walk.oneScreenJSON.utf8), source: "book.json")
        let outcomes: [RouteProbe.Outcome] = drifted ? [.drifted(step: 0, reason: "'Progress' matched nothing")] : []

        let report = try RouteProbeFixture.report(of: book, outcomes: outcomes, buildHash: AppBuildIdentity.hash(ofAppAt: walk.appPath))

        _ = try walk.performDryRun(leaving: report, of: book)

        #expect(walk.watch.phases == [.booting, .building, .running])
        let final = try #require(walk.progress())
        #expect(final.tool == "walk --dry-run")
        #expect(final.phase == (drifted ? .failed : .done))
        #expect(final.resultPath == nil)
        #expect(!FileManager.default.fileExists(atPath: walk.resultURL.path))
    }

    /// A walk that wrote its result names it on one trailing residue line, `result: <path>`, through the face that prints it — the file there, decodable — and nothing else in the answer changes (§4).
    @Test
    func aWalkThatWroteItsResultNamesItOnOneTrailingResidueLine() throws {
        let walk = try Walk()
        let outcome = try walk.performAsProduction(["--app-path", walk.appPath], session: "wiring")
        let command = try WalkCommand.parse([walk.walkbookPath, "--output", walk.output.path])
        var emitted: [String] = []

        try command.run(log: UsageLog(fileURL: walk.directory.url.appendingPathComponent("usage.jsonl"), now: { Date() }), emit: { emitted.append($0) }, emitError: { _ in }, walk: { outcome })

        let line = "result: \(walk.resultURL.path)"
        let served = outcome.servedAnswer()
        #expect(served.residue.last == line)
        #expect(Array(served.residue.dropLast()) == outcome.answer().residue)
        #expect(served.text.split(separator: "\n").filter { $0.hasPrefix("result: ") } == [Substring(line)])
        #expect(emitted.joined(separator: "\n").split(separator: "\n").filter { $0.hasPrefix("result: ") } == [Substring(line)])
        let result = try WalkResult.decoder().decode(WalkResult.self, from: Data(contentsOf: walk.resultURL))
        #expect(result.verdict == .passed)
    }

    /// The line is last even under notes, which a summary's own appended lines would have come after.
    @Test
    func theResultLineComesAfterTheNotes() throws {
        let walk = try Walk()
        let watched = try walk.performAsProduction(["--app-path", walk.appPath], session: "wiring")
        var noted = WalkCommand.Outcome(bundle: watched.bundle, survivedRunnerFailure: "the runner's own failure text")
        noted.resultPath = watched.resultPath

        let plain = noted.answer()
        let served = noted.servedAnswer()

        #expect(plain.residue.contains { $0.contains("the runner's own failure text") })
        #expect(served.residue.last == "result: \(walk.resultURL.path)")
        #expect(Array(served.residue.dropLast()) == plain.residue)
    }

    /// A walk nobody watched answers byte for byte as it always did: no result line, nothing else.
    @Test
    func anUnwatchedWalkServesItsAnswerUnchanged() throws {
        let walk = try Walk()

        let unwatched = try walk.perform([], watched: false)

        #expect(unwatched.servedAnswer() == unwatched.answer())
        #expect(unwatched.servedAnswer().text == unwatched.answer().text)
    }

    /// The files are named by the session Claude Code runs the walk in, and `default` without one, in the directory the usage log was moved to.
    @Test(arguments: ["a-session-id", nil])
    func theSessionNamesTheFilesAndDefaultStandsInForNone(session: String?) throws {
        let walk = try Walk()

        let outcome = try walk.performAsProduction(["--app-path", walk.appPath], session: session)

        let stem = session ?? "default"
        let progress = walk.directory.url.appendingPathComponent("progress/\(stem).json")

        #expect(FileManager.default.fileExists(atPath: progress.path))
        #expect(outcome.resultPath == walk.directory.url.appendingPathComponent("progress/\(stem).result.json").path)
    }

    /// `--verbose` is off unless passed, and refused beside `--dry-run`, which writes no result for it to shape.
    @Test
    func verboseIsOffByDefaultAndRefusedBesideADryRun() throws {
        #expect(try WalkCommand.parse(["book.json", "--output", "out.simwalk"]).verbose == false)
        #expect(try WalkCommand.parse(["book.json", "--output", "out.simwalk", "--verbose"]).verbose == true)
        #expect(throws: (any Error).self) { try WalkCommand.parse(["book.json", "--output", "probe.json", "--dry-run", "--verbose"]) }
    }

    /// `--verbose` reaches the result the production telemetry writes: each step's states present with it, absent without.
    @Test(arguments: [false, true])
    func verboseWritesEachStepsStatesIntoTheResult(verbose: Bool) throws {
        let walk = try Walk()

        _ = try walk.performAsProduction(["--app-path", walk.appPath] + (verbose ? ["--verbose"] : []), session: "wiring")

        let result = try WalkResult.decoder().decode(WalkResult.self, from: Data(contentsOf: walk.resultURL))

        #expect(!result.steps.isEmpty)
        #expect(result.steps.allSatisfy { ($0.states != nil) == verbose })
    }

    /// Two runs alive at once never write the same files, whether they share a session id or both fall back to `default` (SimWalk#83).
    @Test(arguments: ["a-session-id", nil])
    func twoRunsAliveAtOnceNeverShareAFile(session: String?) throws {
        let directory = try TemporaryDirectory()
        var environment = [UsageLog.overrideVariable: directory.url.appendingPathComponent("usage.jsonl").path]
        environment[WalkCommand.sessionVariable] = session
        let command = try WalkCommand.parse(["book.json", "--output", "out.simwalk"])

        let first = command.telemetry(environment: environment)
        let second = command.telemetry(environment: environment)

        #expect(first.writer.url != second.writer.url)
        #expect(first.resultURL != second.resultURL)
        #expect(first.writer.url == ProgressLocation.progressURL(session: session, in: directory.url))
    }
}

extension WalkProgressWiringTests {
    /// What a reader saw at each child the walk ran, and the clock the host times segments on — moved by each timed child by a different amount, so a segment filed under another's key cannot pass.
    final class Watch {
        var uptime: TimeInterval = 100
        /// The phases the file held as each child ran, consecutive repeats collapsed.
        private(set) var phases: [WalkProgress.Phase] = []
        /// The state when the runner's build ran.
        private(set) var atBuild: WalkProgress?
        /// The first state any child saw: the file as the host first wrote it.
        private(set) var first: WalkProgress?
        private var walked = false

        func observe(_ state: WalkProgress?, arguments: [String]) {
            if first == nil {
                first = state
            }
            if let state, phases.last != state.phase {
                phases.append(state.phase)
            }
            if arguments.contains("build-for-testing") {
                atBuild = state
                uptime += 3
            } else if arguments.starts(with: ["simctl", "bootstatus"]) {
                uptime += 1
            } else if arguments.starts(with: ["simctl", "install"]) {
                uptime += 2
            } else if arguments.contains("test-without-building"), !walked {
                walked = true
                uptime += 4
            }
        }
    }

    /// One scripted walk in a scratch directory of its own, watched through the progress file a reader polls.
    final class Walk {
        static var oneScreenJSON: String {
            #"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
        }

        static var twoScreenJSON: String {
            #"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]},{"id":"power","route":[{"tab":{"label":"Workouts"}}],"states":[{"theme":"light"}]}]}"#
        }

        let directory: TemporaryDirectory
        let appPath: String
        let walkbookPath: String
        let output: URL
        let progressURL: URL
        let resultURL: URL
        let watch = Watch()
        private let staged: URL
        private let appInstalled: Bool
        private let buildFails: Bool
        private(set) var runnerEnvironments: [[String: String]] = []
        /// Held for the length of the test, so its backstop never stands in for how a run ended.
        private var telemetry: WalkTelemetry?

        init(appInstalled: Bool = true, buildFails: Bool = false, twoScreens: Bool = false) throws {
            directory = try TemporaryDirectory()
            self.appInstalled = appInstalled
            self.buildFails = buildFails
            appPath = try Self.fakeApp(in: directory)
            let book = directory.url.appendingPathComponent("book.json")
            try Data((twoScreens ? Self.twoScreenJSON : Self.oneScreenJSON).utf8).write(to: book)
            walkbookPath = book.path
            staged = try CaptureBundleFixture.write(
                in: directory,
                captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen())]
            ).url
            output = directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)")
            progressURL = ProgressLocation.progressURL(session: "wiring", in: directory.url)
            resultURL = ProgressLocation.resultURL(session: "wiring", in: directory.url)
        }

        func progress() -> WalkProgress? {
            (try? Data(contentsOf: progressURL)).flatMap { try? WalkProgress.decoder().decode(WalkProgress.self, from: $0) }
        }

        func perform(_ arguments: [String], watched: Bool = true) throws -> WalkCommand.Outcome {
            let command = try command(arguments)
            return try walk(command, telemetry: watched ? makeTelemetry() : nil)
        }

        /// The walk watched by the telemetry the command builds in production, from an environment naming `session` and moving the usage log into this scratch directory, so both files land beside it.
        func performAsProduction(_ arguments: [String], session: String?) throws -> WalkCommand.Outcome {
            let command = try command(arguments)
            var environment = [UsageLog.overrideVariable: directory.url.appendingPathComponent("usage.jsonl").path]
            environment[WalkCommand.sessionVariable] = session
            let made = command.telemetry(environment: environment)
            telemetry = made
            return try walk(command, telemetry: made)
        }

        private func command(_ arguments: [String]) throws -> WalkCommand {
            try WalkCommand.parse([walkbookPath, "--output", output.path, "--device", "UDID-1"] + arguments)
        }

        private func walk(_ command: WalkCommand, telemetry: WalkTelemetry?) throws -> WalkCommand.Outcome {
            let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (staged, output))
            return try command.performWalk(shell: shell(script), pause: { _ in }, now: script.now, nonce: { "the-walks-own-nonce" }, runner: { Self.runner }, builds: builds, leases: leases, telemetry: telemetry)
        }

        func performDryRun(leaving report: RouteProbeReport, of book: Walkbook) throws -> WalkDryRun.Outcome {
            let stagedReport = directory.url.appendingPathComponent("staged-report.json")
            let reportURL = directory.url.appendingPathComponent("probe.json")
            try report.write(to: stagedReport, of: book)
            let script = WalkCommandTests.WalkScript(appPath: appPath, runnerStatus: 0, writes: (stagedReport, reportURL))
            let command = try WalkCommand.parse([walkbookPath, "--output", reportURL.path, "--device", "UDID-1", "--dry-run"])
            return try WalkDryRun.perform(command, shell: shell(script), pause: { _ in }, now: script.now, nonce: { RouteProbeFixture.nonce }, runner: { Self.runner }, builds: builds, leases: leases, telemetry: makeTelemetry())
        }

        private func makeTelemetry() -> WalkTelemetry {
            let made = WalkTelemetry(writer: ProgressWriter(url: progressURL, clock: { Date() }, pid: 4242), resultURL: resultURL, clock: { [watch] in watch.uptime })
            telemetry = made
            return made
        }

        /// The script, read through the progress file at every child, and with the app absent when the walk is to find it so.
        private func shell(_ script: WalkCommandTests.WalkScript) -> Shell {
            Shell(script: { [self] executable, arguments, environment in
                watch.observe(progress(), arguments: arguments)
                if arguments.contains("test-without-building") {
                    runnerEnvironments.append(environment)
                }
                if !appInstalled, arguments.starts(with: ["simctl", "get_app_container"]) {
                    return Shell.Result(status: 2, standardOutput: "", standardError: "No such file or directory\n")
                }
                if buildFails, arguments.contains("build-for-testing") {
                    return Shell.Result(status: 65, standardOutput: "", standardError: "error: the runner did not build\n")
                }
                return try script.run(executable, arguments, environment)
            })
        }

        private var builds: RunnerBuilds {
            RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        }

        private var leases: LeaseStore {
            LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
        }

        private static var runner: RunnerSource {
            RunnerSource(
                projectPath: "/Users/x/.simwalk/runner/snapshots/c0ffee/Runner/SimWalkRunner.xcodeproj",
                commit: "c0ffee0000000000000000000000000000000000",
                origin: .installed
            )
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
    }
}
