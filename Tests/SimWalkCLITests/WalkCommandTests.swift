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

/// What `walk` refuses before it boots anything — every one of these is an input that would otherwise be applied to nothing and reported as though it had been honoured — and the exit code it reports once it has walked.
struct WalkCommandTests {
    /// `--settle 0` and `--settle=-1` both fell through the runner's `milliseconds > 0` guard to the default: the walk ran, the bundle was written, and nothing said the flag had been ignored.
    ///
    /// The message is asserted rather than the type, because ArgumentParser wraps a `ValidationError` in its own `CommandError` before a caller ever sees it — so the type says nothing about which refusal fired.
    @Test(arguments: [["--settle", "0"], ["--settle=-1"]])
    func aQuietPeriodTheRunnerWouldDiscardIsRefusedAtTheCommandLine(_ arguments: [String]) throws {
        let thrown = try #require(#expect(throws: Error.self) {
            try WalkCommand.parse(["book.json", "--output", "example.simwalk"] + arguments)
        })

        #expect(WalkCommand.message(for: thrown).contains("--settle takes a quiet period in milliseconds greater than zero"))
    }

    @Test
    func aPositiveQuietPeriodIsAccepted() throws {
        let command = try WalkCommand.parse(["book.json", "--output", "example.simwalk", "--settle", "1200"])

        #expect(command.settle == 1200)
    }

    /// Omitting it is not the same as passing zero: the runner's own default applies, and the manifest records what was used.
    @Test
    func omittingTheQuietPeriodIsAccepted() throws {
        let command = try WalkCommand.parse(["book.json", "--output", "example.simwalk"])

        #expect(command.settle == nil)
    }

    /// A walk that holds every screen its walkbook asked for is a clean walk, and a clean walk exits 0.
    @Test
    func awalkThatHoldsEveryScreenExitsZero() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory)
        let recorder = StreamRecorder()

        try Self.command().run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) {
            WalkCommand.Outcome(bundle: bundle)
        }

        #expect(recorder.out.count == 1)
        #expect(recorder.err.isEmpty)
    }

    /// A simulator walk measures nothing, and says so rather than leaving the absence of figures to read as none (SimWalk#67, M4).
    @Test
    func aSimulatorWalkSaysMeasureWasDeviceOnlyAndNotRun() throws {
        let directory = try TemporaryDirectory()
        var outcome = try WalkCommand.Outcome(bundle: Self.bundle(in: directory))
        outcome.measureNote = "measure: device only, not run (about)"

        #expect(outcome.answer().text.contains("measure: device only, not run (about)"))
        #expect(!outcome.isQualified)
    }

    /// The field report that reopened this (SimWalk#1 item 1): a 13-screen walkbook ran 12 of 13 screens, one honestly unreachable, and the call came back 0 — indistinguishable from a complete walk to anything not reading stdout.
    @Test
    func awalkMissingAScreenExitsWithTheQualifiedCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, unreachable: ["harbours-list-return"])

        try Self.expectQualifiedExit(reporting: WalkCommand.Outcome(bundle: bundle), in: directory)
    }

    /// A capture taken before the tree stopped changing is the bundle's other qualification, and it rides the same code.
    @Test
    func awalkHoldingAnUnsettledCaptureExitsWithTheQualifiedCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, settled: false)

        try Self.expectQualifiedExit(reporting: WalkCommand.Outcome(bundle: bundle), in: directory)
    }

    /// A capture holding the app's chrome and nothing else is the bundle's third qualification — the artefacts are honest and what they are of is a screen that had not arrived.
    @Test
    func awalkHoldingOnlyChromeExitsWithTheQualifiedCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, hasContent: false)

        try Self.expectQualifiedExit(reporting: WalkCommand.Outcome(bundle: bundle), in: directory)
    }

    /// A walk that could not run at all is a refused *call* — the failure code, on stderr, with nothing on stdout — and never the qualified one, which claims a bundle exists.
    @Test
    func awalkThatCouldNotRunRefusesRatherThanQualifying() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command().run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) {
                throw CaptureBundleError.notABundle(path: "/nowhere.simwalk")
            }
        })

        #expect(thrown == ExitCode.failure)
        #expect(thrown != ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.count == 1)
    }

    /// An error walk's own internals do not classify still lands on `runner-failed`, never `unclassified` — the runner, the device, and walk's own file writes (the temporary walkbook `--screens` narrows to, say) are this tool's own machinery, never a caller's argument.
    @Test
    func awalkFailureWithNoMappedKindDefaultsToRunnerFailed() throws {
        struct Unmapped: Error, CustomStringConvertible {
            var description: String {
                "something this codebase has never classified"
            }
        }
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let log = Self.log(in: directory)

        #expect(throws: ExitCode.self) {
            try Self.command().run(log: log, emit: recorder.emit, emitError: recorder.emitError) {
                throw Unmapped()
            }
        }

        let entries = try UsageReport.entries(at: log.fileURL).entries
        #expect(entries.first?.kind == .runnerFailed)
    }

    /// **A failed runner is not a lost bundle** (SimWalk#3).
    ///
    /// One wedged screen makes `xcodebuild test` exit non-zero whatever `continueAfterFailure` says, and that used to take every other screen's capture with it — where the Brief's contract is per-screen outcomes.
    @Test
    func areadableBundleSurvivesArunnerFailureAndIsReportedRatherThanDiscarded() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory)

        let outcome = try WalkCommand.outcome(runnerFailure: Self.wedged, handback: Self.cleanHandback) { bundle }

        #expect(outcome.bundle == bundle)
        #expect(outcome.survivedRunnerFailure?.contains("main thread busy") == true)
        #expect(outcome.answer().text.contains("the runner reported a failure and this bundle survived it"))
        try Self.expectQualifiedExit(reporting: outcome, in: directory)
    }

    /// And a runner failure that left nothing readable behind is answered with the runner's own error, not with the bundle reader's — "the walk could not run" explains "there is no bundle here", and the reverse explains nothing.
    @Test
    func arunnerFailureThatWroteNoBundleIsAnsweredWithTheRunnersOwnError() {
        let thrown = #expect(throws: RunnerError.self) {
            try WalkCommand.outcome(runnerFailure: Self.wedged, handback: nil) {
                throw CaptureBundleError.manifestMissing(bundlePath: "/nowhere.simwalk", expectedPath: "/nowhere.simwalk/manifest.json")
            }
        }

        #expect(thrown != nil)
    }

    /// With no runner failure, a bundle that cannot be read is still the refusal it always was.
    @Test
    func abundleThatCannotBeReadIsStillArefusalWhenTheRunnerSucceeded() {
        #expect(throws: CaptureBundleError.self) {
            try WalkCommand.outcome(runnerFailure: nil, handback: nil) {
                throw CaptureBundleError.notABundle(path: "/nowhere.simwalk")
            }
        }
    }

    /// A walk with no readable bundle still ended an XCUITest session, so the refusal carries the handback — the runner's own error first, then the line with the command that switches accessibility back on.
    @Test
    func arefusalStillCarriesWhatTheWalkHandedTheDeviceBackIn() throws {
        let failed = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .failed(reason: "writing did not succeed")),
            appearance: .restored(.light)
        )

        let thrown = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: Self.wedged, handback: failed) {
                throw CaptureBundleError.notABundle(path: "/nowhere.simwalk")
            }
        })

        #expect(thrown.underlying is RunnerError)
        #expect(thrown.description.hasPrefix(String(describing: Self.wedged)))
        #expect(thrown.description.contains(AccessibilityPreference.command(udid: "UDID-1")))
    }

    /// A `Refusal` only ever wraps the runner's own failure or a `CaptureBundleError` from reading back the bundle that same runner just wrote — never an argument, so its kind is the runner's regardless of which of the two `underlying` happens to be.
    ///
    /// Both are pinned, since `CaptureBundleError`'s own default kind (used by `bundle inspect`/`bundle audit`) is the opposite one.
    @Test
    func arefusalsKindIsAlwaysRunnerFailed() throws {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .restored(.light)
        )

        let fromRunnerError = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: Self.wedged, handback: handback) {
                throw CaptureBundleError.notABundle(path: "/nowhere.simwalk")
            }
        })
        let fromBundleError = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: nil, handback: handback) {
                throw CaptureBundleError.manifestMissing(bundlePath: "/nowhere.simwalk", expectedPath: "/nowhere.simwalk/manifest.json")
            }
        })

        #expect(UsageFailureKind.of(fromRunnerError) == .runnerFailed)
        #expect(UsageFailureKind.of(fromBundleError) == .runnerFailed)
    }

    /// A restore that failed, or cannot be confirmed, reaches the verdict line an agent reads — not only the notes under the residue.
    @Test
    func ahandbackThatCouldNotPutTheDeviceBackQualifiesTheWalk() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory)
        let outcome = WalkCommand.Outcome(
            bundle: bundle,
            handback: DeviceHandback(
                accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restoredWithoutTeardown),
                appearance: .restored(.light)
            )
        )

        #expect(outcome.isQualified)
        #expect(outcome.answer().verdict.line.contains("a device accessibility restore a later teardown may undo"))
        try Self.expectQualifiedExit(reporting: outcome, in: directory)
    }

    /// A walk over an empty build directory passes `note` through to the build, so a caller is told a first build takes minutes (SimWalk#98, #118).
    @Test
    func aWalkOverAnEmptyBuildDirectoryTellsTheCallerItIsAColdBuild() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--device", "UDID-1"])
        var notes: [String] = []

        _ = try? command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), note: { notes.append($0) })

        #expect(notes == ["building the runner (c0ffee00) — a first build takes several minutes"])
    }

    /// The orchestration end to end against a script: the device's appearance is read before the runner and handed to it, and after the runner — here, one that failed — accessibility is switched back on and the appearance put back.
    ///
    /// The one thing no unit of it could show is that `performWalk` actually calls the handback, and in that order.
    @Test(arguments: [Int32(0), 65])
    func awalkReadsTheDeviceBeforeTheRunnerAndHandsItBackAfter(runnerStatus: Int32) throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: runnerStatus, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let runnerIndex = try #require(script.calls.firstIndex { $0.arguments.contains("test-without-building") })
        let readIndex = try #require(script.calls.firstIndex { $0.arguments == ["simctl", "ui", "UDID-1", "appearance"] })
        let restoreIndex = try #require(script.calls.firstIndex { $0.arguments.contains("write") })
        let putBackIndex = try #require(script.calls.firstIndex { $0.arguments == ["simctl", "ui", "UDID-1", "appearance", "light"] })

        #expect(readIndex < runnerIndex)
        #expect(runnerIndex < restoreIndex)
        #expect(runnerIndex < putBackIndex)
        #expect(script.calls[runnerIndex].environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] == "light")
        // The device's locale is read before the runner too, and handed to it (SimWalk#18).
        let localeIndex = try #require(script.calls.firstIndex { $0.arguments.last == "AppleLocale" })
        #expect(localeIndex < runnerIndex)
        #expect(script.calls[runnerIndex].environment["TEST_RUNNER_SIMWALK_DEVICE_LOCALE"] == "en_GB")
        #expect(outcome.handback?.accessibility.state == .restored)
        #expect(outcome.handback?.appearance == .restored(.light))
        #expect(outcome.handback?.reset == .held)
        #expect((outcome.survivedRunnerFailure != nil) == (runnerStatus != 0))
    }

    /// XCTest blamed the walk for a crash of a process named `xctest` on the Mac (SimWalk#176).
    ///
    /// The Mac's own crash reports say that process was not this walk's, so the runner failure is excused: the walk is `ok`, with no survived-failure qualification or note, and the excused line in the answer.
    @Test
    func aRunnerFailureThatIsXCTestBlamingAHostXCTestCrashLeavesTheWalkOk() throws {
        let directory = try TemporaryDirectory()
        let reports = try TemporaryDirectory()
        try Self.hostCrashReport.write(to: reports.url.appendingPathComponent("xctest-2026-10-21-102515.ips"), atomically: true, encoding: .utf8)
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Self.crashBlamingShell(script, failures: 2), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), crashReports: XCTestCrashEvidence(directory: reports.url))
        let answer = outcome.answer()

        #expect(answer.verdict.exitCode == 0)
        #expect(!answer.verdict.line.contains("a runner failure this bundle survived"))
        #expect(!answer.text.contains("the runner reported a failure and this bundle survived it"))
        #expect(answer.text.contains("XCTest reported 2 \"Critical process xctest crashed\" failures for crash reports of a host process named xctest, not this walk"))
    }

    /// The same failure with no crash report to explain it keeps its qualification and its note, and the answer adds what was searched.
    @Test
    func aRunnerFailureThatIsXCTestBlamingACrashNoReportExplainsStaysQualified() throws {
        let directory = try TemporaryDirectory()
        let reports = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Self.crashBlamingShell(script, failures: 1), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), crashReports: XCTestCrashEvidence(directory: reports.url))
        let answer = outcome.answer()

        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(answer.verdict.line.contains("a runner failure this bundle survived"))
        #expect(answer.text.contains("the runner reported a failure and this bundle survived it"))
        #expect(answer.text.contains("the runner failure is 1 \"Critical process xctest crashed\" failure; "))
    }

    /// The appearance retry's runner fails with exit 65, blaming a host `xctest` crash (SimWalk#176): the retry is folded in, and the walk is not qualified by that runner failure and carries the excused line.
    @Test
    func aRetryRunnerFailureThatIsXCTestBlamingAHostXCTestCrashLeavesTheWalkOk() throws {
        let (directory, retryDirectory, reports) = try (TemporaryDirectory(), TemporaryDirectory(), TemporaryDirectory())
        try Self.hostCrashReport.write(to: reports.url.appendingPathComponent("xctest-2026-10-21-102515.ips"), atomically: true, encoding: .utf8)
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url, retryStatus: 65)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Self.crashBlamingShell(script, failures: 2), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), crashReports: XCTestCrashEvidence(directory: reports.url))
        let answer = outcome.answer()

        #expect(outcome.bundle.manifest.appearanceSettle?.folded == true)
        #expect(!outcome.isQualified)
        #expect(answer.verdict.exitCode == 0)
        #expect(answer.text.contains("XCTest reported 2 \"Critical process xctest crashed\" failures for crash reports of a host process named xctest, not this walk"))
    }

    /// The appearance retry's crash-blame window ends when the retry's runner did, not when the blame is asked for: a host `xctest` crash captured after the runner ended explains nothing (SimWalk#179).
    @Test
    func aHostXCTestCrashCapturedAfterTheRetryRunnerEndedDoesNotExcuseItsFailure() throws {
        let (directory, retryDirectory, reports) = try (TemporaryDirectory(), TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url, retryStatus: 65)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        // Nothing scripted runs once the retry runner has returned, so the scripts' clock stands at the runner's end. This clock, from the retry runner's return, reads that instant and then moves 30 s on with every read: the end the walk records is the runner's, any later read is well past it. The blame's `xcresulttool` call, before it reads the crash reports, files a host crash captured 3 s after the runner's end on the scripts' clock: outside a window that ends with the runner, inside one that ends at a later read.
        var skew: TimeInterval = 0
        let now: () -> Date = {
            guard script.walkedScreens.count > 1 else { return script.now() }
            defer { skew += 30 }
            return script.now().addingTimeInterval(skew)
        }
        let atTheBlame = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS"
            let capturedAt = formatter.string(from: script.now().addingTimeInterval(3))
            let report = Self.hostCrashReport.replacingOccurrences(of: "1969-12-31 23:59:59.0000", with: capturedAt)
            do {
                try report.write(to: reports.url.appendingPathComponent("xctest-2026-10-21-102515.ips"), atomically: true, encoding: .utf8)
            } catch {
                Issue.record(error)
            }
        }

        let outcome = try command.performWalk(shell: Self.crashBlamingShell(script, failures: 2, atTheBlame: atTheBlame), pause: { _ in }, now: now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), crashReports: XCTestCrashEvidence(directory: reports.url))
        let answer = outcome.answer()

        // Without the report there is nothing to excuse the failure, and the expectations below would pass for no reason.
        #expect(FileManager.default.fileExists(atPath: reports.url.appendingPathComponent("xctest-2026-10-21-102515.ips").path))
        #expect(outcome.isQualified)
        #expect(answer.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(answer.verdict.line.contains("a runner failure the appearance retry survived"))
        #expect(!answer.text.contains("not this walk"))
    }

    /// A host `xctest` crash report, captured one second before the epoch the scripts' clock counts from: inside the hour before the run.
    static var hostCrashReport: String {
        """
        {"app_name":"xctest","timestamp":"1969-12-31 23:59:59.00 +0000","bug_type":"309","os_version":"macOS 27.0.1 (26A434)","name":"xctest"}
        {"procName":"xctest","procPath":"/private/var/folders/*/xctest","captureTime":"1969-12-31 23:59:59.0000 +0000","parentProc":"sleep","exception":{"type":"EXC_CRASH","signal":"SIGKILL (Code Signature Invalid)"},"termination":{"namespace":"CODESIGNING","indicator":"Launch Constraint Violation"}}
        """
    }

    /// `xcresulttool get test-results tests` as it lists `failures` XCTest failure messages blaming a crash of `xctest`.
    static func crashFailuresJSON(_ failures: Int) -> String {
        let messages = Array(repeating: #"{"name":"Critical process xctest crashed in (null)","nodeType":"Failure Message"}"#, count: failures).joined(separator: ",")
        return #"{"devices":[],"testPlanConfigurations":[],"testNodes":[{"nodeType":"Test Plan","name":"SimWalkRunner","children":[{"nodeType":"UI test bundle","name":"SimWalkRunner","children":[{"nodeType":"Test Suite","name":"WalkRunner","children":[{"nodeType":"Test Case","name":"testWalk()","children":["# + messages + "]}]}]}]}]}"
    }

    /// `script` as a runner that fails with exit 65 having made its result bundle, and whose result bundle lists `failures` crash-blaming failures; `atTheBlame` runs when the blame reads that bundle, before it reads the crash reports.
    private static func crashBlamingShell(_ script: WalkScript, failures: Int, atTheBlame: @escaping () -> Void = {}) -> Shell {
        Shell(script: { executable, arguments, environment in
            if arguments.starts(with: ["xcresulttool", "get", "test-results", "tests"]) {
                atTheBlame()
                return Shell.Result(status: 0, standardOutput: crashFailuresJSON(failures), standardError: "")
            }
            let result = try script.run(executable, arguments, environment)
            if arguments.contains("test-without-building"), let flag = arguments.firstIndex(of: "-resultBundlePath") {
                try FileManager.default.createDirectory(atPath: arguments[flag + 1], withIntermediateDirectories: true)
            }
            return result
        })
    }

    /// SimWalk#107: an `--output` left without `.simwalk` is completed rather than refused, and the answer's first line says so.
    @Test
    func anOutputWithoutTheSuffixIsCompletedAndTheHeaderSaysSo() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let unnamed = writes.to.deletingPathExtension()
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", unnamed.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(outcome.answer().header.hasSuffix("output: \(writes.to.standardizedFileURL.path) (suffix added)"))
    }

    /// The handback judges the runner's last reset by whether a finalised bundle came back, not by `xcodebuild`'s exit status.
    ///
    /// The SimWalk#19 review: `xcodebuild` exits non-zero for any recorded XCTest failure on a runner that still ran its last reset and wrote its manifest. So a runner that failed *and* finished, leaving the device dark, is a reset that did not hold — and one that left no bundle is inconclusive.
    @Test(arguments: [(Int32(0), true), (65, true), (65, false)])
    func thehandbackJudgesTheLastResetByAFinishedBundle(runnerStatus: Int32, finished: Bool) throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: runnerStatus, appearanceAfterRunner: "dark", writes: finished ? writes : nil)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let handback: DeviceHandback?
        do {
            handback = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory)).handback
        } catch let refusal as WalkCommand.Refusal {
            handback = refusal.handback
        }

        #expect(handback?.reset == (finished ? .didNotHold(read: .dark) : .inconclusive(read: .dark)))
    }

    /// `performWalk` generates its own nonce the way `WalkDryRun.perform` does and hands it to the runner (SimWalk#41) — what `bundleWrittenBy` then checks the written bundle back against.
    @Test
    func awalkHandsTheRunnerItsNonce() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { "the-walks-own-nonce" }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let runnerIndex = try #require(script.calls.firstIndex { $0.arguments.contains("test-without-building") })

        #expect(script.calls[runnerIndex].environment["TEST_RUNNER_SIMWALK_NONCE"] == "the-walks-own-nonce")
        #expect(outcome.bundle.manifest.nonce == "the-walks-own-nonce")
    }

    /// SimWalk#50: the runner is handed `-resultBundlePath` so a refusal can read a named result bundle rather than search for one, and the path is keyed by the walk's own nonce — two walks of the same build never collide on one.
    @Test
    func awalkPassesItsResultBundlePathToTheRunnerKeyedByTheNonce() throws {
        let buildsDirectory = try TemporaryDirectory()
        let builds = RunnerBuilds(directory: buildsDirectory.url.appendingPathComponent("runner-builds", isDirectory: true))

        let directoryA = try TemporaryDirectory()
        let writesA = try Self.runnerWrites(in: directoryA)
        let scriptA = try WalkScript(appPath: Self.fakeApp(in: directoryA), runnerStatus: 0, writes: writesA)
        let commandA = try WalkCommand.parse([Self.walkbook(in: directoryA), "--output", writesA.to.path, "--device", "UDID-1"])
        _ = try commandA.performWalk(shell: Shell(script: scriptA.run), pause: { _ in }, now: scriptA.now, nonce: { "walk-one-nonce" }, runner: { Self.runner }, builds: builds, leases: Self.leases(in: buildsDirectory))

        let directoryB = try TemporaryDirectory()
        let writesB = try Self.runnerWrites(in: directoryB)
        let scriptB = try WalkScript(appPath: Self.fakeApp(in: directoryB), runnerStatus: 0, writes: writesB)
        let commandB = try WalkCommand.parse([Self.walkbook(in: directoryB), "--output", writesB.to.path, "--device", "UDID-1"])
        _ = try commandB.performWalk(shell: Shell(script: scriptB.run), pause: { _ in }, now: scriptB.now, nonce: { "walk-two-nonce" }, runner: { Self.runner }, builds: builds, leases: Self.leases(in: buildsDirectory))

        let runnerCallA = try #require(scriptA.calls.first { $0.arguments.contains("test-without-building") })
        let runnerCallB = try #require(scriptB.calls.first { $0.arguments.contains("test-without-building") })
        let pathA = try #require(Self.resultBundlePath(in: runnerCallA.arguments))
        let pathB = try #require(Self.resultBundlePath(in: runnerCallB.arguments))

        #expect(pathA != pathB)
    }

    /// The `-resultBundlePath` value handed to `xcodebuild`, or `nil` when the flag is absent.
    private static func resultBundlePath(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-resultBundlePath"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// A binary with no runner of its own refuses before anything is booted or installed — the refusal is knowable from the machine, and a boot and an install would be spent learning it.
    @Test
    func anunpairedBinaryRefusesBeforeTheSimulatorIsTouched() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([
            Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path,
            "--device", "UDID-1", "--app-path", Self.fakeApp(in: directory),
        ])
        let unpaired = RunnerProjectError.notInstalled(binaryHash: String(repeating: "2b", count: 32), latest: nil, variable: RunnerProject.overrideVariable)

        #expect(throws: unpaired) {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { throw unpaired }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        }
        #expect(script.calls.isEmpty)
    }

    /// A walk's slim boot touches only a device SimWalk created: on a device it did not (a lease on an existing one) with `--app-path`, nothing is written to the override directory and the answer says nothing of a slim decision.
    @Test
    func aWalkOnADeviceItDidNotCreateWritesNoOverrideAndSaysNothingOfIt() throws {
        let directory = try TemporaryDirectory()
        let overrideRoot = directory.url.appendingPathComponent("override-root", isDirectory: true)
        try FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, booted: false)
        let command = try WalkCommand.parse([
            Self.walkbook(in: directory), "--output", writes.to.path,
            "--device", "UDID-1", "--app-path", Self.fakeApp(in: directory),
        ])
        let shell = Shell(script: script.run)

        let outcome = try command.performWalk(
            shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory),
            provisioning: { SlimWalkProvisioning(shell: $0, overrides: DisabledServicesOverride(root: overrideRoot)) }
        )

        #expect(try FileManager.default.contentsOfDirectory(atPath: overrideRoot.path).isEmpty)
        #expect(outcome.deviceNote == nil)
        #expect(script.calls.contains { $0.arguments.starts(with: ["simctl", "boot"]) })
    }

    /// A device handed back as it was found is printed under the summary and qualifies nothing: it is a fact about the machine, and a bundle is not less trustworthy for it (SimWalk#5).
    @Test
    func whatTheWalkLeftTheDeviceInIsReportedWithoutQualifyingTheBundle() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory)
        let recorder = StreamRecorder()
        let outcome = WalkCommand.Outcome(bundle: bundle, handback: Self.cleanHandback)

        #expect(!outcome.isQualified)
        try Self.command().run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) { outcome }

        #expect(recorder.out.first?.contains(Self.cleanHandback.accessibility.note) == true)
    }

    /// SimWalk#16: the walk builds the runner it resolved, in a build directory keyed to that runner, and hands the runner its own commit to record — never the one shared directory every source used to build into.
    @Test
    func thewalkBuildsItsRunnerInADirectoryOfItsOwnAndRecordsItsCommit() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        _ = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let build = try #require(script.calls.first { $0.arguments.contains("build-for-testing") })
        let walk = try #require(script.calls.first { $0.arguments.contains("test-without-building") })
        let expected = Self.builds(in: directory).directory(for: Self.runner).path
        let derivedData = try [build, walk].map { call in
            try call.arguments[#require(call.arguments.firstIndex(of: "-derivedDataPath")) + 1]
        }

        #expect(derivedData == [expected, expected])
        #expect([build, walk].allSatisfy { $0.arguments.contains(Self.runner.projectPath) })
        #expect(expected.hasSuffix("/runner-builds/\(Self.runner.buildKey)"))
        #expect(Self.builds(in: directory).builtProject(at: URL(fileURLWithPath: expected)) == Self.runner.projectPath)
        #expect(walk.environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] == Self.runner.commit)
    }

    /// The SimWalk#22 review's finding 3: the walk records its build's use as soon as it has resolved its runner, before the boot and the install that take tens of seconds — so a prune planned meanwhile keeps the build, and the snapshot and binding it names.
    ///
    /// An install that fails still leaves the record, which is how it can be seen to come first.
    @Test
    func thewalkRecordsItsBuildsUseBeforeTheDeviceIsTouched() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, failing: ["install"])
        let command = try WalkCommand.parse([
            Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path,
            "--device", "UDID-1", "--app-path", Self.fakeApp(in: directory),
        ])

        _ = try? command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let build = Self.builds(in: directory).directory(for: Self.runner)

        #expect(!script.calls.contains { $0.arguments.contains("build-for-testing") })
        #expect(Self.builds(in: directory).builtProject(at: build) == Self.runner.projectPath)
    }

    /// The runner's own line has to land wherever the driver's did.
    ///
    /// `SIMWALK_USAGE_LOG` names a *file*, and the runner used to be handed a fixed `~/.simwalk` directory it computed for itself, so an overridden log's `walk` line landed in scratch while its `walk.runner` line landed in the real log. `performWalk` now resolves the file once and hands the runner that exact path.
    @Test
    func thewalkHandsTheRunnerTheResolvedLogFileNotAFixedDirectory() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let overriddenLog = directory.url.appendingPathComponent("scratch-calls.jsonl")

        _ = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, logFileURL: overriddenLog, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        let walk = try #require(script.calls.first { $0.arguments.contains("test-without-building") })

        #expect(walk.environment["TEST_RUNNER_SIMWALK_LOG"] == overriddenLog.path)
    }

    /// A walk refuses an `--output` that already holds something, before anything is touched (the SimWalk#19 review).
    ///
    /// The runner would refuse it in its own process and leave the old bundle there, and the host read that back as this walk's result — down to a device check that read `held`. The old bundle is readable, which is exactly the problem.
    @Test
    func anoutputThatAlreadyHoldsABundleIsRefusedBeforeTheSimulatorIsTouched() throws {
        let directory = try TemporaryDirectory()
        let stale = try Self.bundle(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", stale.url.path, "--device", "UDID-1"])

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        })

        guard case .bundleDirectoryNotEmpty = thrown else {
            Issue.record("expected the output to be refused as not empty, got \(thrown)")
            return
        }

        #expect(script.calls.isEmpty)
    }

    /// A bundle whose manifest started before the walk launched its runner is another walk's, and is refused rather than reported as this one's — the belt to the empty-output refusal's braces.
    @Test
    func abundleThatStartedBeforeTheWalkLaunchedIsRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, nonce: "this-walks-nonce")
        let launched = bundle.manifest.startedAt.addingTimeInterval(60)

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try WalkCommand.bundleWrittenBy(walkLaunchedAt: launched, buildHash: bundle.manifest.appBuildHash, nonce: "this-walks-nonce", at: bundle.url)
        })
        guard case let .bundleFromAnotherWalk(path, problems) = thrown else {
            Issue.record("expected .bundleFromAnotherWalk, got \(thrown)")
            return
        }

        #expect(path == bundle.url.path)
        #expect(problems.count == 1)
        #expect(problems.first?.contains("before this walk launched its runner") == true)
        #expect(try WalkCommand.bundleWrittenBy(walkLaunchedAt: bundle.manifest.startedAt, buildHash: bundle.manifest.appBuildHash, nonce: "this-walks-nonce", at: bundle.url) == bundle)
    }

    /// A bundle whose manifest carries another walk's nonce is refused the same way — the SimWalk#41 gap two overlapping walks of the same build to the same path leave the started-before and build-hash checks unable to close.
    @Test
    func abundleCarryingAnotherWalksNonceIsRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, nonce: "the-other-walks-nonce")

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try WalkCommand.bundleWrittenBy(walkLaunchedAt: bundle.manifest.startedAt, buildHash: bundle.manifest.appBuildHash, nonce: "this-walks-nonce", at: bundle.url)
        })
        guard case let .bundleFromAnotherWalk(_, problems) = thrown else {
            Issue.record("expected .bundleFromAnotherWalk, got \(thrown)")
            return
        }

        #expect(problems.count == 1)
        #expect(problems.first?.contains("another walk's nonce") == true)
    }

    /// A bundle whose manifest carries no nonce at all — one written before this format, or by a walk that generated none — is refused too: absent is not a match, never a pass.
    @Test
    func abundleCarryingNoNonceIsRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, nonce: nil)

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try WalkCommand.bundleWrittenBy(walkLaunchedAt: bundle.manifest.startedAt, buildHash: bundle.manifest.appBuildHash, nonce: "this-walks-nonce", at: bundle.url)
        })
        guard case let .bundleFromAnotherWalk(_, problems) = thrown else {
            Issue.record("expected .bundleFromAnotherWalk, got \(thrown)")
            return
        }

        #expect(problems.count == 1)
        #expect(problems.first?.contains("carries no nonce") == true)
    }

    /// A bundle walked against a build other than this walk's own is refused too, whatever its nonce says.
    @Test
    func abundleWalkedAgainstAnotherBuildIsRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, buildHash: "deadbeef", nonce: "this-walks-nonce")

        let thrown = try #require(#expect(throws: CaptureBundleError.self) {
            try WalkCommand.bundleWrittenBy(walkLaunchedAt: bundle.manifest.startedAt, buildHash: "a1b2c3d4", nonce: "this-walks-nonce", at: bundle.url)
        })
        guard case let .bundleFromAnotherWalk(_, problems) = thrown else {
            Issue.record("expected .bundleFromAnotherWalk, got \(thrown)")
            return
        }

        #expect(problems.count == 1)
        #expect(problems.first?.contains("walked against build") == true)
    }

    /// SimWalk#26, the trap end to end against a script: the first pass refuses `progress`'s dark state — the device reported it set and drew light — so the walk settles the device (set dark, a shutdown, a boot, the found one back) and walks `progress` alone again, and the second attempt's captures are what the bundle holds, with the settle in its manifest and on its answer.
    ///
    /// Only the refused screen is walked again: `browse` was judged on the first pass and stands.
    @Test
    func adarkStateTheDeviceDidNotDrawIsWalkedAgainAfterASettleAndTheManifestSaysSo() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let runners = script.calls.indices.filter { script.calls[$0].arguments.contains("test-without-building") }
        let setDark = try #require(script.calls.firstIndex { $0.arguments == ["simctl", "ui", "UDID-1", "appearance", "dark"] })
        let shutdown = try #require(script.calls.firstIndex { $0.arguments == ["simctl", "shutdown", "UDID-1"] })
        let boot = try #require(script.calls.firstIndex { $0.arguments == ["simctl", "boot", "UDID-1"] })
        #expect(runners.count == 2)
        #expect(try #require(runners.first) < setDark && setDark < shutdown && shutdown < boot && boot < runners[1])
        #expect(script.calls[boot ..< runners[1]].contains { $0.arguments == ["simctl", "ui", "UDID-1", "appearance", "light"] })
        #expect(script.walkedScreens == [["progress", "browse"], ["progress"]])

        let progress = try #require(outcome.bundle.manifest.screens.first)
        #expect(progress.outcome == .captured)
        #expect(progress.captures.map(\.state.theme) == [.light, .dark])
        #expect(outcome.bundle.manifest.screens.last?.captures.map(\.state.theme) == [.light])
        let settle = try #require(outcome.bundle.manifest.appearanceSettle)
        #expect(settle.appearance == .dark)
        #expect(settle.retried.map(\.id) == ["progress"])
        #expect(settle.retried.first?.firstRefusedStates == [Walkbook.CaptureState(theme: .dark)])
        #expect(try CaptureBundle.read(at: writes.to).manifest == outcome.bundle.manifest)
        #expect(!outcome.isQualified)
        #expect(outcome.answer().text.contains("progress — first refused [dark]; now captured"))
        #expect(outcome.handback?.reset == .held)
        #expect(outcome.handback?.appearance == .restored(.light))
        // The second runner's scratch bundle is gone once the fold has taken what it needed.
        #expect(script.outputs.count == 2)
        #expect(!FileManager.default.fileExists(atPath: script.outputs[1]))
    }

    /// Review finding 6: a second runner that leaves nothing to fold recovers nothing and loses nothing — the first attempt stands, the manifest records the settle and why nothing was folded (finding 3), the verdict is qualified, the answer says it once, and the scratch bundle is gone.
    @Test
    func asecondPassThatLeavesNothingToFoldKeepsTheFirstAttemptAndRecordsTheSettle() throws {
        let directory = try TemporaryDirectory()
        let first = try Self.refusingDark(in: directory)
        let writes = (bundle: first.url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(script.walkedScreens.count == 2)
        #expect(outcome.bundle.manifest.screens == first.manifest.screens)
        let settle = try #require(outcome.bundle.manifest.appearanceSettle)
        #expect(settle.settleFailure == nil)
        #expect(settle.secondPassFailure != nil)
        #expect(settle.retried.map(\.id) == ["progress"])
        let answer = outcome.answer()
        #expect(answer.verdict.line.contains("an appearance retry that could not be folded in"))
        #expect(answer.text.contains("left nothing that could be folded in"))
        #expect(!answer.text.contains("left nothing this walk could fold in"))
        #expect(!FileManager.default.fileExists(atPath: script.outputs[1]))
    }

    /// Review finding 6: a second runner that failed and left a bundle is folded — the first pass's rule — and its failure qualifies the verdict and is printed.
    @Test
    func asecondRunnerThatFailedAndLeftABundleIsFoldedAndQualifiesTheWalk() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(
            appPath: Self.fakeApp(in: directory),
            runnerStatus: 0,
            writes: writes,
            retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url,
            retryStatus: 65
        )
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(outcome.bundle.manifest.screens.first?.outcome == .captured)
        #expect(outcome.bundle.manifest.appearanceSettle?.folded == true)
        #expect(outcome.answer().verdict.line.contains("a runner failure the appearance retry survived"))
        #expect(outcome.answer().text.contains("the runner reported a failure walking the refused screens again after the appearance settle"))
    }

    /// Review finding 6: the second runner's last reset is judged too — it left the device dark where it was found light, so the bundle's light captures from that pass rest on a reset that did not hold, and the verdict says so.
    @Test
    func asecondRunnersResetThatDidNotHoldQualifiesTheWalk() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(
            appPath: Self.fakeApp(in: directory),
            runnerStatus: 0,
            writes: writes,
            retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url,
            appearanceAfterRetry: "dark"
        )
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(outcome.handback?.reset == .didNotHold(read: .dark))
        #expect(outcome.answer().verdict.line.contains("an appearance reset that did not hold"))
    }

    /// A second attempt refused again — the fixture scripts the refusal the runner's own check would give on the settled device — is folded in, after one settle and no loop.
    ///
    /// What this pins is the walk's side: a re-refused attempt keeps what the first kept, so it is taken; the device is shut down once; the answer names the screen refused on both attempts. Whether the settled device's check refuses again is `StateApplicationCheck`'s, pinned in its own tests.
    @Test
    func aretryRefusedAgainIsFoldedAfterOneSettleAndNoLoop() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: true).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let progress = try #require(outcome.bundle.manifest.screens.first)
        guard case .stateNotApplied = progress.outcome else {
            Issue.record("a dark state still drawn light after the settle must stay refused, got \(progress.outcome)")
            return
        }

        #expect(progress.refusedStates == [Walkbook.CaptureState(theme: .dark)])
        #expect(progress.captures.map(\.state.theme) == [.light])
        #expect(outcome.bundle.manifest.appearanceSettle?.retried.map(\.id) == ["progress"])
        #expect(script.walkedScreens.count == 2)
        #expect(script.calls.count { $0.arguments == ["simctl", "shutdown", "UDID-1"] } == 1)
        #expect(outcome.isQualified)
        #expect(outcome.answer().text.contains("progress — first refused [dark]; now refused, state not applied"))
    }

    /// A device that drew the appearance it reported pays nothing: one runner, no shutdown, no boot, and a manifest with no settle in it.
    @Test
    func adeviceThatDrewTheAppearanceItReportedPaysNoReboot() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.drewBoth(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(script.walkedScreens.count == 1)
        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "shutdown"]) || $0.arguments.starts(with: ["simctl", "boot"]) })
        #expect(outcome.bundle.manifest.appearanceSettle == nil)
        #expect(!outcome.isQualified)
    }

    /// A settle that could not boot the device again recovers nothing and loses nothing: the first attempt's bundle stands, refusal and all, and the verdict says the settle did not complete, with the command that boots the device.
    ///
    /// The manifest records the settle and the step it stopped at (review finding 3) — the device was shut down, and a reader of the bundle has to be able to see that. Round 1 left `appearanceSettle` out here and this test pinned its absence; the spec's "the manifest records that a settle happened" is what changed it.
    ///
    /// The reset judgement is the first runner's — read before the settle — because what the device reads after a failed settle is the settle's doing.
    @Test
    func asettleThatCouldNotBootLeavesTheFirstAttemptAndQualifiesTheWalk() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, failing: ["boot"])
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(script.walkedScreens.count == 1)
        #expect(outcome.bundle.manifest.appearanceSettle?.settleFailure?.hasPrefix("booting it") == true)
        #expect(outcome.answer().text.contains("the settle stopped booting it"))
        #expect(outcome.bundle.manifest.screens.first?.refusedStates == [Walkbook.CaptureState(theme: .dark)])
        #expect(outcome.answer().verdict.line.contains("an appearance settle that did not complete"))
        #expect(outcome.answer().text.contains("run: xcrun simctl boot UDID-1"))
        #expect(outcome.handback?.reset == .held)
    }

    /// SimWalk#26, review finding 1: a device found dark whose states were refused on appearance is settled the one way measured to cure the trap — set dark, rebooted — and nothing is switched after the boot, so the second runner walks the device as the walk found it.
    ///
    /// Round 1 booted it light and switched it to dark before the second pass, the trap's own trigger.
    @Test
    func adeviceFoundDarkIsSettledDarkAndNotSwitchedBeforeTheSecondPass() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingBothOnADarkDevice(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(
            appPath: Self.fakeApp(in: directory),
            runnerStatus: 0,
            appearance: "dark",
            appearanceAfterRunner: "dark",
            writes: writes,
            retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url
        )
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let runners = script.calls.indices.filter { script.calls[$0].arguments.contains("test-without-building") }
        let setDark = try #require(script.calls.firstIndex { $0.arguments == ["simctl", "ui", "UDID-1", "appearance", "dark"] })
        let boot = try #require(script.calls.firstIndex { $0.arguments == ["simctl", "boot", "UDID-1"] })
        #expect(runners.count == 2)
        #expect(try #require(runners.first) < setDark && setDark < boot && boot < runners[1])
        #expect(!script.calls[boot ..< runners[1]].contains { $0.arguments.starts(with: ["simctl", "ui", "UDID-1", "appearance"]) && $0.arguments.count == 5 })
        let settle = try #require(outcome.bundle.manifest.appearanceSettle)
        #expect(settle.appearance == .dark)
        #expect(settle.found == .dark)
        #expect(outcome.bundle.manifest.screens.first?.outcome == .captured)
        #expect(outcome.answer().text.contains("so the device was set dark, shut down and booted — the appearance it was found in"))
        #expect(outcome.handback?.appearance == .restored(.dark))
        #expect(!outcome.isQualified)
    }

    /// The round-2 review's finding 1: a device the walk found already booted, and was not given by UDID — resolved by name, or taken as the booted default — may be another session's, so a refusal on appearance does not reboot it.
    ///
    /// Nothing touches the device between the runner and the handback: one runner, no shutdown, no boot, every screen's record the first attempt's. The verdict is qualified — the walk meant to cure these screens and did not — and the answer prints the settle a person runs, generated from the steps a settle takes.
    ///
    /// The manifest records the settle not made, why and that command (the round-3 review's finding 3); round 2 left `appearanceSettle` out here and this test pinned its absence, so an `inspect` of the bundle said nothing of it.
    @Test(arguments: [["--device", "iPhone 17 Pro"], []])
    func adeviceTheWalkFoundBootedAndWasNotGivenByUDIDIsNotRebooted(selection: [String]) throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.refusingDark(in: directory)
        let writes = (bundle: first.url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path] + selection)

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(!script.calls.contains { $0.arguments == ["simctl", "shutdown", "UDID-1"] || $0.arguments == ["simctl", "boot", "UDID-1"] })
        #expect(script.walkedScreens.count == 1)
        #expect(outcome.bundle.manifest.screens == first.manifest.screens)
        let settleCommand = "xcrun simctl ui UDID-1 appearance dark && xcrun simctl shutdown UDID-1 && xcrun simctl boot UDID-1 && xcrun simctl bootstatus UDID-1 -b && xcrun simctl ui UDID-1 appearance light"
        let settle = try #require(outcome.bundle.manifest.appearanceSettle)
        #expect(settle.declined?.command == settleCommand)
        #expect(settle.declined?.reason.contains("--device UDID-1") == true)
        #expect(settle.retried.map(\.id) == ["progress"])
        #expect(settle.milliseconds == 0)
        let answer = outcome.answer()
        #expect(answer.verdict.line.contains("an appearance settle not made on a device this walk did not boot, lease or get by UDID"))
        #expect(settle.declined?.reason.contains("simwalk lease acquire --device UDID-1") == true)
        #expect(answer.text.contains(settleCommand))
        #expect(outcome.handback?.reset == .held)
    }

    /// And a device this walk booted itself — shut down when the walk resolved it by name — had nothing of anybody else's on it, so it is settled as one named by UDID is.
    @Test
    func adeviceTheWalkBootedItselfIsSettledWhenResolvedByName() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(
            appPath: Self.fakeApp(in: directory),
            runnerStatus: 0,
            writes: writes,
            retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url,
            booted: false
        )
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "iPhone 17 Pro"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(script.calls.contains { $0.arguments == ["simctl", "shutdown", "UDID-1"] })
        #expect(script.walkedScreens == [["progress", "browse"], ["progress"]])
        #expect(outcome.bundle.manifest.screens.first?.outcome == .captured)
        #expect(!outcome.isQualified)
    }

    /// The round-2 review's finding 2: a fold that fails and cannot be undone leaves the only copy of the first attempt set aside in the scratch bundle — so the scratch bundle is kept, not removed, and the pass says where the first attempt is.
    @Test
    func afoldThatCannotBeUndoneKeepsTheScratchBundleAndSaysWhereTheFirstAttemptIs() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.refusingDark(in: directory)
        let retry = try Self.progressAgain(in: retryDirectory, refusingDark: false, nonce: "retry-nonce")
        let bookPath = try Self.lightAndDarkWalkbook(in: directory)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: bookPath))
        var outputs: [String] = []
        defer {
            for output in outputs {
                try? FileManager.default.removeItem(atPath: output)
            }
        }
        // Every move out of a retry's scratch bundle fails: the second attempt cannot come in, nor the first go back.
        let failing = FailingMoves.fileManager { source, _ in source.path.contains("/simwalk-retry-") }
        var appearance = "light"
        let run: (String, [String], TimeInterval) throws -> Shell.Result = { _, arguments, _ in
            if arguments.starts(with: ["simctl", "ui"]), arguments.count == 5 {
                appearance = arguments[4]
            }
            return Shell.Result(status: 0, standardOutput: "\(appearance)\n", standardError: "")
        }
        let pass = AppearanceRetryPass(udid: "UDID-1", found: .light, walkbookPath: bookPath, mayReboot: true, buildHash: "a1b2c3d4", fileManager: failing, nonce: { "retry-nonce" }, renew: { _ in nil }, walk: { _, output, _ in
            outputs.append(output)
            try FileManager.default.copyItem(at: retry.url, to: URL(fileURLWithPath: output))
        })

        let outcome = try #require(pass.perform(after: first, of: book, run: run, now: { Date(timeIntervalSince1970: 0) }))

        let scratch = try URL(fileURLWithPath: #require(outputs.first))
        let setAside = CaptureBundleLayout.setAsideDirectory(in: scratch)
        guard case let .foldNotUndone(reason) = outcome.report else {
            Issue.record("a fold that could not be undone must be answered as one, got \(outcome.report)")
            return
        }

        #expect(reason.contains("set aside at \(setAside.path)"))
        #expect(FileManager.default.fileExists(atPath: CaptureBundle.manifestURL(in: setAside).path))
        #expect(outcome.report.notes(udid: "UDID-1", recorded: false).contains { $0.contains(setAside.path) })
    }

    /// The round-3 review's finding 2: no move a fold makes leaves the bundle's own folder — the second pass's scratch bundle is written inside the first — so none of them can be a copy and a delete between two volumes.
    ///
    /// Between volumes a move copies and then deletes, and one that fails between the two leaves a directory half in each place: with the scratch bundle under `$TMPDIR` and `--output` on another volume, the first attempt's screen was copied aside, partly deleted, never recorded as moved, and the scratch bundle holding its only whole copy then removed. Here every move that crosses the bundle's edge fails exactly that way, so the fold completes only if none does.
    @Test
    func everyMoveAFoldMakesStaysInsideTheBundleSoNoneIsACopyBetweenVolumes() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.refusingDark(in: directory)
        let retry = try Self.progressAgain(in: retryDirectory, refusingDark: false, nonce: "retry-nonce")
        let bookPath = try Self.lightAndDarkWalkbook(in: directory)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: bookPath))
        let inside = first.url.path + "/"
        let crossing = FailingMoves.partwayFileManager { source, destination in
            source.path.hasPrefix(inside) != destination.path.hasPrefix(inside)
        }
        var outputs: [String] = []
        let pass = AppearanceRetryPass(udid: "UDID-1", found: .light, walkbookPath: bookPath, mayReboot: true, buildHash: "a1b2c3d4", fileManager: crossing, nonce: { "retry-nonce" }, renew: { _ in nil }, walk: { _, output, _ in
            outputs.append(output)
            try FileManager.default.copyItem(at: retry.url, to: URL(fileURLWithPath: output))
        })

        let outcome = try #require(pass.perform(after: first, of: book, run: Self.settlingDevice(), now: { Date(timeIntervalSince1970: 0) }))

        #expect(outcome.report == .folded(runnerFailure: nil))
        let folded = try CaptureBundle.read(at: first.url)
        #expect(folded.manifest.screens.first?.captures.map(\.state.theme) == [.light, .dark])
        #expect(folded.manifest.screens.last?.captures.map(\.state.theme) == [.light])
        let scratch = try #require(outputs.first)
        #expect(scratch.hasPrefix(inside))
        #expect(!FileManager.default.fileExists(atPath: scratch))
    }

    /// A fold the pass refuses for its content — the second attempt recorded `browse` as well as `progress`, so it kept more than it was sent for — removes its scratch bundle too, once the refusal is written into the first attempt's manifest.
    ///
    /// Scratch removal was only checked on the successful fold above; `keepsScratch` stays false on this branch, and a mutant setting it `true` in the plain `retryFailed` branch of `secondPass` would leave the directory this asserts is gone.
    @Test
    func afoldRefusedForItsContentWithItsRecordWrittenRemovesTheScratchBundle() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.refusingDark(in: directory)
        let retry = try Self.drewBoth(in: retryDirectory, nonce: "retry-nonce")
        let bookPath = try Self.lightAndDarkWalkbook(in: directory)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: bookPath))
        var outputs: [String] = []
        let pass = AppearanceRetryPass(udid: "UDID-1", found: .light, walkbookPath: bookPath, mayReboot: true, buildHash: "a1b2c3d4", nonce: { "retry-nonce" }, renew: { _ in nil }, walk: { _, output, _ in
            outputs.append(output)
            try FileManager.default.copyItem(at: retry.url, to: URL(fileURLWithPath: output))
        })

        let outcome = try #require(pass.perform(after: first, of: book, run: Self.settlingDevice(), now: { Date(timeIntervalSince1970: 0) }))

        guard case .retryFailed(_, keptAt: nil) = outcome.report else {
            Issue.record("a fold refused for its content, recorded, must answer as a retry not folded in with nothing kept, got \(outcome.report)")
            return
        }
        let scratch = try #require(outputs.first)

        #expect(!FileManager.default.fileExists(atPath: scratch))
    }

    /// And a second runner that leaves no readable bundle at all — nothing that could even be judged a fold candidate — removes its scratch bundle the same way: `keepsScratch` stays false on this branch too, the same mutant would leave this directory behind, and this asserts it does not.
    @Test
    func asecondRunnerThatLeftNoBundleRemovesTheScratchBundle() throws {
        let directory = try TemporaryDirectory()
        let first = try Self.refusingDark(in: directory)
        let bookPath = try Self.lightAndDarkWalkbook(in: directory)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: bookPath))
        var outputs: [String] = []
        let pass = AppearanceRetryPass(udid: "UDID-1", found: .light, walkbookPath: bookPath, mayReboot: true, buildHash: "a1b2c3d4", renew: { _ in nil }, walk: { _, output, _ in
            outputs.append(output)
            try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        })

        let outcome = try #require(pass.perform(after: first, of: book, run: Self.settlingDevice(), now: { Date(timeIntervalSince1970: 0) }))

        guard case .runnerLeftNothing = outcome.report else {
            Issue.record("a second runner that left no bundle must answer as one, with nothing kept, got \(outcome.report)")
            return
        }
        let scratch = try #require(outputs.first)

        #expect(!FileManager.default.fileExists(atPath: scratch))
    }

    /// The pass over a second runner whose `progress` light audit timed out, its moves going through `fileManager`.
    ///
    /// SimWalk#195: the timed-out audits ride out of `secondPass` on every return that read its bundle. Through a whole walk `.folded` is redundant (the walk re-reads the folded bundle), so each is asserted on the pass's `retryTimeouts` directly.
    private func passOverATimedOutRetry(fileManager: (_ first: CaptureBundle) -> FileManager, sourceLocation: SourceLocation = #_sourceLocation) throws -> AppearanceRetryPass.Outcome {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.refusingDark(in: directory)
        let retry = try CaptureBundleFixture.writeWalk(in: retryDirectory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "progress", captures: [
                CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen(), appleAudit: TestManagerRestartTests.timedOut),
                CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .dark), tree: CaptureBundleFixture.plainScreen()),
            ]),
        ], nonce: "retry-nonce")
        let bookPath = try Self.lightAndDarkWalkbook(in: directory)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: bookPath))
        var outputs: [String] = []
        defer {
            for output in outputs {
                try? FileManager.default.removeItem(atPath: output)
            }
        }
        let pass = AppearanceRetryPass(udid: "UDID-1", found: .light, walkbookPath: bookPath, mayReboot: true, buildHash: "a1b2c3d4", fileManager: fileManager(first), nonce: { "retry-nonce" }, renew: { _ in nil }, walk: { _, output, _ in
            outputs.append(output)
            try FileManager.default.copyItem(at: retry.url, to: URL(fileURLWithPath: output))
        })
        return try #require(pass.perform(after: first, of: book, run: Self.settlingDevice(), now: { Date(timeIntervalSince1970: 0) }), sourceLocation: sourceLocation)
    }

    /// The one timed-out audit the retry bundle records, named by screen, state and Apple's own sentence.
    private static let progressLightTimedOut = ["progress light: Audit failed to complete in time"]

    private static func named(_ timeouts: [AppleAuditScan.Failure]) -> [String] {
        timeouts.map { "\($0.screenID) \($0.stateSlug): \($0.reason)" }
    }

    @Test
    func aFoldedRetryAnswersTheTimedOutAuditsItsSecondRunnerRecorded() throws {
        let outcome = try passOverATimedOutRetry { _ in .default }

        guard case .folded = outcome.report else {
            Issue.record("a retry whose fold held must be answered as folded, got \(outcome.report)")
            return
        }

        #expect(Self.named(outcome.retryTimeouts) == Self.progressLightTimedOut)
    }

    @Test
    func aFoldThatCouldNotBeUndoneAnswersTheTimedOutAuditsItsSecondRunnerRecorded() throws {
        let failing = FailingMoves.fileManager { source, _ in source.path.contains("/simwalk-retry-") }
        let outcome = try passOverATimedOutRetry { _ in failing }

        guard case .foldNotUndone = outcome.report else {
            Issue.record("a fold that could not be undone must be answered as one, got \(outcome.report)")
            return
        }

        #expect(Self.named(outcome.retryTimeouts) == Self.progressLightTimedOut)
    }

    @Test
    func aRetryKeptAtItsScratchBundleAnswersTheTimedOutAuditsItsSecondRunnerRecorded() throws {
        let outcome = try passOverATimedOutRetry { first in
            let progress = CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.screenDirectory(screenID: "progress"), in: first.url).path
            return FailingMoves.partwayFileManager { source, _ in source.path == progress }
        }

        guard case let .retryFailed(_, keptAt) = outcome.report, keptAt != nil else {
            Issue.record("a fold undone whose record could not be written must be answered with the scratch bundle kept, got \(outcome.report)")
            return
        }

        #expect(Self.named(outcome.retryTimeouts) == Self.progressLightTimedOut)
    }

    /// And the second guard: a fold undone, whose record over the first attempt could not be written after it, keeps the scratch bundle — it holds what the fold set aside — and the answer says where.
    ///
    /// Here the move setting the first attempt's `progress` aside fails partway, as a copy and a delete between volumes does: the set-aside holds a whole copy, the bundle has lost a file of it, the move was never recorded, and the manifest put back names an artefact that is gone — so the record is refused. Removing the scratch bundle then would delete the only whole copy.
    @Test
    func afoldUndoneWhoseRecordCouldNotBeWrittenKeepsTheScratchBundleAndSaysWhere() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.refusingDark(in: directory)
        let retry = try Self.progressAgain(in: retryDirectory, refusingDark: false, nonce: "retry-nonce")
        let bookPath = try Self.lightAndDarkWalkbook(in: directory)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: bookPath))
        let progress = CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.screenDirectory(screenID: "progress"), in: first.url).path
        let failing = FailingMoves.partwayFileManager { source, _ in source.path == progress }
        var outputs: [String] = []
        let pass = AppearanceRetryPass(udid: "UDID-1", found: .light, walkbookPath: bookPath, mayReboot: true, buildHash: "a1b2c3d4", fileManager: failing, nonce: { "retry-nonce" }, renew: { _ in nil }, walk: { _, output, _ in
            outputs.append(output)
            try FileManager.default.copyItem(at: retry.url, to: URL(fileURLWithPath: output))
        })

        let outcome = try #require(pass.perform(after: first, of: book, run: Self.settlingDevice(), now: { Date(timeIntervalSince1970: 0) }))

        let scratch = try URL(fileURLWithPath: #require(outputs.first))
        let setAside = CaptureBundleLayout.setAsideDirectory(in: scratch)
        guard case let .retryFailed(_, keptAt) = outcome.report else {
            Issue.record("a fold undone whose record could not be written must be answered as a retry not folded in, got \(outcome.report)")
            return
        }

        #expect(keptAt == scratch.path)
        let light = try #require(first.manifest.screens.first?.captures.first)
        #expect(FileManager.default.fileExists(atPath: CaptureBundleLayout.url(forRelativePath: light.screenshotPath, in: setAside).path))
        #expect(FileManager.default.fileExists(atPath: CaptureBundleLayout.url(forRelativePath: light.axTreePath, in: setAside).path))
        #expect(outcome.report.notes(udid: "UDID-1", recorded: false).contains { $0.contains("kept at \(scratch.path)") })
    }

    /// #51.3b: `secondPass` must check the second bundle back against the exact nonce it handed the runner — every other test here fixes `nonce` to one constant string, so a check pointed at any other value that is itself just as consistent would still match by accident. A generator that returns a fresh value each call is the only way to catch that: the bundle is staged with whatever nonce the runner was actually handed, so a check that (wrongly) called `nonce()` again for a second, different value would refuse the fold this pins as succeeding.
    @Test
    func thefoldChecksTheBundleAgainstTheExactNonceTheRunnerWasHanded() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let first = try Self.refusingDark(in: directory)
        let bookPath = try Self.lightAndDarkWalkbook(in: directory)
        let book = try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: bookPath))
        var callCount = 0
        let nonces: () -> String = {
            callCount += 1
            return "retry-nonce-\(callCount)"
        }
        let pass = AppearanceRetryPass(udid: "UDID-1", found: .light, walkbookPath: bookPath, mayReboot: true, buildHash: "a1b2c3d4", nonce: nonces, renew: { _ in nil }, walk: { _, output, deliveredNonce in
            let retry = try Self.progressAgain(in: retryDirectory, refusingDark: false, nonce: deliveredNonce)
            try FileManager.default.copyItem(at: retry.url, to: URL(fileURLWithPath: output))
        })

        let outcome = try #require(pass.perform(after: first, of: book, run: Self.settlingDevice(), now: { Date(timeIntervalSince1970: 0) }))

        #expect(outcome.report == .folded(runnerFailure: nil))
        #expect(callCount == 1)
    }

    /// The round-3 report's held item: a second runner whose bundle was read back finished — it resets the device before it finalises its manifest — whether or not its attempt could be folded in, so the reset it left is judged, not called inconclusive.
    ///
    /// The second attempt here recorded other screens than it was sent for, so the fold refuses it; the device reads dark after it, where the walk found it light.
    @Test
    func asecondRunnerWhoseBundleWasReadIsJudgedFinishedWhenItsAttemptIsNotFolded() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(
            appPath: Self.fakeApp(in: directory),
            runnerStatus: 0,
            writes: writes,
            retryWrites: Self.drewBoth(in: retryDirectory).url,
            appearanceAfterRetry: "dark"
        )
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(outcome.bundle.manifest.appearanceSettle?.secondPassFailure?.contains("the second attempt recorded [progress, browse]") == true)
        #expect(outcome.handback?.reset == .didNotHold(read: .dark))
        #expect(outcome.answer().verdict.line.contains("an appearance reset that did not hold"))
    }

    /// A second runner that exits non-zero and whose readable bundle the fold then refuses for its content used to lose the fold's own refusal — `secondPassFailure` recorded only the runner's exit (`runnerFailure ?? error`), the symptom, not the reason the screen could not be recovered.
    ///
    /// Here the runner also exits non-zero (`retryStatus: 65`) on top of the same content mismatch as above, and both belong in the record.
    @Test
    func asecondPassFailureNamesTheFoldsRefusalEvenWhenTheRunnerAlsoFailed() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(
            appPath: Self.fakeApp(in: directory),
            runnerStatus: 0,
            writes: writes,
            retryWrites: Self.drewBoth(in: retryDirectory).url,
            retryStatus: 65
        )
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let reason = try #require(outcome.bundle.manifest.appearanceSettle?.secondPassFailure)

        #expect(reason.contains("the second attempt recorded [progress, browse]"))
        #expect(reason.contains("the runner also failed"))
    }

    /// SimWalk#68: a second runner that dies with the app leaves no bundle and may have stopped before its last reset, so the host puts the device back to the appearance it was found in straight after it — ahead of the handback — and the answer names the pass's failure as the cause, where it used to read the device's dark as saying "nothing either way" about the first runner's resets.
    @Test
    func asecondRunnerThatLeftNothingIsFollowedByAPutBackFromTheHostNamedForItsFailure() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryStatus: 65, appearanceAfterRetry: "dark")
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let calls = script.calls.map(\.arguments)
        let secondRunner = try #require(calls.lastIndex { $0.contains("test-without-building") })
        let afterRunner = calls[(secondRunner + 1)...]
        let putBack = try #require(afterRunner.firstIndex(of: DeviceAppearance.setArguments(.light, udid: "UDID-1")))
        let handback = try #require(afterRunner.firstIndex { $0.contains("write") })
        let text = outcome.answer().text

        #expect(putBack < handback)
        #expect(outcome.handback?.reset == .held)
        #expect(text.contains("the second pass's runner failed and left nothing to read, so it may have stopped before its last reset; the host then put UDID-1 back and it read light"))
        #expect(!text.contains("says nothing either way about whether the resets held"))
    }

    /// The same put-back after a runner that exited 0 and left no bundle: the line says so, not that the runner failed.
    @Test
    func asecondRunnerThatExitedZeroAndLeftNothingIsNotSaidToHaveFailed() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryStatus: 0)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let text = outcome.answer().text

        #expect(text.contains("the second pass's runner exited 0 but left no bundle this walk could accept"))
        #expect(!text.contains("the second pass's runner failed"))
    }

    /// SimWalk#70: the second pass's runner is handed a result bundle path of its own, and a failure that left nothing to read is diagnosed from that bundle, as the first pass's is — where before it could only be reported by its exit.
    @Test
    func asecondRunnerThatFailedIsDiagnosedFromItsOwnResultBundle() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryStatus: 65, appearanceAfterRetry: "dark")
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let runners = script.calls.map(\.arguments).filter { $0.contains("test-without-building") }
        let paths = runners.compactMap { arguments in arguments.firstIndex(of: "-resultBundlePath").map { arguments[$0 + 1] } }
        let text = outcome.answer().text

        #expect(runners.count == 2)
        #expect(paths.count == 2)
        #expect(Set(paths).count == paths.count)
        let second = try #require(paths.last)
        #expect(text.contains("appearance settle: what the second pass's own result bundle says of its failure:\n  the runner's result bundle could not be read — the runner wrote no result bundle: \(second)"))
    }

    /// A second runner that exited 0 and left nothing did not fail, so no result bundle is read for it.
    @Test
    func asecondRunnerThatExitedZeroAndLeftNothingIsNotDiagnosed() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryStatus: 0)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let text = outcome.answer().text

        #expect(text.contains("the second pass's runner exited 0 but left no bundle this walk could accept"))
        #expect(!text.contains("result bundle says of its failure"))
        #expect(!text.contains("the runner's result bundle"))
    }

    /// The host's put-back after a second runner that left nothing does not read back as the found appearance, and nor does the handback's own: the reset is still judged on the first runner alone — `held` — and the answer does not say the resets are unknowable, nor claim a put-back.
    @Test
    func aPutBackThatDoesNotHoldStillJudgesTheResetOnTheFirstRunnerAlone() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryStatus: 65, appearanceAfterRetry: "dark", ignoringAppearanceWritesAfterRetry: true)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let text = outcome.answer().text

        #expect(outcome.handback?.reset == .held)
        #expect(!text.contains("says nothing either way about whether the resets held"))
        #expect(text.contains("the host could not put UDID-1 back to light afterwards"))
        #expect(!text.contains("the host then put"))
    }

    /// A walk whose bundle is left with no manifest is a refusal, and the refusal is the only answer a caller reads — so it carries the retry's line, and with it where the first attempt was set aside.
    @Test
    func arefusalCarriesWhereAFoldThatCouldNotBeUndoneLeftTheFirstAttempt() {
        let report = AppearanceRetryPass.Report.foldNotUndone(reason: "its manifest is set aside at /tmp/simwalk-retry-1.simwalk/first-attempt.simwalk")

        let thrown = #expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: nil, handback: Self.cleanHandback, appearanceRetry: report) {
                throw CaptureBundleError.manifestMissing(bundlePath: "walked.simwalk", expectedPath: "walked.simwalk/manifest.json")
            }
        }

        #expect(thrown?.description.contains("set aside at /tmp/simwalk-retry-1.simwalk/first-attempt.simwalk") == true)
    }

    /// The round-2 review's finding 4: `CaptureBundleError.bundleFromAnotherWalk`'s description is already a bulleted, multi-line list of problems — the handback's own notes go on their own line after it, never joined onto its last bullet with " — " as though they were another problem in that list.
    @Test
    func aMultiLineUnderlyingDescriptionPutsTheHandbackOnItsOwnLine() {
        let thrown = #expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: nil, handback: Self.cleanHandback) {
                throw CaptureBundleError.bundleFromAnotherWalk(path: "walked.simwalk", problems: ["it carries another walk's nonce"])
            }
        }

        let underlyingDescription = String(describing: CaptureBundleError.bundleFromAnotherWalk(path: "walked.simwalk", problems: ["it carries another walk's nonce"]))
        let expected = underlyingDescription + "\n" + Self.cleanHandback.notes.joined(separator: "\n")

        #expect(thrown?.description == expected)
        #expect(thrown?.description.contains("- it carries another walk's nonce — ") == false)
    }

    /// A single-line description keeps the inline " — " join it always had — only a multi-line one gets the handback on its own line.
    @Test
    func aSingleLineUnderlyingDescriptionStillJoinsTheHandbackInline() {
        let thrown = #expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: nil, handback: Self.cleanHandback) {
                throw CaptureBundleError.notABundle(path: "/nowhere.simwalk")
            }
        }

        let expected = (["no capture bundle at /nowhere.simwalk — expected a directory"] + Self.cleanHandback.notes).joined(separator: " — ")

        #expect(thrown?.description == expected)
    }

    /// The round-2 review's finding 3: a settle whose wait for the boot outlived its bound leaves a device that may be wedged, and the handback's calls go to it next — so each is bounded.
    ///
    /// The wedge ends as a handback that could not put the device back, the commands printed and the verdict qualified; never as a walk that hangs on a call nothing bounds.
    @Test
    func ahandbackAfterABootThatWedgedIsBoundedAndSaysWhatToRun() throws {
        let directory = try TemporaryDirectory()
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, wedging: true)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(timedScript: script.timedRun), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        #expect(script.unboundedAfterWedge.isEmpty)
        #expect(outcome.bundle.manifest.appearanceSettle?.settleFailure?.hasPrefix("waiting for it to finish booting") == true)
        let answer = outcome.answer()
        #expect(answer.verdict.line.contains("an appearance settle that did not complete"))
        #expect(answer.verdict.line.contains("a device appearance that could not be put back"))
        #expect(answer.text.contains("run: xcrun simctl boot UDID-1"))
        #expect(answer.text.contains("run: xcrun simctl ui UDID-1 appearance light"))
    }

    /// SimWalk#50: a runner that failed without a bundle is refused with what its result bundle says — the path, the activities before the failure, and where the hierarchy went — so nobody has to go looking for the `.xcresult`.
    @Test
    func arunnerFailureRefusalNamesTheResultBundleTheActivitiesAndTheExportedHierarchy() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let digest = RunnerActivityDigest(
            recentActivities: ["Tap \"Progress\" Button", "Find the Any (Element at index 1)"],
            failure: "Failed to get matching snapshot: No matches found for Element at index 1",
            earlierFailures: 0,
            triageAttachments: [RunnerActivityDigest.Attachment(name: "App UI hierarchy for com.example.probe", uuid: "0B60")]
        )
        let diagnosis = RunnerFailureDiagnosis.digested(
            resultBundlePath: "/builds/Logs/Test/simwalk-20260923T151200-0B602BE7.xcresult",
            digest: digest,
            hierarchy: .exported(["/builds/Logs/Test/simwalk-20260923T151200-0B602BE7-attachments/0B60.txt"])
        )

        #expect(throws: ExitCode.self) {
            try Self.command().run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) {
                try WalkCommand.outcome(
                    runnerFailure: Self.wedged,
                    handback: Self.cleanHandback,
                    diagnosingRunnerFailure: { diagnosis },
                    readingBundle: { throw CaptureBundleError.notABundle(path: "/nowhere.simwalk") }
                )
            }
        }

        let err = recorder.err.joined(separator: "\n")
        #expect(recorder.out.isEmpty)
        #expect(err.contains("result bundle: /builds/Logs/Test/simwalk-20260923T151200-0B602BE7.xcresult"))
        #expect(err.contains("the last 2 activities before the failure:\n    Tap \"Progress\" Button\n    Find the Any (Element at index 1)"))
        #expect(err.contains("failure: Failed to get matching snapshot: No matches found for Element at index 1"))
        #expect(err.contains("UI hierarchy at the failure, exported to: /builds/Logs/Test/simwalk-20260923T151200-0B602BE7-attachments/0B60.txt"))
    }

    /// A result bundle that is missing, or that `xcresulttool` could not read, is one line under the refusal and nothing else.
    @Test
    func anunreadableResultBundleIsOneLineUnderTheRefusal() throws {
        let diagnosis = RunnerFailureDiagnosis.unreadable(resultBundlePath: "/builds/x.xcresult", reason: "the runner wrote no result bundle")

        let bare = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: Self.wedged, handback: Self.cleanHandback) {
                throw CaptureBundleError.notABundle(path: "/nowhere.simwalk")
            }
        })
        let diagnosed = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(
                runnerFailure: Self.wedged,
                handback: Self.cleanHandback,
                diagnosingRunnerFailure: { diagnosis },
                readingBundle: { throw CaptureBundleError.notABundle(path: "/nowhere.simwalk") }
            )
        })

        #expect(diagnosed.description == bare.description + "\n  the runner's result bundle could not be read — the runner wrote no result bundle: /builds/x.xcresult")
    }

    /// A walk that answered with a bundle, or a refusal the runner did not cause, never reads the result bundle: a run that worked prints nothing new.
    @Test
    func theResultBundleIsReadOnlyWhenTheRunnersFailureIsTheRefusal() throws {
        var asked = 0
        let diagnose: () -> RunnerFailureDiagnosis? = {
            asked += 1
            return .nothingToShow(resultBundlePath: "/builds/x.xcresult")
        }
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory)

        let survived = try WalkCommand.outcome(runnerFailure: Self.wedged, handback: Self.cleanHandback, diagnosingRunnerFailure: diagnose) { bundle }
        let notTheRunner = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try WalkCommand.outcome(runnerFailure: nil, handback: Self.cleanHandback, diagnosingRunnerFailure: diagnose) {
                throw CaptureBundleError.notABundle(path: "/nowhere.simwalk")
            }
        })

        #expect(asked == 0)
        #expect(survived.survivedRunnerFailure != nil)
        #expect(notTheRunner.runnerDiagnosis.isEmpty)
    }

    /// A device named by UDID that another caller has leased is refused naming the holder, and nothing past `simctl list` has run — no boot, no install, no appearance read (Brief §2.4).
    @Test
    func aleasedDeviceNamedWithoutItsTokenIsRefusedBeforeAnythingTouchesIt() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let lease = try leases.acquire(udid: "UDID-1", ttl: 3600, holderPID: 41, now: Date(timeIntervalSince1970: 0))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--device", "UDID-1"])

        #expect(throws: LeaseError.held(udid: "UDID-1", holderPID: 41, expiresAt: lease.expiresAt)) {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        }
        #expect(!script.calls.isEmpty)
        #expect(script.calls.filter { $0.arguments != ["--find", "simctl"] }.allSatisfy { $0.arguments.starts(with: ["simctl", "list"]) })
    }

    /// SimWalk#136: every `simctl` call a walk makes — setup, settle, reboot, handback — reaches the shell bounded, so none can sit behind a stalled `xcrun` forever.
    ///
    /// Seen where `Shell.run` has applied the per-verb bound and handed the call to its script: a bound dropped from the walk's own calls arrives here as `nil`.
    @Test
    func everySimctlCallAWalkMakesIsBounded() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", writes.to.path, "--device", "UDID-1"])
        var seen: [(arguments: [String], timeout: TimeInterval?)] = []
        let shell = Shell(timedScript: { executable, arguments, environment, timeout in
            seen.append((arguments, timeout))
            return try script.run(executable, arguments, environment)
        })

        _ = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let simctl = seen.filter { $0.arguments.first == "simctl" }

        #expect(simctl.contains { $0.arguments.starts(with: ["simctl", "boot"]) })
        #expect(simctl.contains { $0.arguments.starts(with: ["simctl", "status_bar"]) })
        #expect(simctl.contains { $0.arguments.starts(with: ["simctl", "privacy"]) })
        #expect(simctl.filter { $0.timeout == nil }.map(\.arguments).isEmpty)
    }

    /// SimWalk#136: a `simctl` call that outlives its bound refuses the walk naming that command, and the walk's claim on the device is released.
    ///
    /// The install is the stalled call: an appearance read that times out is deliberately no refusal (SimWalk#32), it leaves the appearance unknown.
    @Test
    func aSimctlCallThatOutlivesItsBoundRefusesTheWalkNamingItAndReleasesTheDevice() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--device", "UDID-1", "--app-path", Self.fakeApp(in: directory)])
        var stalled = ""
        let shell = Shell { executable, arguments, environment in
            if arguments.starts(with: ["simctl", "install"]) {
                stalled = (["xcrun"] + arguments).joined(separator: " ")
                throw ShellError.timedOut(command: stalled, seconds: 300)
            }
            return try script.run(executable, arguments, environment)
        }
        var refusal: (any Error)?

        do {
            _ = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        } catch {
            refusal = error
        }

        #expect(stalled.hasPrefix("xcrun simctl install UDID-1"))
        #expect(refusal as? ShellError == .timedOut(command: stalled, seconds: 300))
        #expect(WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).isEmpty)
        #expect(leases.all().isEmpty)
    }

    /// SimWalk#182: a serial walk interrupted during its runner gives back its lease and its claim on the device before the cancel returns, since the signal then ends the process without reaching the walk's own release.
    ///
    /// Read at the cancel, not after the walk: here the walk carries on once the cancel returns, and its own release would hide a cancel that gave nothing back.
    @Test
    func anInterruptionDuringASerialWalksRunnerReleasesItsLeaseAndClaimBeforeTheCancelReturns() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let interruption = Cancellation()
        var heldBeforeCancel: (leased: [String], claimed: Set<String>)?
        var heldAtCancel: (leased: [String], claimed: Set<String>)?
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building"), heldAtCancel == nil {
                heldBeforeCancel = (leases.all().map(\.udid), WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive))
                interruption.cancel()
                heldAtCancel = (leases.all().map(\.udid), WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive))
            }
            return try script.run(executable, arguments, environment)
        }

        // The cancel is raised on the walk's own thread, which cannot hand the device back while it waits, so the interruption waits for no handback (SimWalk#187; `HandbackGateTests` raises it from another).
        _ = try? command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases, interruption: interruption, handbackBound: 0, interruptionNote: { _ in })

        let before = try #require(heldBeforeCancel)
        let atCancel = try #require(heldAtCancel)

        #expect(before.leased == ["UDID-1"])
        #expect(before.claimed == ["UDID-1"])
        #expect(atCancel.leased.isEmpty)
        #expect(atCancel.claimed.isEmpty)
    }

    /// SimWalk#187: a walk interrupted while `prepare` builds its runner gives back its lease and its claim on the device before the cancel returns, since the signal then ends the process before the walk's own release is registered.
    ///
    /// Read at the cancel, not after the walk: here the walk carries on once the cancel returns, and its own release would hide a cancel that gave nothing back.
    @Test
    func anInterruptionDuringPrepareReleasesTheLeaseAndClaimBeforeTheCancelReturns() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let interruption = Cancellation()
        var heldBeforeCancel: (leased: [String], claimed: Set<String>)?
        var heldAtCancel: (leased: [String], claimed: Set<String>)?
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("build-for-testing"), heldAtCancel == nil {
                heldBeforeCancel = (leases.all().map(\.udid), WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive))
                interruption.cancel()
                heldAtCancel = (leases.all().map(\.udid), WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive))
            }
            return try script.run(executable, arguments, environment)
        }

        _ = try? command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases, interruption: interruption)

        let before = try #require(heldBeforeCancel)
        let atCancel = try #require(heldAtCancel)

        #expect(before.leased == ["UDID-1"])
        #expect(before.claimed == ["UDID-1"])
        #expect(atCancel.leased.isEmpty)
        #expect(atCancel.claimed.isEmpty)
    }

    /// SimWalk#187: a serial walk's runner runs on a shell the interruption's stop reaches, so an interruption landing once the runner is built leaves no runner driving the device after the lease and claim are given back.
    ///
    /// A scripted child cannot be ended mid-run, so this pins what puts the runner in the stop's reach: a launch after the stop is refused, as a running child registered with it is stopped (``ChildStopTests``). Before the fix the runner launched on a device no longer held.
    @Test
    func anInterruptionDuringASerialWalkReachesItsRunnerSoNoneLaunchesOnADeviceNoLongerHeld() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let interruption = Cancellation()
        let childStop = ChildStop()
        var built = false
        var heldAtCancel: (leased: [String], claimed: Set<String>)?
        var runnerLaunched = false
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                runnerLaunched = true
            } else if built, heldAtCancel == nil {
                interruption.cancel()
                heldAtCancel = (leases.all().map(\.udid), WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive))
            }
            built = built || arguments.contains("build-for-testing")
            return try script.run(executable, arguments, environment)
        }

        // Raised on the walk's own thread, so the interruption waits for no handback, as above.
        _ = try? command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases, interruption: interruption, childStop: childStop, handbackBound: 0, interruptionNote: { _ in })

        let atCancel = try #require(heldAtCancel)

        #expect(childStop.isStopped)
        #expect(!runnerLaunched)
        #expect(atCancel.leased.isEmpty)
        #expect(atCancel.claimed.isEmpty)
    }

    /// SimWalk#136: the appearance read before the runner, stalled behind `xcodebuild -runFirstLaunch`, refuses the walk naming the cause and the fix, before the runner runs, and releases the device.
    @Test
    func anAppearanceReadStalledOnFirstLaunchRefusesTheWalkNamingTheCause() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let stall = ShellError.stalledOnFirstLaunch(command: "xcrun simctl ui UDID-1 appearance", seconds: 10)
        let (refusal, script) = try Self.walk(in: directory, leases: leases, appearanceReadThrows: stall)

        #expect(refusal as? ShellError == stall)
        #expect(refusal.map { String(describing: $0) }?.contains("run `sudo xcodebuild -runFirstLaunch` (or open Xcode once), then retry") == true)
        #expect(!script.calls.contains { $0.arguments.contains("test-without-building") })
        #expect(leases.all().isEmpty)
    }

    /// SimWalk#32, kept by SimWalk#136: the same read timing out with nothing to say why is no refusal — the walk goes on to the runner with the appearance unknown.
    @Test
    func anAppearanceReadThatTimesOutIsStillNoRefusal() throws {
        let directory = try TemporaryDirectory()
        let timeout = ShellError.timedOut(command: "xcrun simctl ui UDID-1 appearance", seconds: 10)
        let (refusal, script) = try Self.walk(in: directory, leases: Self.leases(in: directory), appearanceReadThrows: timeout)

        #expect(refusal as? ShellError == nil)
        #expect(script.calls.contains { $0.arguments.contains("test-without-building") })
    }

    /// A walk of an owned device whose every appearance read throws `error`, answering what it was refused with, if anything, and the script it ran against.
    private static func walk(in directory: TemporaryDirectory, leases: LeaseStore, appearanceReadThrows error: ShellError) throws -> (refusal: (any Error)?, script: WalkScript) {
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--device", "UDID-1"])
        let shell = Shell { executable, arguments, environment in
            if arguments == DeviceAppearance.readArguments(udid: "UDID-1") {
                throw error
            }
            return try script.run(executable, arguments, environment)
        }
        do {
            _ = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        } catch {
            return (error, script)
        }
        return (nil, script)
    }

    /// A walkbook's setup: every change it can make, so each test sees every vector.
    static var setupJSON: String {
        #""setup":{"privacy":{"grant":["location"]},"statusBar":"clean","increaseContrast":true},"#
    }

    /// A settle reboots the device, and a `simctl status_bar` override does not survive a reboot: the walk sets it again between the boot and the second pass, and hands the whole setup back after the last runner.
    @Test
    func aSetupStatusBarIsMadeAgainAfterTheSettleRebootsTheDevice() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", writes.to.path, "--device", "UDID-1"])

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))

        let calls = script.calls.map(\.arguments)
        let runners = calls.indices.filter { calls[$0].contains("test-without-building") }
        let override = DeviceSetup.statusBarArguments(udid: "UDID-1")
        let overrides = calls.indices.filter { calls[$0] == override }
        let boot = try #require(calls.firstIndex(of: ["simctl", "boot", "UDID-1"]))
        let clear = try #require(calls.firstIndex(of: ["simctl", "status_bar", "UDID-1", "clear"]))
        #expect(runners.count == 2)
        try #require(overrides.count == 2)
        #expect(try #require(overrides.first) < runners[0])
        #expect(boot < overrides[1] && overrides[1] < runners[1])
        #expect(runners[1] < clear)
        #expect(try #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "grant", "location", "com.example.probe"])) < runners[0])
        #expect(try #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "reset", "location", "com.example.probe"])) > runners[1])
        #expect(script.increaseContrast == "disabled")
        #expect(outcome.handback?.appearance == .restored(.light))
        let record = try #require(try CaptureBundle.read(at: writes.to).manifest.deviceSetup)
        #expect(record.made.first == "privacy grant location")
        #expect(record.statusBarNotReapplied == nil)
        #expect(record.notHandedBack.isEmpty)
        #expect(record.handedBack == ["status bar override cleared, read back clear", "Increase Contrast put back disabled, read back"])
        #expect(outcome.answer().text.contains("setup: privacy grant location; status bar clean"))
        // SimWalk#63: nothing reads a privacy reset back, so the grant's handback qualifies the walk, and its record is gone once handed back.
        #expect(outcome.setup?.qualifications == ["a setup change handed back but not confirmed as found"])
        #expect(outcome.isQualified)
        #expect(DeviceSetupJournal.beside(Self.leases(in: directory)).entry(onDevice: "UDID-1") == nil)
    }

    /// SimWalk#72: a setup record a killed walk left is handed back before this walk's first change, for its own app, and this walk's answer and manifest say whose it was; while this walk's runner runs, the record on disk is this walk's own.
    @Test
    func aKilledWalksSetupRecordIsHandedBackBeforeThisWalksSetupAndSaid() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", writes.to.path, "--device", "UDID-1"])
        let leases = Self.leases(in: directory)
        let journal = DeviceSetupJournal.beside(leases)
        try Self.plantSetupRecord(#"{"udid":"UDID-1","bundleID":"killed.id","pid":2147483647,"token":"killed","applied":{"privacy":[{"action":"grant","service":"photos"}],"statusBar":false,"statusBarFound":[]}}"#, in: journal)
        var duringRunner: DeviceSetupJournal.Entry?
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building"), duringRunner == nil {
                duringRunner = journal.entry(onDevice: "UDID-1")
            }
            return try script.run(executable, arguments, environment)
        }

        let outcome = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        let calls = script.calls.map(\.arguments)
        let leftoverReset = try #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "reset", "photos", "killed.id"]))
        #expect(try leftoverReset < #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "grant", "location", "com.example.probe"])))
        #expect(duringRunner?.bundleID == "com.example.probe")
        #expect(duringRunner?.token != "killed")
        #expect(duringRunner?.applied.increaseContrastFound == "disabled")
        #expect(outcome.setup?.qualifications.first == "a setup an earlier walk left on the device, handed back before this one's")
        #expect(outcome.isQualified)
        let record = try #require(try CaptureBundle.read(at: writes.to).manifest.deviceSetup)
        #expect(record.leftover?.first?.hasPrefix("⚠ setup leftover: pid 2147483647 (no longer running) made privacy grant photos for killed.id") == true)
        #expect(outcome.answer().text.contains("⚠ setup leftover: pid 2147483647"))
        #expect(journal.entry(onDevice: "UDID-1") == nil)
    }

    /// SimWalk#72: a setup record whose walk still runs refuses this walk before any change, naming the pid, and is left exactly as it was.
    @Test
    func aSetupRecordOfAWalkStillRunningRefusesTheWalkBeforeAnyChange() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--device", "UDID-1"])
        let journal = DeviceSetupJournal.beside(Self.leases(in: directory))
        let running = #"{"udid":"UDID-1","bundleID":"other.id","pid":1,"token":"running","applied":{"privacy":[],"statusBar":true,"statusBarFound":[]}}"#
        try Self.plantSetupRecord(running, in: journal)

        #expect {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        } throws: { error in
            guard case let .leftoverRecord(_, reason, _)? = error as? DeviceSetupError else { return false }
            return reason.contains("pid 1, which is still running")
        }
        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "privacy"]) || $0.arguments.starts(with: ["simctl", "status_bar"]) })
        #expect(try String(contentsOf: journal.directory.appendingPathComponent("UDID-1.json"), encoding: .utf8) == running)
        #expect(Self.leases(in: directory).all().isEmpty)
    }

    /// SimWalk#73: a walk that makes no setup settles a killed walk's record too — handed back before its runner, removed, and said in the answer and the manifest — rather than capturing under the leftover unsaid.
    @Test
    func aWalkWithoutASetupHandsBackAKilledWalksSetupRecordBeforeItsRunner() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let leases = Self.leases(in: directory)
        let journal = DeviceSetupJournal.beside(leases)
        try Self.plantSetupRecord(#"{"udid":"UDID-1","bundleID":"killed.id","pid":2147483647,"token":"killed","applied":{"privacy":[{"action":"grant","service":"photos"}],"statusBar":false,"statusBarFound":[]}}"#, in: journal)

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        let calls = script.calls.map(\.arguments)
        let reset = try #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "reset", "photos", "killed.id"]))
        #expect(try reset < #require(calls.firstIndex { $0.contains("test-without-building") }))
        #expect(journal.entry(onDevice: "UDID-1") == nil)
        #expect(outcome.setup?.qualifications == ["a setup an earlier walk left on the device, handed back before this walk ran"])
        #expect(outcome.isQualified)
        let record = try #require(try CaptureBundle.read(at: writes.to).manifest.deviceSetup)
        #expect(record.made.isEmpty)
        #expect(record.leftover?.first?.hasPrefix("⚠ setup leftover: pid 2147483647 (no longer running) made privacy grant photos for killed.id and never handed it back; handed back before this walk ran") == true)
        #expect(outcome.answer().text.contains("⚠ setup leftover: pid 2147483647"))
    }

    /// SimWalk#73: a walk that makes no setup on a device it does not own — found booted, not named or leased — hands nothing back, since that changes device-wide state as a setup would; it leaves a gone walk's record where it is and captures qualified.
    @Test
    func aWalkWithoutASetupOnADeviceItDoesNotOwnLeavesAKilledWalksRecordAndQualifies() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path])
        let leases = Self.leases(in: directory)
        let journal = DeviceSetupJournal.beside(leases)
        let killed = #"{"udid":"UDID-1","bundleID":"killed.id","pid":2147483647,"token":"killed","applied":{"privacy":[{"action":"grant","service":"photos"}],"statusBar":false,"statusBarFound":[]}}"#
        try Self.plantSetupRecord(killed, in: journal)

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "privacy"]) })
        #expect(try String(contentsOf: journal.directory.appendingPathComponent("UDID-1.json"), encoding: .utf8) == killed)
        #expect(outcome.setup?.qualifications == ["the device carries a setup a gone walk left, not handed back"])
        #expect(outcome.isQualified)
    }

    /// SimWalk#73: a walk that makes no setup, over the record of a walk still running, neither refuses nor touches it — the device is that walk's until it hands back — but captures qualified, naming the pid.
    @Test
    func aWalkWithoutASetupOverARunningWalksSetupRecordLeavesItAndQualifies() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let leases = Self.leases(in: directory)
        let journal = DeviceSetupJournal.beside(leases)
        let running = #"{"udid":"UDID-1","bundleID":"other.id","pid":1,"token":"running","applied":{"privacy":[],"statusBar":true,"statusBarFound":[]}}"#
        try Self.plantSetupRecord(running, in: journal)

        let outcome = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "privacy"]) || $0.arguments.starts(with: ["simctl", "status_bar"]) })
        #expect(try String(contentsOf: journal.directory.appendingPathComponent("UDID-1.json"), encoding: .utf8) == running)
        #expect(outcome.setup?.qualifications == ["the device carries a setup pid 1 made, a walk still running"])
        #expect(outcome.isQualified)
        #expect(outcome.answer().text.contains("⚠ setup leftover: pid 1 (still running) made status bar clean"))
    }

    /// SimWalk#75: a walk that makes no setup hands a killed walk's record back only under a lease that still renews, as a setup is made only under one — a lapsed lease leaves the record where it is and says why, in the setup's words.
    @Test
    func aWalkWithoutASetupWhoseLeaseCannotBeRenewedLeavesAKilledWalksRecord() throws {
        let directory = try TemporaryDirectory()
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let leases = Self.leases(in: directory)
        let journal = DeviceSetupJournal.beside(leases)
        let killed = #"{"udid":"UDID-1","bundleID":"killed.id","pid":2147483647,"token":"killed","applied":{"privacy":[{"action":"grant","service":"photos"}],"statusBar":false,"statusBarFound":[]}}"#
        try Self.plantSetupRecord(killed, in: journal)
        let shell = Shell { executable, arguments, environment in
            if arguments.starts(with: ["simctl", "ui"]) {
                Self.dropEveryLease(in: leases)
            }
            return try script.run(executable, arguments, environment)
        }

        let outcome = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "privacy"]) })
        #expect(try String(contentsOf: journal.directory.appendingPathComponent("UDID-1.json"), encoding: .utf8) == killed)
        #expect(outcome.setupNotMade?.hasPrefix("the lease on UDID-1 could not be renewed: ") == true)
        #expect(outcome.answer().text.contains("the setup an earlier walk left was not handed back"))
        #expect(outcome.isQualified)
    }

    /// Writes `json` as the setup record another walk left on UDID-1.
    static func plantSetupRecord(_ json: String, in journal: DeviceSetupJournal) throws {
        try FileManager.default.createDirectory(at: journal.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: journal.directory.appendingPathComponent("UDID-1.json"))
    }

    /// A setup changes device-wide state, so a device the walk found booted and was not given by UDID or lease — which may be another session's — is refused before the boot, with nothing but the device list read.
    @Test
    func aSetupOnADeviceTheWalkDoesNotOwnIsRefusedBeforeAnythingChangesIt() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", directory.url.appendingPathComponent("out.simwalk").path])

        #expect(throws: DeviceSetupError.notOwned(udid: "UDID-1")) {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        }
        #expect(!script.calls.isEmpty)
        #expect(script.calls.filter { $0.arguments != ["--find", "simctl"] }.allSatisfy { $0.arguments.starts(with: ["simctl", "list"]) })
        #expect(Self.leases(in: directory).all().isEmpty)
    }

    /// A walk whose runner left no bundle is a refusal — and its setup was made all the same, so it is handed back all the same and the refusal says so.
    @Test
    func aRefusedWalkStillHandsBackItsSetup() throws {
        let directory = try TemporaryDirectory()
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 65)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--device", "UDID-1"])

        let refusal = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory))
        })

        let calls = script.calls.map(\.arguments)
        let runner = try #require(calls.firstIndex { $0.contains("test-without-building") })

        #expect(try #require(calls.firstIndex(of: ["simctl", "privacy", "UDID-1", "reset", "location", "com.example.probe"])) > runner)
        #expect(try #require(calls.firstIndex(of: ["simctl", "status_bar", "UDID-1", "clear"])) > runner)
        #expect(script.increaseContrast == "disabled")
        #expect(refusal.setup?.handback.failed.isEmpty == true)
        #expect(refusal.description.contains("setup handed back: location reset"))
        #expect(Self.leases(in: directory).all().isEmpty)
    }

    /// A walk that names no lease holds the device it resolved for as long as its runner runs — against every other simwalk session — and gives it back when the walk ends.
    @Test
    func awalkWithNoLeaseHoldsItsDeviceWhileTheRunnerRunsAndReleasesItAfter() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path])
        var heldDuringRunner: [String] = []
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                heldDuringRunner = leases.all().map(\.udid)
            }
            return try script.run(executable, arguments, environment)
        }

        _ = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(heldDuringRunner == ["UDID-1"])
        #expect(leases.all().isEmpty)
    }

    /// A walk under a `--lease` lease holds a claim on its device while the runner runs — which a handback honours whatever the token — and releases the claim, not the lease, when it ends (SimWalk#128).
    @Test
    func awalkUnderALeaseHoldsAClaimWhileTheRunnerRunsAndReleasesItAfter() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let lease = try leases.acquire(udid: "UDID-1", ttl: 3600, holderPID: getpid(), now: Date(timeIntervalSince1970: 0))
        let writes = try Self.runnerWrites(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", writes.to.path, "--lease", lease.token])
        var walkedDuringRunner: Set<String> = []
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                walkedDuringRunner = WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive)
            }
            return try script.run(executable, arguments, environment)
        }

        _ = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        #expect(walkedDuringRunner == ["UDID-1"])
        #expect(WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).isEmpty)
        #expect(try leases.lease(onDevice: "UDID-1") == lease)
    }

    /// A walk that is refused after it has taken its claim — here the runner's build fails — leaves none behind (SimWalk#128).
    @Test
    func aWalkRefusedAfterTakingItsClaimLeavesNoClaim() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path])
        var claimedBeforeRefusal = false
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("build-for-testing") {
                claimedBeforeRefusal = !WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).isEmpty
                return Shell.Result(status: 65, standardOutput: "", standardError: "** BUILD FAILED **")
            }
            return try script.run(executable, arguments, environment)
        }

        #expect(throws: (any Error).self) {
            try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        }

        #expect(claimedBeforeRefusal)
        #expect(WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).isEmpty)
        #expect(leases.all().isEmpty)
    }

    /// SimWalk#128: a walk whose claim cannot be written releases the lease it took, and runs nothing.
    @Test
    func aWalkWhoseClaimCannotBeWrittenReleasesTheLeaseItTook() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        let blocker = leases.directory.appendingPathComponent(".walks")
        try Data().write(to: blocker)
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--device", "UDID-1"])
        var ranRunner = false
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("build-for-testing") || arguments.contains("test-without-building") {
                ranRunner = true
            }
            return try script.run(executable, arguments, environment)
        }
        var storeFailedPath: String?

        do {
            _ = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        } catch let LeaseError.storeFailed(path, _) {
            storeFailedPath = path
        }

        #expect(storeFailedPath == leases.directory.path)
        #expect(!ranRunner)
        #expect(leases.all().isEmpty)
    }

    /// A `--lease` lease is renewed as the walk starts, and one that can no longer be renewed — its holder gone, so any session may reclaim the device — refuses the walk before anything past `simctl list` has run.
    @Test
    func awalkUnderALeaseThatCannotBeRenewedIsRefusedBeforeAnythingTouchesTheDevice() throws {
        let directory = try TemporaryDirectory()
        let leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in false })
        let lease = try leases.acquire(udid: "UDID-1", ttl: 3600, holderPID: 41, now: Date(timeIntervalSince1970: 0))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path, "--lease", lease.token])

        #expect(throws: LeaseError.holderExited(udid: "UDID-1", holderPID: 41)) {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        }
        #expect(!script.calls.isEmpty)
        #expect(script.calls.filter { $0.arguments != ["--find", "simctl"] }.allSatisfy { $0.arguments.starts(with: ["simctl", "list"]) })
        #expect(try leases.lease(onDevice: "UDID-1") == lease)
    }

    /// With nothing named, a leased device is not a candidate at all: a machine whose only device is leased refuses before any boot, rather than walking somebody else's device.
    @Test
    func awalkWithNoDeviceNamedRefusesWhenEveryDeviceIsLeased() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        _ = try leases.acquire(udid: "UDID-1", ttl: 3600, holderPID: 41, now: Date(timeIntervalSince1970: 0))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, booted: false)
        let command = try WalkCommand.parse([Self.walkbook(in: directory), "--output", directory.url.appendingPathComponent("out.simwalk").path])

        #expect(throws: LeaseError.noUnleasedDevice(runtime: "iOS")) {
            try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)
        }
        #expect(!script.calls.contains { $0.arguments.starts(with: ["simctl", "boot"]) })
        #expect(script.calls.filter { $0.arguments != ["--find", "simctl"] }.allSatisfy { $0.arguments.starts(with: ["simctl", "list"]) })
    }

    /// A walk whose lease is gone by the time its first runner has run — expired, reclaimed, released by `prune` — reboots nothing: the device may be another session's by then, so the settle is declined with the reason and the refusals stand.
    @Test
    func aWalkWhoseLeaseLapsedWhileTheRunnerRanRebootsNothing() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                Self.dropEveryLease(in: leases)
            }
            return try script.run(executable, arguments, environment)
        }

        let outcome = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        let calls = script.calls.map(\.arguments)
        let notRenewed: [String]? = if case let .leaseNotRenewed(screens, _, _) = outcome.appearanceRetry {
            screens
        } else {
            nil
        }

        #expect(!calls.contains { $0.starts(with: ["simctl", "shutdown"]) || $0.starts(with: ["simctl", "boot"]) })
        #expect(calls.filter { $0.contains("test-without-building") }.count == 1)
        #expect(notRenewed == ["progress"])
        #expect(outcome.bundle.manifest.appearanceSettle?.declined?.reason.contains("could not be renewed") == true)
        #expect(outcome.isQualified)
        #expect(leases.all().isEmpty)
    }

    /// A walk whose lease holds renews it before the settle reboots the device, so a walk that runs long does not settle a device its lease has stopped keeping others off.
    @Test
    func aWalkWhoseLeaseHoldsRenewsItBeforeTheSettle() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let leases = Self.leases(in: directory)
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        var expiries: [Date] = []
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") && expiries.isEmpty || arguments.starts(with: ["simctl", "shutdown"]) {
                expiries += leases.all().map(\.lease.expiresAt)
            }
            return try script.run(executable, arguments, environment)
        }

        let outcome = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        try #require(expiries.count == 2)

        #expect(expiries[0] < expiries[1])
        #expect(outcome.appearanceRetry == .folded(runnerFailure: nil))
        #expect(leases.all().isEmpty)
    }

    /// A lease that lapses while the settle reboots the device stops the walk there: the status bar is not made again and no second runner runs, and the manifest says why nothing was folded in.
    @Test
    func aWalkWhoseLeaseLapsedDuringTheSettleIsNotWalkedAgain() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let leases = Self.leases(in: directory)
        let writes = try (bundle: Self.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: Self.progressAgain(in: retryDirectory, refusingDark: false).url)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", writes.to.path, "--device", "UDID-1"])
        let shell = Shell { executable, arguments, environment in
            if arguments.starts(with: ["simctl", "boot"]) {
                Self.dropEveryLease(in: leases)
            }
            return try script.run(executable, arguments, environment)
        }

        let outcome = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        let calls = script.calls.map(\.arguments)
        let failure: String? = if case let .retryFailed(reason, nil) = outcome.appearanceRetry {
            reason
        } else {
            nil
        }

        #expect(calls.contains(["simctl", "boot", "UDID-1"]))
        #expect(calls.filter { $0.contains("test-without-building") }.count == 1)
        #expect(calls.filter { $0 == DeviceSetup.statusBarArguments(udid: "UDID-1") }.count == 1)
        #expect(failure?.contains("could not be renewed") == true)
        #expect(outcome.bundle.manifest.appearanceSettle?.secondPassFailure == failure)
        #expect(outcome.isQualified)
    }

    /// A lease that can no longer be renewed when the walk comes to its setup leaves the setup unmade — no grant, no status bar, no contrast — and the walk's answer qualified with why.
    @Test
    func aWalkWhoseLeaseCannotBeRenewedBeforeTheSetupMakesNoSetup() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let writes = try (bundle: Self.drewBoth(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkScript(appPath: Self.fakeApp(in: directory), runnerStatus: 0, writes: writes)
        let command = try WalkCommand.parse([Self.lightAndDarkWalkbook(in: directory, setup: true), "--output", writes.to.path, "--device", "UDID-1"])
        let shell = Shell { executable, arguments, environment in
            if arguments.starts(with: ["simctl", "ui"]) {
                Self.dropEveryLease(in: leases)
            }
            return try script.run(executable, arguments, environment)
        }

        let outcome = try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases)

        let calls = script.calls.map(\.arguments)

        #expect(!calls.contains { $0.starts(with: ["simctl", "privacy"]) || $0.starts(with: ["simctl", "status_bar"]) })
        #expect(!calls.contains { $0.count == 5 && $0[3] == "increase_contrast" })
        #expect(outcome.setup == nil)
        #expect(outcome.setupNotMade?.hasPrefix("the lease on UDID-1 could not be renewed: ") == true)
        #expect(outcome.answer().text.contains("the setup was not made"))
        #expect(outcome.isQualified)
    }

    /// SimWalk#78: a walk that makes no setup on a device it owns renews its lease only to hand a record back, so one with no record leaves the lease as it was — a renewal for nothing is a lease kept alive by a walk with nothing to do under it.
    @Test
    func anOwnedWalkWithoutASetupAndWithoutARecordDoesNotRenewItsLease() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let held = try leases.acquire(udid: "UDID-1", ttl: WalkLease.ttl, holderPID: getpid(), now: start)
        let lease = WalkLease(store: leases, udid: "UDID-1", token: held.token, taken: true)
        let journal = DeviceSetupJournal.beside(leases)
        let request = WalkCommand.SetupRequest(setup: nil, udid: "UDID-1", bundleID: "com.example.probe", owned: true)
        #expect(!journal.hasRecord(onDevice: "UDID-1"))

        let settled = try WalkCommand.makeSetup(request, lease: lease, now: start.addingTimeInterval(60), journal: journal, run: { _, arguments in
            Issue.record("no command should run: \(arguments)")
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })

        #expect(settled.made == nil)
        #expect(settled.notMade == nil)
        #expect(try leases.lease(onDevice: "UDID-1")?.expiresAt == held.expiresAt)
    }

    /// SimWalk#77: the walk's lease is gone before it settles a gone walk's record, so the leftover says the lease is why it stayed, not that the walk does not own the device — on the path of a walk without a setup.
    @Test
    func aWalkWithoutASetupWhoseLeaseIsGoneSaysTheLeaseNotOwnershipLeftAGoneWalksRecord() throws {
        let directory = try TemporaryDirectory()
        let planted = try Self.plantedRecordUnderADroppedLease(in: directory, pid: 2_147_483_647)
        let request = WalkCommand.SetupRequest(setup: nil, udid: "UDID-1", bundleID: "com.example.probe", owned: true)

        let settled = try WalkCommand.makeSetup(request, lease: planted.lease, now: planted.start.addingTimeInterval(60), journal: planted.journal, run: { _, arguments in
            Issue.record("no command should run: \(arguments)")
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })

        let line = settled.made?.leftover?.lines.first

        #expect(line?.contains("could not be renewed to hand it back") == true)
        #expect(line?.contains("does not own") == false)
        #expect(settled.notMade?.hasSuffix("the setup an earlier walk left was not handed back") == true)
        #expect(planted.journal.hasRecord(onDevice: "UDID-1"))
    }

    /// SimWalk#77: the same on the path of a walk with a setup, whose renewal fails before it changes anything.
    @Test
    func aWalkWithASetupWhoseLeaseIsGoneSaysTheLeaseNotOwnershipLeftAGoneWalksRecord() throws {
        let directory = try TemporaryDirectory()
        let planted = try Self.plantedRecordUnderADroppedLease(in: directory, pid: 2_147_483_647)
        let setup = Walkbook.Setup(privacy: Walkbook.Setup.Privacy(grant: ["photos"]))
        let request = WalkCommand.SetupRequest(setup: setup, udid: "UDID-1", bundleID: "com.example.probe", owned: true)

        let settled = try WalkCommand.makeSetup(request, lease: planted.lease, now: planted.start.addingTimeInterval(60), journal: planted.journal, run: { _, arguments in
            Issue.record("no command should run: \(arguments)")
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })

        let line = settled.made?.leftover?.lines.first

        #expect(line?.contains("could not be renewed to hand it back") == true)
        #expect(line?.contains("does not own") == false)
        #expect(settled.notMade?.hasSuffix("the setup was not made") == true)
        #expect(planted.journal.hasRecord(onDevice: "UDID-1"))
    }

    /// SimWalk#77: a record whose walk still runs is that walk's, lease or no lease, so the lapsed lease does not claim a handback it was never going to make.
    @Test
    func aLapsedLeaseIsNotBlamedForARunningWalksRecord() throws {
        let directory = try TemporaryDirectory()
        let planted = try Self.plantedRecordUnderADroppedLease(in: directory, pid: getppid())
        let request = WalkCommand.SetupRequest(setup: nil, udid: "UDID-1", bundleID: "com.example.probe", owned: true)

        let settled = try WalkCommand.makeSetup(request, lease: planted.lease, now: planted.start.addingTimeInterval(60), journal: planted.journal, run: { _, arguments in
            Issue.record("no command should run: \(arguments)")
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })

        #expect(settled.notMade?.hasPrefix("the lease on UDID-1 could not be renewed: ") == true)
        #expect(settled.notMade?.contains("not handed back") == false)
    }

    /// An owned lease on UDID-1 that is then dropped from the store, and a record another walk of `pid` left on the device: `pid` is a dead one or a live one, as the test needs.
    private static func plantedRecordUnderADroppedLease(in directory: TemporaryDirectory, pid: Int32) throws -> PlantedRecord {
        let leases = Self.leases(in: directory)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let held = try leases.acquire(udid: "UDID-1", ttl: WalkLease.ttl, holderPID: getpid(), now: start)
        let lease = WalkLease(store: leases, udid: "UDID-1", token: held.token, taken: true)
        let journal = DeviceSetupJournal.beside(leases)
        try plantSetupRecord(#"{"udid":"UDID-1","bundleID":"gone.id","pid":\#(pid),"token":"gone","applied":{"privacy":[{"action":"grant","service":"photos"}],"statusBar":false,"statusBarFound":[]}}"#, in: journal)
        dropEveryLease(in: leases)
        return PlantedRecord(lease: lease, journal: journal, start: start)
    }

    /// Takes every lease out of `leases` — what a lease that lapsed and was reclaimed, or was released by `prune`, looks like to the walk holding it.
    static func dropEveryLease(in leases: LeaseStore) {
        for entry in leases.all() {
            _ = try? leases.remove(udid: entry.udid, token: entry.lease.token)
        }
    }

    /// The leases these walks see — the test's own scratch store, with every holder alive, so a lease is held until it expires.
    static func leases(in directory: TemporaryDirectory) -> LeaseStore {
        LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
    }

    /// Where these walks build, and record that they did — scratch, never the machine's own `~/.simwalk`.
    static func builds(in directory: TemporaryDirectory) -> RunnerBuilds {
        RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
    }

    /// The runner these walks build: a snapshot paired with the binary, as an installed walk resolves one.
    static var runner: RunnerSource {
        RunnerSource(
            projectPath: "/Users/x/.simwalk/runner/snapshots/c0ffee/Runner/SimWalkRunner.xcodeproj",
            commit: "c0ffee0000000000000000000000000000000000",
            origin: .installed
        )
    }

    /// A bundle staged beside the walk, and the `--output` path — a different one — the scripted runner copies it to when it runs.
    static func runnerWrites(in directory: TemporaryDirectory) throws -> (bundle: URL, to: URL) {
        try (bundle(in: directory).url, directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
    }

    /// A device put back exactly as it was found.
    private static var cleanHandback: DeviceHandback {
        DeviceHandback(accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored), appearance: .restored(.light))
    }

    /// A device every settle command succeeds on, reading back whichever appearance was last set — for a pass driven without a whole walk.
    private static func settlingDevice() -> (String, [String], TimeInterval) throws -> Shell.Result {
        var appearance = "light"
        return { _, arguments, _ in
            if arguments.starts(with: ["simctl", "ui"]), arguments.count == 5 {
                appearance = arguments[4]
            }
            return Shell.Result(status: 0, standardOutput: "\(appearance)\n", standardError: "")
        }
    }

    /// A two-screen walkbook on disk — `progress` in light and dark, `browse` in light — returning its path.
    static func lightAndDarkWalkbook(in directory: TemporaryDirectory, setup: Bool = false) throws -> String {
        let url = directory.url.appendingPathComponent("book.json")
        let json = #"{"name":"probe","appBundleID":"com.example.probe","# + (setup ? Self.setupJSON : "") + #""screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"},{"theme":"dark"}]},{"id":"browse","route":[{"tab":{"label":"Browse"}}],"states":[{"theme":"light"}]}]}"#
        try Data(json.utf8).write(to: url)
        return url.path
    }

    /// The first pass on a device that reported `dark` and drew light: `progress` kept its light capture and refused its dark one, `browse` captured.
    static func refusingDark(in directory: TemporaryDirectory) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [
            progressScreen(refusingDark: true),
            CaptureBundleFixture.ScreenSpec(id: "browse", captures: [capture("browse", .light)]),
        ])
    }

    /// The first pass on a device found dark that drew light: `progress`'s two captures measured alike, and with the device found dark neither side could be kept — both refused on appearance; `browse` captured.
    private static func refusingBothOnADarkDevice(in directory: TemporaryDirectory) throws -> CaptureBundle {
        let both = [Walkbook.CaptureState(theme: .light), Walkbook.CaptureState(theme: .dark)]
        return try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light' (mean brightness 0.929 against 0.929), and the device's own appearance was dark before the walk"),
                refusedStates: both,
                refusedOnAppearance: both
            ),
            CaptureBundleFixture.ScreenSpec(id: "browse", captures: [capture("browse", .light)]),
        ])
    }

    /// The same walk on a device that drew what it reported: every state captured.
    private static func drewBoth(in directory: TemporaryDirectory, nonce: String? = nil) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [
            progressScreen(refusingDark: false),
            CaptureBundleFixture.ScreenSpec(id: "browse", captures: [capture("browse", .light)]),
        ], nonce: nonce)
    }

    /// The second pass, over `progress` alone — both states captured, or the dark one refused again.
    static func progressAgain(in directory: TemporaryDirectory, refusingDark: Bool, nonce: String? = nil) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [progressScreen(refusingDark: refusingDark)], nonce: nonce)
    }

    private static func progressScreen(refusingDark: Bool) -> CaptureBundleFixture.ScreenSpec {
        guard refusingDark else {
            return CaptureBundleFixture.ScreenSpec(id: "progress", captures: [capture("progress", .light), capture("progress", .dark)])
        }
        return CaptureBundleFixture.ScreenSpec(
            id: "progress",
            outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light' (mean brightness 0.929 against 0.929)"),
            captures: [capture("progress", .light)],
            refusedStates: [Walkbook.CaptureState(theme: .dark)],
            refusedOnAppearance: [Walkbook.CaptureState(theme: .dark)]
        )
    }

    private static func capture(_ screenID: String, _ theme: Walkbook.Theme) -> CaptureBundleFixture.Capture {
        CaptureBundleFixture.Capture(screenID: screenID, state: Walkbook.CaptureState(theme: theme), tree: CaptureBundleFixture.plainScreen())
    }

    /// A one-screen walkbook on disk, returning its path.
    static func walkbook(in directory: TemporaryDirectory) throws -> String {
        let url = directory.url.appendingPathComponent("book.json")
        let json = #"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
        try Data(json.utf8).write(to: url)
        return url.path
    }

    /// An installed app as far as `AppBuildIdentity` is concerned: an `Info.plist` naming an executable that is there.
    static func fakeApp(in directory: TemporaryDirectory) throws -> String {
        let url = directory.url.appendingPathComponent("Probe.app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": "Probe"], format: .xml, options: 0)
        try plist.write(to: url.appendingPathComponent("Info.plist"))
        try Data("binary".utf8).write(to: url.appendingPathComponent("Probe"))
        return url.path
    }

    /// The simulator's own pasteboard XPC, which is not this tool's to fix and is this tool's to survive.
    private static var wedged: RunnerError {
        RunnerError.walkFailed(reason: "browse-search: process main thread busy for 30.0s")
    }

    /// The summary is printed on every branch — the code is what a script gates on, not the absence of a report.
    private static func expectQualifiedExit(
        reporting outcome: WalkCommand.Outcome,
        in directory: TemporaryDirectory,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self, sourceLocation: sourceLocation) {
            try command().run(log: log(in: directory), emit: recorder.emit, emitError: recorder.emitError) { outcome }
        }, sourceLocation: sourceLocation)

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode), sourceLocation: sourceLocation)
        #expect(recorder.out.count == 1, sourceLocation: sourceLocation)
        #expect(recorder.err.isEmpty, sourceLocation: sourceLocation)
    }

    private static func bundle(
        in directory: TemporaryDirectory,
        unreachable: [String] = [],
        settled: Bool = true,
        hasContent: Bool = true,
        buildHash: String = "a1b2c3d4",
        nonce: String? = nil
    ) throws -> CaptureBundle {
        try CaptureBundleFixture.write(
            in: directory,
            captures: [
                CaptureBundleFixture.Capture(
                    screenID: "progress",
                    state: Walkbook.CaptureState(theme: .light),
                    tree: CaptureBundleFixture.plainScreen(),
                    settled: settled,
                    hasContent: hasContent
                ),
            ],
            unreachable: unreachable,
            buildHash: buildHash,
            nonce: nonce
        )
    }

    private static func command() throws -> WalkCommand {
        try WalkCommand.parse(["book.json", "--output", "example.simwalk"])
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }
}

