//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// What a simulator walk reads to tell whether its runner failure was XCTest blaming it for a host process's crash (SimWalk#176): the failures its result bundle lists, and the `xctest*.ips` crash reports in ``directory``.
///
/// The failures come from `xcrun xcresulttool get test-results tests --path --compact` as version 25115 (schema 0.4.0) prints it — every `Failure Message` node's `name`, anywhere under `testNodes`. Not `summary`, whose `testFailures` lists only the first. A missing or unreadable bundle, or a directory that cannot be listed, answers ``XCTestCrashBlame/notApplicable``: nothing to excuse, so the failure stands as it did.
public struct XCTestCrashEvidence: Sendable {
    /// Where the crash reports are read: the Mac's own, by default; a test's scratch otherwise.
    public let directory: URL

    public init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    /// `~/Library/Logs/DiagnosticReports`, where macOS files a crash report, a simulator's included.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// What `runnerFailure` comes to: classified only when it is a test failure (``RunnerError/isTestFailure``) and the run's result bundle is at `resultBundlePath`; ``XCTestCrashBlame/notApplicable`` otherwise.
    public func blame(_ runnerFailure: Error, resultBundlePath: String?, launchedAt: Date, endedAt: Date, shell: Shell) -> XCTestCrashBlame {
        guard (runnerFailure as? RunnerError)?.isTestFailure == true, let resultBundlePath,
              let messages = Self.failureMessages(resultBundlePath: resultBundlePath, shell: shell),
              messages.allSatisfy({ $0.hasPrefix(XCTestCrashBlame.failurePrefix) }),
              let reports = reports()
        else { return .notApplicable }
        let window = XCTestCrashBlame.window(launchedAt: launchedAt, endedAt: endedAt)
        let searched = (directory.path as NSString).abbreviatingWithTildeInPath
        let blame = XCTestCrashBlame.classify(failureMessages: messages, reports: reports, window: window, searched: searched)
        guard case let .unexplained(failures, found, searched, _) = blame, found.isEmpty else { return blame }
        return .unexplained(failures: failures, reports: found, searched: searched, unsaved: Self.unsavedCrashes(window: DateInterval(start: launchedAt, end: max(launchedAt, endedAt)), shell: shell))
    }

    /// How many crashes of a process named `xctest` the system log records in `window`, the runner's own span; `nil` when `log` fails, times out, is truncated or prints nothing decodable.
    ///
    /// Read only when no report was found: macOS keeps at most 25 of one process's crash reports, so a busy Mac saves none for a crash XCUITest was still told of (SimWalk#191).
    static func unsavedCrashes(window: DateInterval, shell: Shell) -> Int? {
        guard let result = try? shell.run("/usr/bin/log", XCTestCrashLog.arguments(window: window), timeout: 30),
              result.succeeded, !result.truncated
        else { return nil }
        return XCTestCrashLog.parse(ndjson: result.standardOutput, window: window)?.crashes
    }

    /// Every failure message the bundle at `resultBundlePath` records, in the order `xcresulttool` lists them; `nil` when the bundle is missing or could not be read.
    public static func failureMessages(resultBundlePath: String, shell: Shell) -> [String]? {
        guard FileManager.default.fileExists(atPath: resultBundlePath),
              let result = try? RunnerFailureDiagnosis.xcresulttool(["get", "test-results", "tests", "--path", resultBundlePath, "--compact"], shell: shell),
              result.succeeded, !result.truncated,
              let document = try? JSONDecoder().decode(Document.self, from: Data(result.standardOutput.utf8))
        else { return nil }
        var messages: [String] = []
        for node in document.testNodes {
            node.collectFailureMessages(into: &messages)
        }
        return messages
    }

    /// Every readable `xctest*.ips` report in ``directory``; `nil` when it cannot be listed.
    public func reports() -> [HostCrashReport]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        return names.filter { $0.hasPrefix("xctest") && $0.hasSuffix(".ips") }.sorted().compactMap { name in
            (try? Data(contentsOf: directory.appendingPathComponent(name))).flatMap { HostCrashReport.parse(fileName: name, $0) }
        }
    }
}

extension XCTestCrashEvidence {
    /// The part of `get test-results tests` that is read.
    private struct Document: Decodable {
        let testNodes: [Node]
    }

    /// One node of the test tree: a plan, bundle, suite, case or failure message.
    private struct Node: Decodable {
        let name: String?
        let nodeType: String?
        let children: [Node]?

        func collectFailureMessages(into messages: inout [String]) {
            if nodeType == "Failure Message", let name {
                messages.append(name)
            }
            for child in children ?? [] {
                child.collectFailureMessages(into: &messages)
            }
        }
    }
}
