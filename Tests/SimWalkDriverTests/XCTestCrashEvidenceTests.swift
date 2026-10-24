//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What a simulator walk reads to tell XCTest blaming it for a host process's crash (SimWalk#176): the failure messages of a result bundle and the `xctest*.ips` reports of a directory.
struct XCTestCrashEvidenceTests {
    private static var nestedTests: String {
        """
        {"devices":[],"testPlanConfigurations":[],"testNodes":[{"nodeType":"Test Plan","name":"SimWalkRunner","children":[\
        {"nodeType":"UI test bundle","name":"SimWalkRunner","children":[{"nodeType":"Test Suite","name":"WalkRunner","children":[\
        {"nodeType":"Test Case","name":"testWalk()","children":[\
        {"name":"Critical process xctest crashed in (null)","nodeType":"Failure Message"},\
        {"name":"Critical process xctest crashed in (null)","nodeType":"Failure Message"}]}]}]}]}]}
        """
    }

    private static var hostReport: String {
        """
        {"app_name":"xctest","timestamp":"2026-10-21 10:25:15.00 +0100","bug_type":"309","name":"xctest"}
        {"procName":"xctest","procPath":"/private/var/folders/*/xctest","captureTime":"2026-10-21 10:25:15.6053 +0100"}
        """
    }