extension WalkCommandTests {
    /// A lease on UDID-1 that was dropped from the store, and the record another walk left beside it.
    struct PlantedRecord {
        let lease: WalkLease
        let journal: DeviceSetupJournal
        let start: Date
    }

    /// Stands in for `simctl` and `xcodebuild` across a whole walk: one booted device, the app installed, a runner that exits with `runnerStatus`, a device that reads `light`, and an accessibility key the teardown has switched off.
    ///
    /// A second runner — the appearance retry's (SimWalk#26) — writes `retryWrites` wherever the walk pointed it, and every runner's walkbook is read as it runs, so a test can see which screens each pass was sent to walk.
    final class WalkScript {
        private(set) var calls: [(arguments: [String], environment: [String: String])] = []
        /// The screen ids of the walkbook each runner was handed, in the order the runners ran.
        private(set) var walkedScreens: [[String]] = []
        /// The output directory each runner was handed, in the order the runners ran — the second is the retry's scratch bundle.
        private(set) var outputs: [String] = []
        private var elapsed: TimeInterval = 0
        private var accessibility = "0"
        private var appearance: String
        /// What `simctl ui … increase_contrast` reads — `disabled`, as a fresh device has it, until something sets it.
        private(set) var increaseContrast = "disabled"
        private var statusBarOverridden = false
        private let appPath: String
        private let runnerStatus: Int32
        private let appearanceAfterRunner: String
        /// A bundle written ahead, and where the runner puts it when it runs — `nil` for a runner that writes nothing.
        private let writes: (bundle: URL, to: URL)?
        /// The bundle a second runner writes to the output it is handed — `nil` for one that writes nothing.
        private let retryWrites: URL?
        /// What a second runner exits with and leaves the appearance at — `nil` for the first runner's.
        private let retryStatus: Int32?
        private let appearanceAfterRetry: String?
        private let ignoringAppearanceWritesAfterRetry: Bool
        /// `simctl` subcommands that exit non-zero, as a device that will not do them does.
        private let failing: [String]
        /// Whether `simctl list` reports the device booted — somebody else's, as far as a walk can tell — or shut down, for this walk to boot.
        private let booted: Bool
        /// The device `simctl list` reports; a test of the override directory needs one named like a UUID, which that directory keys on.
        private let udid: String
        /// The `deviceTypeIdentifier` `simctl list` reports, `nil` as a device that reports none (SimWalk#219).
        private let deviceType: String?
        /// Whether the settle's wait for the boot wedges: it outlives its bound, and from then on every call to the device would hang — one made with a bound times out, one made without is recorded in `unboundedAfterWedge`.
        private let wedging: Bool
        private var wedged = false
        /// The calls made to the wedged device with no bound — each one a walk that would never have answered.
        ///
        /// Answered here as a failure, which the real device would never have given.
        private(set) var unboundedAfterWedge: [[String]] = []

