//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A runner that timed out launching the app is run once more when it wrote nothing (SimWalk#266).
struct LaunchTimeoutRetryTests {
    @Test
    func theLaunchTimeoutIsRecognisedInADigestAndInAStartFailure() {
        #expect(Self.digest(Self.timeoutText).isLaunchTimeout)
        #expect(Self.timeout("a").isLaunchTimeout)
        let both = RunnerFailureDiagnosis.failedBeforeTest(resultBundlePath: "a", failures: [RunnerFailureDiagnosis.StartFailure(testName: "x", failureText: "other"), RunnerFailureDiagnosis.StartFailure(testName: "t", failureText: Self.timeoutText)])
        #expect(both.isLaunchTimeout)
    }

    @Test
    func everyOtherFailureIsNotALaunchTimeout() {
        let refused = #"Failed to launch com.x: The request to open "com.x" failed. (Underlying Error: FBSApplicationLibrary returned nil)"#

        #expect(!Self.digest(refused).isLaunchTimeout)
        #expect(!Self.digest("Timed out attempting to launch app").isLaunchTimeout)
        #expect(!Self.digest("Failed to launch com.x").isLaunchTimeout)
        #expect(!RunnerFailureDiagnosis.nothingToShow(resultBundlePath: "a").isLaunchTimeout)
        #expect(!RunnerFailureDiagnosis.unreadable(resultBundlePath: "a", reason: Self.timeoutText).isLaunchTimeout)
        #expect(!RunnerFailureDiagnosis.failedBeforeTest(resultBundlePath: "a", failures: []).isLaunchTimeout)
    }

    @Test
    func aRunnerThatSucceedsRunsOnce() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        let recorder = Recorder()
        let result = run(output: output, failures: [], diagnosis: { Self.timeout($0) }, recorder: recorder)

        #expect(result.failure == nil)
        #expect(recorder.attempts == ["first"])
        #expect(recorder.diagnosed.isEmpty)
        #expect(result.note(writing: "bundle") == nil)
    }

    @Test
    func aTimeoutWithEmptyOutputRunsASecondRunnerAndSaysSo() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let recorder = Recorder()
        let result = run(output: output, failures: ["first"], diagnosis: { Self.timeout($0) }, recorder: recorder)

        #expect(result.failure == nil)
        #expect(recorder.attempts == ["first", "second"])
        #expect(result.resultBundlePath == "second")
        #expect(result.firstResultBundlePath == "first")
        #expect(result.note(writing: "bundle") == "the first runner timed out launching the app before it captured anything; a second runner wrote this bundle (first runner's result bundle: first)")
        #expect(result.note(writing: "report")?.contains("wrote this report") == true)
    }

    @Test
    func aSecondTimeoutIsTheFailureAndThereIsNoThirdRunner() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        let recorder = Recorder()
        let result = run(output: output, failures: ["first", "second"], diagnosis: { Self.timeout($0) }, recorder: recorder)

        #expect(result.failure != nil)
        #expect(recorder.attempts == ["first", "second"])
        #expect(result.resultBundlePath == "second")
        #expect(result.firstResultBundlePath == "first")
        #expect(result.diagnosis == Self.timeout("second"))
        #expect(result.note(writing: "bundle")?.contains("first runner's result bundle: first") == true)
    }

    @Test
    func anotherFailureIsNotRetried() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        let recorder = Recorder()
        let other = RunnerFailureDiagnosis.nothingToShow(resultBundlePath: "first")
        let result = run(output: output, failures: ["first"], diagnosis: { _ in other }, recorder: recorder)

        #expect(result.failure != nil)
        #expect(recorder.attempts == ["first"])
        #expect(result.diagnosis == other)
        #expect(result.firstResultBundlePath == nil)
        #expect(!result.notRetriedForOutput)
    }

    @Test
    func aTimeoutWithOutputAlreadyWrittenIsNotRetried() throws {
        let (directory, output) = try missingOutput()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data().write(to: output.appendingPathComponent("file"))
        _ = directory
        let recorder = Recorder()
        let result = run(output: output, failures: ["first"], diagnosis: { Self.timeout($0) }, recorder: recorder)

        #expect(recorder.attempts == ["first"])
        #expect(result.notRetriedForOutput)
        #expect(result.diagnosis == Self.timeout("first"))
        #expect(result.firstResultBundlePath == nil)
    }

    @Test
    func aStoppedRunReadsNothingAndIsNotRetried() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        let recorder = Recorder()
        let result = run(output: output, stopped: true, failures: ["first"], diagnosis: { Self.timeout($0) }, recorder: recorder)

        #expect(result.failure != nil)
        #expect(recorder.attempts == ["first"])
        #expect(recorder.diagnosed.isEmpty)
        #expect(result.diagnosis == nil)
    }

    /// SimWalk#298: a runner killed before it connected never started the test, so it is run once more and the answer says so.
    @Test
    func aRunnerKilledBeforeConnectingRunsASecondRunnerAndSaysSo() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        let recorder = Recorder()
        let result = run(output: output, failures: ["first"], diagnosis: { Self.killed($0) }, recorder: recorder)

        #expect(result.failure == nil)
        #expect(recorder.attempts == ["first", "second"])
        #expect(result.firstRunnerWasKilled)
        #expect(result.note(writing: "bundle") == "the first runner was killed before it connected to XCTest, so it captured nothing; a second runner wrote this bundle (first runner's result bundle: first)")
    }

    @Test
    func aSecondKillIsTheFailureAndSaysNoStepRan() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        let recorder = Recorder()
        let result = run(output: output, failures: ["first", "second"], diagnosis: { Self.killed($0) }, recorder: recorder)

        #expect(result.failure != nil)
        #expect(recorder.attempts == ["first", "second"])
        let lines = LaunchTimeoutRetry.diagnosisLines(diagnosis: result.diagnosis, retry: result, checkingLaunch: { _ in "never asked" })
        #expect(lines == [
            "the first runner was killed before it connected to XCTest (result bundle: first); what follows is the second runner's",
            "result bundle: second",
            "failure: Test crashed with signal kill before establishing connection. (SimWalkRunner-Runner encountered an error)",
            "the runner was killed before it connected to XCTest, so no step ran: the Mac or the device, not the app or the route — walk again",
        ])
    }

    @Test
    func aRunnerKilledAfterItConnectedIsNotRetried() throws {
        let (directory, output) = try missingOutput()
        _ = directory
        let recorder = Recorder()
        let later = RunnerFailureDiagnosis.failedBeforeTest(resultBundlePath: "first", failures: [RunnerFailureDiagnosis.StartFailure(testName: "testWalk()", failureText: "Test crashed with signal kill.")])
        let result = run(output: output, failures: ["first"], diagnosis: { _ in later }, recorder: recorder)

        #expect(!later.isKilledBeforeConnecting)
        #expect(recorder.attempts == ["first"])
        #expect(!later.lines.contains { $0.contains("no step ran") })
        #expect(result.firstResultBundlePath == nil)
    }
}

