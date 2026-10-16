//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What a failed runner's result bundle says (SimWalk#50): each of the three ways reading it can fall short is one line naming why, never a throw.
struct RunnerFailureDiagnosisTests {
    /// No bundle at the named path — the runner never wrote one, or wrote it somewhere else — is one line saying so, and `xcresulttool` is never run to find out.
    @Test
    func amissingResultBundleIsOneLineSayingSoAndNeverRunsXcresulttool() {
        let path = "/no/such/place/simwalk.xcresult"
        let shell = Shell(script: { _, _, _ in
            Issue.record("xcresulttool should not be run when the bundle path does not exist")
            return Shell.Result(status: 1, standardOutput: "", standardError: "")
        })

        let diagnosis = RunnerFailureDiagnosis.read(resultBundlePath: path, shell: shell)

        #expect(diagnosis == .unreadable(resultBundlePath: path, reason: "the runner wrote no result bundle"))
        #expect(diagnosis.lines.count == 1)
    }

    /// A bundle that is there, but `xcresulttool get test-results activities` exits non-zero — a schema `xcresulttool` cannot read, say — is one line naming its own failure.
    @Test
    func anXcresulttoolFailureIsOneLineSayingSo() throws {
        let directory = try TemporaryDirectory()
        let bundlePath = directory.url.appendingPathComponent("result.xcresult").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        let shell = Shell(script: { _, _, _ in
            Shell.Result(status: 1, standardOutput: "", standardError: "Error: no matching test found\n")
        })

        let diagnosis = RunnerFailureDiagnosis.read(resultBundlePath: bundlePath, shell: shell)

        guard case let .unreadable(_, reason) = diagnosis else {
            Issue.record("expected .unreadable, got \(diagnosis)")
            return
        }

        #expect(reason.contains("Error: no matching test found"))
        #expect(diagnosis.lines.count == 1)
    }

    /// A bundle that is there, and whose `xcresulttool` call exited successfully but was cut off at the drain limit, is worded as truncated rather than as an `xcresulttool` failure it never was (item 3 of the round-2 review).
    @Test
    func atruncatedResultIsWordedAsTruncatedNotAsAnXcresulttoolFailure() throws {
        let directory = try TemporaryDirectory()
        let bundlePath = directory.url.appendingPathComponent("result.xcresult").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        let shell = Shell(script: { _, _, _ in
            Shell.Result(status: 0, standardOutput: "{\"testRuns\":[", standardError: "", truncated: true)
        })

        let diagnosis = RunnerFailureDiagnosis.read(resultBundlePath: bundlePath, shell: shell)

        guard case let .unreadable(_, reason) = diagnosis else {
            Issue.record("expected .unreadable, got \(diagnosis)")
            return
        }

        #expect(reason.contains("truncated"))
        #expect(!reason.contains("xcresulttool failed"))
    }

    /// A bundle whose activities are readable and whose failure's triage attached the UI hierarchy, but whose export writes none of it (a bundle stripped of its attachments, say) — one line saying the export wrote nothing, not a silent `.exported([])`.
    @Test
    func anExportThatWritesNothingIsOneLineSayingSo() throws {
        let directory = try TemporaryDirectory()
        let bundlePath = directory.url.appendingPathComponent("result.xcresult").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        let activitiesJSON = """
        {"testRuns":[{"activities":[
          {"title":"Collecting debug information to assist test failure triage","isAssociatedWithFailure":false,"attachments":[{"name":"App UI hierarchy for com.example.app","uuid":"ABCD1234"}]},
          {"title":"Assertion failed","isAssociatedWithFailure":true}
        ]}]}
        """
        let shell = Shell(script: { _, arguments, _ in
            if arguments.contains("export") {
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }
            return Shell.Result(status: 0, standardOutput: activitiesJSON, standardError: "")
        })

        let diagnosis = RunnerFailureDiagnosis.read(resultBundlePath: bundlePath, shell: shell)

        guard case let .digested(_, _, hierarchy) = diagnosis else {
            Issue.record("expected .digested, got \(diagnosis)")
            return
        }
        guard case let .failed(reason) = hierarchy else {
            Issue.record("expected .failed, got \(hierarchy)")
            return
        }

        #expect(reason.contains("wrote none"))
        #expect(hierarchy.lines.count == 1)
    }