        init(
            appPath: String,
            runnerStatus: Int32,
            appearance: String = "light",
            appearanceAfterRunner: String = "light",
            writes: (bundle: URL, to: URL)? = nil,
            retryWrites: URL? = nil,
            retryStatus: Int32? = nil,
            appearanceAfterRetry: String? = nil,
            ignoringAppearanceWritesAfterRetry: Bool = false,
            failing: [String] = [],
            booted: Bool = true,
            udid: String = "UDID-1",
            deviceType: String? = nil,
            wedging: Bool = false
        ) {
            self.udid = udid
            self.deviceType = deviceType
            self.booted = booted
            self.wedging = wedging
            self.appPath = appPath
            self.runnerStatus = runnerStatus
            self.appearance = appearance
            self.appearanceAfterRunner = appearanceAfterRunner
            self.writes = writes
            self.retryWrites = retryWrites
            self.retryStatus = retryStatus
            self.appearanceAfterRetry = appearanceAfterRetry
            self.ignoringAppearanceWritesAfterRetry = ignoringAppearanceWritesAfterRetry
            self.failing = failing
        }

        var run: (String, [String], [String: String]) throws -> Shell.Result {
            { [self] _, arguments, environment in
                calls.append((arguments, environment))
                elapsed += 0.2
                if arguments.first == "simctl", arguments.count > 1, failing.contains(arguments[1]) {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "An error was encountered processing the command (code=164)\n")
                }
                if arguments.contains("test-without-building") {
                    runnerWrites(environment)
                }
                return answer(arguments)
            }
        }