extension LaunchTimeoutRetryTests {
    private struct Failed: Error {}

    private static var timeoutText: String {
        "Failed to launch com.x: Timed out attempting to launch app."
    }

    private static func timeout(_ path: String) -> RunnerFailureDiagnosis {
        .failedBeforeTest(resultBundlePath: path, failures: [RunnerFailureDiagnosis.StartFailure(testName: "t", failureText: timeoutText)])
    }

    private static func killed(_ path: String) -> RunnerFailureDiagnosis {
        .failedBeforeTest(
            resultBundlePath: path,
            failures: [RunnerFailureDiagnosis.StartFailure(testName: "SimWalkRunner-Runner encountered an error", failureText: "Test crashed with signal kill before establishing connection.")]
        )
    }

    private static func digest(_ failure: String, path: String = "a") -> RunnerFailureDiagnosis {
        .digested(resultBundlePath: path, digest: RunnerActivityDigest(recentActivities: [], failure: failure, earlierFailures: 0, triageAttachments: []), hierarchy: .nothingAttached)
    }

    private final class Recorder {
        var attempts: [String] = []
        var diagnosed: [String] = []
    }

    private func run(output: URL, stopped: Bool = false, failures: Set<String>, diagnosis: @escaping (String) -> RunnerFailureDiagnosis, recorder: Recorder) -> LaunchTimeoutRetry.Run {
        LaunchTimeoutRetry.run(
            resultBundlePath: "first",
            nextResultBundlePath: { "second" },
            output: output,
            stopped: { stopped },
            diagnose: { path in
                recorder.diagnosed.append(path)
                return diagnosis(path)
            },
            attempt: { path in
                recorder.attempts.append(path)
                if failures.contains(path) {
                    throw Failed()
                }
            }
        )
    }

    private func missingOutput() throws -> (TemporaryDirectory, URL) {
        let directory = try TemporaryDirectory()
        return (directory, directory.url.appendingPathComponent("out"))
    }
}
