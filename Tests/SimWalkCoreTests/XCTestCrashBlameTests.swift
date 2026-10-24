//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A runner failure is excused only when every failure is XCTest's crash message and the crash reports in the window are a host `xctest`'s alone (SimWalk#176).
struct XCTestCrashBlameTests {
    private static let launched = Date(timeIntervalSince1970: 1_792_574_860)
    private static let window = XCTestCrashBlame.window(launchedAt: launched, endedAt: launched.addingTimeInterval(73))
    private static var message: String {
        "Critical process xctest crashed in (null)"
    }

    @Test
    func theWindowRunsFromAnHourBeforeTheLaunchToTheEnd() {
        #expect(Self.window.start == Self.launched.addingTimeInterval(-3600))
        #expect(Self.window.end == Self.launched.addingTimeInterval(73))
    }

    @Test
    func hostReportsAloneInTheWindowExcuseTheFailuresAndAreNamedInCaptureOrder() {
        let reports = [Self.report("b.ips", at: -60), Self.report("a.ips", at: -120), Self.report("late.ips", at: 600)]

        let blame = XCTestCrashBlame.classify(failureMessages: Array(repeating: Self.message, count: 10), reports: reports, window: Self.window, searched: "~/Library/Logs/DiagnosticReports")

        #expect(blame == .hostReports(failures: 10, reports: ["a.ips", "b.ips"]))
        #expect(blame.isExcused)
    }

    @Test
    func aSimulatorXctestReportInTheWindowLeavesTheFailureUnexplained() throws {
        let simulator = try #require(HostCrashReport.parse(fileName: "xctest-simulator.ips", HostCrashReportTests.fixture("xctest-simulator")))
        let host = try #require(HostCrashReport.parse(fileName: "xctest-host.ips", HostCrashReportTests.fixture("xctest-host")))

        let blame = XCTestCrashBlame.classify(failureMessages: [Self.message], reports: [simulator, host], window: Self.window, searched: "~/Library/Logs/DiagnosticReports")

        #expect(simulator.isInSimulator, "the real shape, whose path is not under CoreSimulator")
        #expect(blame == .unexplained(failures: 1, reports: ["xctest-host.ips", "xctest-simulator.ips"], searched: "~/Library/Logs/DiagnosticReports", unsaved: nil))
        #expect(!blame.isExcused)
    }

    @Test
    func aReportOutsideTheWindowLeavesTheFailureUnexplainedWithNoneFound() {
        let blame = XCTestCrashBlame.classify(failureMessages: [Self.message, Self.message], reports: [Self.report("old.ips", at: -3700)], window: Self.window, searched: "~/Library/Logs/DiagnosticReports")

        #expect(blame.line == #"the runner failure is 2 "Critical process xctest crashed" failures; crash reports of a process named xctest from an hour before the run to its end: none in ~/Library/Logs/DiagnosticReports"#)
        #expect(!blame.isExcused)
    }

    /// One failure that is not the crash message, another process's report, or no failure at all: nothing to classify.
    @Test
    func aFailureThatIsNotTheCrashMessageIsNotApplicable() {
        let reports = [Self.report("a.ips", at: -60)]

        #expect(XCTestCrashBlame.classify(failureMessages: [Self.message, "XCTAssertTrue failed"], reports: reports, window: Self.window, searched: "d") == .notApplicable)
        #expect(XCTestCrashBlame.classify(failureMessages: [], reports: reports, window: Self.window, searched: "d") == .notApplicable)
        #expect(XCTestCrashBlame.classify(failureMessages: [Self.message], reports: [Self.report("a.ips", at: -60, process: "Finder")], window: Self.window, searched: "d") != .hostReports(failures: 1, reports: ["a.ips"]))
        #expect(XCTestCrashBlame.notApplicable.line == nil)
    }

    @Test
    func theExcusedLineNamesOneReportInTheSingular() {
        let blame = XCTestCrashBlame.classify(failureMessages: [Self.message], reports: [Self.report("xctest-1.ips", at: -60)], window: Self.window, searched: "d")

        #expect(blame.line == #"XCTest reported 1 "Critical process xctest crashed" failure for crash reports of a host process named xctest, not this walk (captured from an hour before the run to its end): xctest-1.ips — not counted as a runner failure"#)
    }

    @Test
    func theExcusedLineNamesThreeOfFiveReportsAndCountsTheRest() {
        let reports = (1 ... 5).map { Self.report("xctest-\($0).ips", at: TimeInterval($0 * 10 - 600)) }

        let blame = XCTestCrashBlame.classify(failureMessages: Array(repeating: Self.message, count: 10), reports: reports, window: Self.window, searched: "d")

        #expect(blame.line == #"XCTest reported 10 "Critical process xctest crashed" failures for crash reports of a host process named xctest, not this walk (captured from an hour before the run to its end): xctest-1.ips, xctest-2.ips, xctest-3.ips (+2 more) — not counted as a runner failure"#)
    }

    /// With no report found, the line adds the crashes the system log records that macOS saved no report for, in the singular for one; zero or an unread log leaves it as it was.
    @Test
    func theUnexplainedLineSaysWhenTheSystemLogRecordsCrashesWithNoSavedReport() {
        func line(_ unsaved: Int?) -> String? {
            XCTestCrashBlame.unexplained(failures: 2, reports: [], searched: "~/d", unsaved: unsaved).line
        }
        let base = #"the runner failure is 2 "Critical process xctest crashed" failures; crash reports of a process named xctest from an hour before the run to its end: none in ~/d"#

        #expect(line(3) == base + ", though the system log records 3 crashes of a process named xctest while the runner ran that macOS saved no report for, so which process crashed cannot be told")
        #expect(line(1) == base + ", though the system log records 1 crash of a process named xctest while the runner ran that macOS saved no report for, so which process crashed cannot be told")
        #expect(line(0) == base)
        #expect(line(nil) == base)
    }

    private static func report(_ name: String, at offset: TimeInterval, process: String = "xctest") -> HostCrashReport {
        HostCrashReport(fileName: name, processName: process, processPath: "/private/var/folders/*/xctest", capturedAt: launched.addingTimeInterval(offset))
    }
}