        /// `run`, told each call's bound — for `Shell(timedScript:)`, and the one place a wedge can be seen: after the settle's wait for the boot outlives its bound, a bounded call times out (taking its bound off the clock) and an unbounded one is recorded.
        var timedRun: (String, [String], [String: String], TimeInterval?) throws -> Shell.Result {
            { [self] executable, arguments, environment, timeout in
                let settling = calls.contains { $0.arguments.starts(with: ["simctl", "shutdown"]) }
                guard wedged || (wedging && settling && arguments.starts(with: ["simctl", "bootstatus"])) else {
                    return try run(executable, arguments, environment)
                }
                calls.append((arguments, environment))
                wedged = true
                guard let timeout else {
                    // The clock moves as for any call, so a walk that polls the wedged device unbounded still reaches
                    // its own deadlines — and fails on the record above, rather than looping on a clock that stood still.
                    elapsed += 0.2
                    unboundedAfterWedge.append(arguments)
                    return Shell.Result(status: 1, standardOutput: "", standardError: "wedged\n")
                }
                elapsed += timeout
                throw ShellError.timedOut(command: (["xcrun"] + arguments).joined(separator: " "), seconds: timeout)
            }
        }

        var now: () -> Date {
            { [self] in Date(timeIntervalSince1970: elapsed) }
        }