    private func bundle(in directory: TemporaryDirectory) throws -> String {
        let path = directory.url.appendingPathComponent("result.xcresult").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Every `Failure Message` node is collected, however deep, in the order listed.
    @Test
    func everyFailureMessageIsCollectedFromANestedTestsDocument() throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let shell = Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "") })

        let messages = XCTestCrashEvidence.failureMessages(resultBundlePath: path, shell: shell)

        #expect(messages == ["Critical process xctest crashed in (null)", "Critical process xctest crashed in (null)"])
    }

    /// A failing `xcresulttool` is nothing to excuse.
    @Test
    func anXcresulttoolFailureGivesNothingToExcuse() throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let shell = Shell(script: { _, _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "Error") })

        #expect(XCTestCrashEvidence.failureMessages(resultBundlePath: path, shell: shell) == nil)
    }

    /// A bundle that is not there is nothing to excuse, and `xcresulttool` is never run to find out.
    @Test
    func aMissingBundleGivesNothingToExcuse() {
        let shell = Shell(script: { _, _, _ in
            Issue.record("xcresulttool should not be run when the bundle does not exist")
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })

        #expect(XCTestCrashEvidence.failureMessages(resultBundlePath: "/no/such/place/simwalk.xcresult", shell: shell) == nil)
    }

    /// Only `xctest*.ips` files are read: another process's report and a file that is not a report are ignored.
    @Test
    func onlyXctestIpsFilesAreListedFromTheDirectory() throws {
        let directory = try TemporaryDirectory()
        for name in ["xctest-2026-10-21-102515.ips", "other-2026-10-21-102515.ips", "xctest-notes.txt"] {
            try Self.hostReport.write(to: directory.url.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let reports = XCTestCrashEvidence(directory: directory.url).reports()

        #expect(reports?.map(\.fileName) == ["xctest-2026-10-21-102515.ips"])
        #expect(reports?.first?.processName == "xctest")
    }

    /// A directory that cannot be listed is nothing to excuse: the failure is classified `notApplicable`.
    @Test
    func anUnreadableDirectoryGivesNothingToExcuse() throws {
        let directory = try TemporaryDirectory()
        let missing = directory.url.appendingPathComponent("absent", isDirectory: true)
        let path = try bundle(in: directory)
        let shell = Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "") })
        let evidence = XCTestCrashEvidence(directory: missing)

        #expect(evidence.reports() == nil)
        let failure = RunnerError.walkFailed(reason: "failed", status: 65)
        #expect(evidence.blame(failure, resultBundlePath: path, launchedAt: Date(timeIntervalSince1970: 0), endedAt: Date(), shell: shell) == .notApplicable)
    }

    /// Only xcodebuild's exit 65 is a test failure: a run that exited otherwise, or did not exit, gives nothing to excuse however well the messages and reports match.
    @Test(arguments: [nil, 1, 64, 70] as [Int32?])
    func aRunnerFailureThatIsNotExit65GivesNothingToExcuse(status: Int32?) throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let reports = try TemporaryDirectory()
        try Self.hostReport.write(to: reports.url.appendingPathComponent("xctest-2026-10-21-102515.ips"), atomically: true, encoding: .utf8)
        let shell = Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "") })
        let launchedAt = Date(timeIntervalSince1970: 1_792_574_500)
        let endedAt = Date(timeIntervalSince1970: 1_792_575_000)
        let evidence = XCTestCrashEvidence(directory: reports.url)

        let control = evidence.blame(RunnerError.walkFailed(reason: "failed", status: 65), resultBundlePath: path, launchedAt: launchedAt, endedAt: endedAt, shell: shell)
        let blame = evidence.blame(RunnerError.walkFailed(reason: "failed", status: status), resultBundlePath: path, launchedAt: launchedAt, endedAt: endedAt, shell: shell)

        #expect(control.isExcused, "the same evidence is excused at exit 65")
        #expect(blame == .notApplicable)
    }

    /// Three `ReportCrash` events for `xctest` in the window, one for another process.
    private static var logSample: String {
        """
        {"timestamp":"2026-10-22 08:14:18.891448+0100","eventMessage":"logGenerationTiming: sending CA event for xctest[309] elapsedTime=0.086"}
        {"timestamp":"2026-10-22 08:14:20.000000+0100","eventMessage":"logGenerationTiming: sending CA event for Finder[309] elapsedTime=0.100"}
        {"timestamp":"2026-10-22 08:14:26.838938+0100","eventMessage":"logGenerationTiming: sending CA event for xctest[309] elapsedTime=0.114"}
        {"timestamp":"2026-10-22 08:14:29.927062+0100","eventMessage":"logGenerationTiming: sending CA event for xctest[309] elapsedTime=0.073"}
        {"count":3,"finished":1}
        """
    }

    /// The runner launched 2026-10-22 08:13:07 BST and ended 08:15:00.
    private static let logLaunch = Date(timeIntervalSince1970: 1_792_653_187)
    private static let logEnd = Date(timeIntervalSince1970: 1_792_653_300)

    /// With no report found, the system log is read for the window and its count lands in the answer: `--style ndjson`, the ReportCrash predicate and the runner's own span (launch to end, not the hour before) in UTC.
    @Test
    func noReportsAndACrashLoggedGivesTheUnsavedCount() throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let reports = try TemporaryDirectory()
        var calls: [[String]] = []
        let shell = Shell(script: { executable, arguments, _ in
            if executable == "/usr/bin/log" {
                calls.append(arguments)
                return Shell.Result(status: 0, standardOutput: Self.logSample, standardError: "")
            }
            return Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "")
        })
        let evidence = XCTestCrashEvidence(directory: reports.url)

        let blame = evidence.blame(RunnerError.walkFailed(reason: "failed", status: 65), resultBundlePath: path, launchedAt: Self.logLaunch, endedAt: Self.logEnd, shell: shell)

        let searched = (reports.url.path as NSString).abbreviatingWithTildeInPath
        #expect(blame == .unexplained(failures: 2, reports: [], searched: searched, unsaved: 3))
        let arguments = try #require(calls.first)
        #expect(arguments.contains("ndjson"))
        #expect(arguments.contains(XCTestCrashLog.predicate))
        #expect(arguments.contains("2026-10-22 07:13:07+0000"))
        #expect(arguments.contains("2026-10-22 07:15:00+0000"))
    }

    /// A host report in the window excuses the failure and the log is never read.
    @Test
    func aHostReportExcusesTheFailureWithoutReadingTheLog() throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let reports = try TemporaryDirectory()
        try Self.hostReport.write(to: reports.url.appendingPathComponent("xctest-2026-10-21-102515.ips"), atomically: true, encoding: .utf8)
        let shell = Shell(script: { executable, _, _ in
            if executable == "/usr/bin/log" {
                Issue.record("the system log should not be read when a report excuses the failure")
            }
            return Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "")
        })
        let launchedAt = Date(timeIntervalSince1970: 1_792_574_500)
        let endedAt = Date(timeIntervalSince1970: 1_792_575_000)

        let blame = XCTestCrashEvidence(directory: reports.url).blame(RunnerError.walkFailed(reason: "failed", status: 65), resultBundlePath: path, launchedAt: launchedAt, endedAt: endedAt, shell: shell)

        #expect(blame.isExcused)
    }

    /// A `log` call that fails leaves the count unknown, not zero.
    @Test
    func aFailingLogCallLeavesTheUnsavedCountUnknown() throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let reports = try TemporaryDirectory()
        let shell = Shell(script: { executable, _, _ in
            executable == "/usr/bin/log"
                ? Shell.Result(status: 1, standardOutput: "", standardError: "log: error")
                : Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "")
        })

        let blame = XCTestCrashEvidence(directory: reports.url).blame(RunnerError.walkFailed(reason: "failed", status: 65), resultBundlePath: path, launchedAt: Self.logLaunch, endedAt: Self.logEnd, shell: shell)

        let searched = (reports.url.path as NSString).abbreviatingWithTildeInPath

        #expect(blame == .unexplained(failures: 2, reports: [], searched: searched, unsaved: nil))
    }

    /// A log reply cut short is not trusted to count: the unsaved count stays unknown.
    @Test
    func aTruncatedLogReplyLeavesTheUnsavedCountUnknown() throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let reports = try TemporaryDirectory()
        let shell = Shell(script: { executable, _, _ in
            executable == "/usr/bin/log"
                ? Shell.Result(status: 0, standardOutput: Self.logSample, standardError: "", truncated: true)
                : Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "")
        })

        let blame = XCTestCrashEvidence(directory: reports.url).blame(RunnerError.walkFailed(reason: "failed", status: 65), resultBundlePath: path, launchedAt: Self.logLaunch, endedAt: Self.logEnd, shell: shell)

        let searched = (reports.url.path as NSString).abbreviatingWithTildeInPath

        #expect(blame == .unexplained(failures: 2, reports: [], searched: searched, unsaved: nil))
    }

    /// A simulator `xctest` report in the window leaves the failure unexplained with that report named, and the system log is never read: it is read only when no report was found.
    @Test
    func aSimulatorReportIsNamedWithoutReadingTheLog() throws {
        let directory = try TemporaryDirectory()
        let path = try bundle(in: directory)
        let reports = try TemporaryDirectory()
        let simulatorReport = """
        {"app_name":"xctest","timestamp":"2026-10-21 10:26:00.00 +0100","bug_type":"309","name":"xctest"}
        {"procName":"xctest","procPath":"/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest","captureTime":"2026-10-21 10:26:00.2500 +0100","parentProc":"launchd_sim","coalitionName":"com.apple.CoreSimulator.SimDevice.DEVICE"}
        """
        try simulatorReport.write(to: reports.url.appendingPathComponent("xctest-2026-10-21-102600.ips"), atomically: true, encoding: .utf8)
        let shell = Shell(script: { executable, _, _ in
            if executable == "/usr/bin/log" {
                Issue.record("the system log should not be read when a report was found")
            }
            return Shell.Result(status: 0, standardOutput: Self.nestedTests, standardError: "")
        })

        let blame = XCTestCrashEvidence(directory: reports.url).blame(RunnerError.walkFailed(reason: "failed", status: 65), resultBundlePath: path, launchedAt: Date(timeIntervalSince1970: 1_792_574_500), endedAt: Date(timeIntervalSince1970: 1_792_575_000), shell: shell)

        let searched = (reports.url.path as NSString).abbreviatingWithTildeInPath

        #expect(blame == .unexplained(failures: 2, reports: ["xctest-2026-10-21-102600.ips"], searched: searched, unsaved: nil))
    }
}