    /// The real `get test-results summary --compact` of a runner that died before its test (SimWalk#124): an iPad Pro asking for its passcode to allow UI automation, 2026-10-15.
    private static var startFailureSummary: String {
        #"""
        {"devicesAndConfigurations":[{"device":{"architecture":"arm64","deviceId":"00008000-0000000000000000","deviceName":"iPad","modelName":"iPad Pro 13-inch (M5)","osBuildNumber":"24A446","osVersion":"27.0.1","platform":"iOS"},"expectedFailures":0,"failedTests":1,"passedTests":0,"skippedTests":0,"testPlanConfiguration":{"configurationId":"1","configurationName":"Test Scheme Action"}}],"environmentDescription":"SimWalkRunner · Built with macOS 27.0.1","expectedFailures":0,"failedTests":1,"finishTime":1792089339.502,"passedTests":0,"result":"Failed","runtimeWarnings":[],"skippedTests":0,"startTime":1792089277.596,"statistics":[],"testFailures":[{"failureText":"The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.)","targetName":"SimWalkRunner","testIdentifier":1,"testIdentifierString":"SimWalkRunner-Runner (1627) encountered an error","testName":"SimWalkRunner-Runner (1627) encountered an error"}],"title":"Test - SimWalkRunner","topInsights":[],"totalTestCount":1}
        """#
    }

    private static func expectStartFailureLines(_ diagnosis: RunnerFailureDiagnosis, path: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let failure = RunnerFailureDiagnosis.StartFailure(
            testName: "SimWalkRunner-Runner (1627) encountered an error",
            failureText: "The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.)"
        )

        #expect(diagnosis == .failedBeforeTest(resultBundlePath: path, failures: [failure]), sourceLocation: sourceLocation)
        #expect(diagnosis.lines.first == "result bundle: \(path)", sourceLocation: sourceLocation)
        #expect(diagnosis.lines.contains("failure: \(failure.failureText) (\(failure.testName))"), sourceLocation: sourceLocation)
        #expect(diagnosis.lines.contains { $0.hasPrefix("UI automation could not be enabled in time") && $0.hasSuffix("(SimWalk#124)") }, sourceLocation: sourceLocation)
    }

    /// Two failures that both timed out enabling automation mode: the passcode line is said once.
    @Test
    func thePasscodeLineIsSaidOnceForTwoMatchingFailures() {
        let failure = RunnerFailureDiagnosis.StartFailure(testName: "a", failureText: "Timed out while enabling automation mode.")
        let other = RunnerFailureDiagnosis.StartFailure(testName: "b", failureText: "Timed out while enabling automation mode.")
        let lines = RunnerFailureDiagnosis.failedBeforeTest(resultBundlePath: "/x.xcresult", failures: [failure, other]).lines

        #expect(lines.filter { $0.hasPrefix("UI automation could not be enabled in time") }.count == 1)
        #expect(lines.filter { $0.hasPrefix("failure:") }.count == 2)
    }

    /// `activities --test-id` for a test that never started prints an error and exits 0 with nothing on stdout: the summary's failures are the answer, not "records no failure to show".
    @Test
    func aRunnerThatFailedBeforeItsTestNamesTheSummarysFailure() throws {
        let directory = try TemporaryDirectory()
        let bundlePath = directory.url.appendingPathComponent("result.xcresult").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        let shell = Shell(script: { _, arguments, _ in
            arguments.contains("summary")
                ? Shell.Result(status: 0, standardOutput: Self.startFailureSummary, standardError: "")
                : Shell.Result(status: 0, standardOutput: "", standardError: "Error: Failed to find test with the provided identifier\n")
        })

        Self.expectStartFailureLines(RunnerFailureDiagnosis.read(resultBundlePath: bundlePath, shell: shell), path: bundlePath)
    }

    /// The same bundle when `xcresulttool` exits non-zero for the activities read.
    @Test
    func aFailedActivitiesReadFallsBackToTheSummarysFailure() throws {
        let directory = try TemporaryDirectory()
        let bundlePath = directory.url.appendingPathComponent("result.xcresult").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        let shell = Shell(script: { _, arguments, _ in
            arguments.contains("summary")
                ? Shell.Result(status: 0, standardOutput: Self.startFailureSummary, standardError: "")
                : Shell.Result(status: 1, standardOutput: "", standardError: "Error: Failed to find test\n")
        })

        Self.expectStartFailureLines(RunnerFailureDiagnosis.read(resultBundlePath: bundlePath, shell: shell), path: bundlePath)
    }

    /// A summary with no failures leaves the answer what it was before the summary was read.
    @Test
    func aSummaryWithNoFailuresLeavesTheOldAnswers() throws {
        let directory = try TemporaryDirectory()
        let bundlePath = directory.url.appendingPathComponent("result.xcresult").path
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        let summary = #"{"result":"Failed","testFailures":[]}"#
        let empty = Shell(script: { _, arguments, _ in
            Shell.Result(status: 0, standardOutput: arguments.contains("summary") ? summary : "", standardError: "")
        })
        let failing = Shell(script: { _, arguments, _ in
            arguments.contains("summary") ? Shell.Result(status: 0, standardOutput: summary, standardError: "") : Shell.Result(status: 1, standardOutput: "", standardError: "boom\n")
        })

        #expect(RunnerFailureDiagnosis.read(resultBundlePath: bundlePath, shell: empty) == .nothingToShow(resultBundlePath: bundlePath))
        guard case let .unreadable(_, reason) = RunnerFailureDiagnosis.read(resultBundlePath: bundlePath, shell: failing) else {
            Issue.record("expected .unreadable")
            return
        }

        #expect(reason.contains("boom"))
    }
}
