//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a runner's failures are XCTest blaming the walk for a crash of another process named `xctest` on the Mac (SimWalk#176).
///
/// XCUITest reads the host's crash reports, where a simulator's land too, and records `Critical process xctest crashed in (null)` for any recent crash of a process of that name — so another session launching an `xctest` that macOS kills fails a walk that never crashed. A runner failure is excused only when **every** failure is that message, at least one report of a host `xctest` (``HostCrashReport/isInSimulator`` false) was captured in the window, and none of an `xctest` inside a simulator was: a simulator's `xctest` crash may be this walk's own.
///
/// The window is from an hour before the runner launched to when it ended (``window(launchedAt:endedAt:)``). Pure: the failures, the reports and the window in, a classification out.
public enum XCTestCrashBlame: Equatable, Sendable {
    /// The failures are not all XCTest's crash message, or there are none: nothing to excuse, nothing to add.
    case notApplicable
    /// Every failure is the crash message and the reports in the window are a host process's alone: not this walk's failure.
    ///
    /// `reports` are their file names, in capture order.
    case hostReports(failures: Int, reports: [String])
    /// Every failure is the crash message, and the reports do not show it was a host process's: the failure stands.
    ///
    /// `reports` are the file names of every `xctest` report in the window, in capture order; `searched` is where they were looked for. `unsaved` is how many crashes of a process named `xctest` the system log records while the runner ran when no report was found (``XCTestCrashLog``, SimWalk#191); `nil` when the log was not read or could not be.
    case unexplained(failures: Int, reports: [String], searched: String, unsaved: Int?)

    /// How XCTest's message for a crash it saw begins.
    public static var failurePrefix: String {
        "Critical process xctest crashed"
    }

    /// From an hour before the runner launched to when it ended.
    public static func window(launchedAt: Date, endedAt: Date) -> DateInterval {
        let start = launchedAt.addingTimeInterval(-3600)
        return DateInterval(start: start, end: max(start, endedAt))
    }

    /// What `failureMessages` come to, given the crash `reports` found in `searched` and the run's `window`.
    public static func classify(failureMessages: [String], reports: [HostCrashReport], window: DateInterval, searched: String) -> XCTestCrashBlame {
        guard !failureMessages.isEmpty, failureMessages.allSatisfy({ $0.hasPrefix(failurePrefix) }) else { return .notApplicable }
        let inWindow = reports
            .filter { $0.processName == "xctest" && window.contains($0.capturedAt) }
            .sorted { ($0.capturedAt, $0.fileName) < ($1.capturedAt, $1.fileName) }
        let host = inWindow.filter { !$0.isInSimulator }
        guard !host.isEmpty, host.count == inWindow.count else {
            return .unexplained(failures: failureMessages.count, reports: inWindow.map(\.fileName), searched: searched, unsaved: nil)
        }
        return .hostReports(failures: failureMessages.count, reports: host.map(\.fileName))
    }

    /// Whether the runner failure is excused: not counted as one.
    public var isExcused: Bool {
        if case .hostReports = self {
            true
        } else {
            false
        }
    }

    /// The line an answer carries; `nil` when there is nothing to say.
    public var line: String? {
        switch self {
        case .notApplicable:
            nil
        case let .hostReports(failures, reports):
            "XCTest reported \(Self.count(failures)) for crash reports of a host process named xctest, not this walk (captured from an hour before the run to its end): \(Self.names(reports)) — not counted as a runner failure"
        case let .unexplained(failures, reports, searched, unsaved):
            "the runner failure is \(Self.count(failures)); crash reports of a process named xctest from an hour before the run to its end: \(reports.isEmpty ? "none in \(searched)" + Self.unsavedClause(unsaved) : Self.names(reports))"
        }
    }

    /// What the system log adds when no report was found: crashes macOS saved no report for.
    ///
    /// Nothing for zero or an unread log, since a log message macOS might rename is not proof that no crash happened.
    private static func unsavedClause(_ unsaved: Int?) -> String {
        guard let unsaved, unsaved > 0 else { return "" }
        return ", though the system log records \(unsaved) crash\(unsaved == 1 ? "" : "es") of a process named xctest while the runner ran that macOS saved no report for, so which process crashed cannot be told"
    }

    private static func count(_ failures: Int) -> String {
        "\(failures) \"\(failurePrefix)\" failure\(failures == 1 ? "" : "s")"
    }

    /// At most three names, then how many more.
    private static func names(_ reports: [String]) -> String {
        reports.prefix(3).joined(separator: ", ") + (reports.count > 3 ? " (+\(reports.count - 3) more)" : "")
    }
}