        /// What a runner leaves behind: the screens its walkbook named, and its bundle — the walk's own for the first runner, the retry's for a second, at the output it was handed.
        ///
        /// Every canned bundle it copies in is stamped with the build hash and nonce the driver actually passed in `environment` afterwards — what the real runner does by reading `TEST_RUNNER_SIMWALK_BUILD_HASH` and `TEST_RUNNER_SIMWALK_NONCE` back into the manifest it writes (SimWalk#41), and what lets a canned bundle staged before the nonce exists still read back as this run's own.
        private func runnerWrites(_ environment: [String: String]) {
            let book = environment["TEST_RUNNER_SIMWALK_WALKBOOK"].flatMap { try? WalkbookLoader.load(contentsOf: URL(fileURLWithPath: $0)) }
            walkedScreens.append(book?.screens.map(\.id) ?? [])
            let output = environment["TEST_RUNNER_SIMWALK_OUTPUT"] ?? ""
            outputs.append(output)
            let outputURL = URL(fileURLWithPath: output)
            if walkedScreens.count > 1 {
                if let retryWrites {
                    try? FileManager.default.copyItem(at: retryWrites, to: outputURL)
                    Self.stamp(bundleAt: outputURL, environment: environment)
                }
            } else if let writes {
                try? FileManager.default.copyItem(at: writes.bundle, to: writes.to)
                Self.stamp(bundleAt: writes.to, environment: environment)
            }
        }

        /// Overwrites a canned bundle's `appBuildHash` and `nonce` with whatever the driver actually passed this call, leaving every other field as the fixture wrote it — a JSON-object patch rather than a full manifest decode, so it never has to agree with `CaptureBundle`'s own date strategy.
        private static func stamp(bundleAt url: URL, environment: [String: String]) {
            let manifestURL = CaptureBundle.manifestURL(in: url)
            guard let data = try? Data(contentsOf: manifestURL),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            if let buildHash = environment["TEST_RUNNER_SIMWALK_BUILD_HASH"] {
                object["appBuildHash"] = buildHash
            }
            if let nonce = environment["TEST_RUNNER_SIMWALK_NONCE"] {
                object["nonce"] = nonce
            }
            guard let patched = try? JSONSerialization.data(withJSONObject: object) else { return }
            try? patched.write(to: manifestURL)
        }

        private func answer(_ arguments: [String]) -> Shell.Result {
            let typeField = deviceType.map { #","deviceTypeIdentifier":"\#($0)""# } ?? ""
            let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"\#(udid)","name":"iPhone 17 Pro","state":""# + (booted ? "Booted" : "Shutdown") + #""\#(typeField)}]}}"#
            let output: String
            var status: Int32 = 0
            switch arguments {
            case _ where arguments.starts(with: ["simctl", "list"]):
                output = devices
            case _ where arguments.starts(with: ["simctl", "get_app_container"]):
                output = appPath
            // Increase Contrast is its own setting: a walkbook's setup sets it with a five-argument `simctl ui` too, and
            // read as an appearance it would corrupt the one the walk found.
            case _ where arguments.starts(with: ["simctl", "ui"]) && arguments.count > 3 && arguments[3] == "increase_contrast":
                if arguments.count == 5 {
                    increaseContrast = arguments[4]
                }
                output = increaseContrast
            case _ where arguments.starts(with: ["simctl", "ui"]):
                if arguments.count == 5, arguments[3] == "appearance", !(ignoringAppearanceWritesAfterRetry && walkedScreens.count > 1) {
                    appearance = arguments[4]
                }
                output = appearance
            case _ where arguments.contains("test-without-building"):
                output = ""
                let isRetry = walkedScreens.count > 1
                status = isRetry ? retryStatus ?? runnerStatus : runnerStatus
                appearance = isRetry ? appearanceAfterRetry ?? appearanceAfterRunner : appearanceAfterRunner
            // The runner's own write, which is the only way a bundle gets to `--output` now that a walk
            // refuses one that is already there — done in `runnerWrites`, which has the environment this
            // needs to stamp the copy with (SimWalk#41).
            case _ where arguments.contains("-g") && arguments.last == "AppleLocale":
                output = "en_GB"
            case _ where arguments.contains("-g") && arguments.last == "AppleLanguages":
                output = "(\n    \"en-GB\"\n)"
            case _ where arguments.contains("write"):
                accessibility = "1"
                output = ""
            case _ where arguments.contains("read"):
                output = accessibility
            // The status bar listing as measured on iOS 27, which a setup reads before its override and after its clear (SimWalk#63).
            case _ where arguments.starts(with: ["simctl", "status_bar"]):
                statusBarOverridden = arguments[3] == "list" ? statusBarOverridden : arguments[3] == "override"
                output = "Current Status Bar Overrides:\n=============================" + (arguments[3] == "list" && statusBarOverridden ? "\nTime: 09:41" : "")
            default:
                output = ""
            }
            return Shell.Result(status: status, standardOutput: "\(output)\n", standardError: "")
        }
    }
}
