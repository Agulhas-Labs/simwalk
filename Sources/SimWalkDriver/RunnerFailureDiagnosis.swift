//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// What a failed runner's result bundle says, read for the refusal that names it (SimWalk#50): the bundle's path, the ``RunnerActivityDigest`` of its activities, and where the UI hierarchy its failure triage attached was exported.
///
/// Before this, finding out meant locating the newest `.xcresult` under the build's `Logs/Test`, 40 kB of activities JSON, a script to flatten it, and a second `xcresulttool` call for the hierarchy — about 60 kB read for a dozen lines. The run now writes its bundle to a path named in advance (``RunnerInvocation/resultBundlePath(launchedAt:id:)``), so nothing is searched for.
///
/// Both calls are `xcrun xcresulttool` as version 25115 (schema 0.4.0) spells them — `get test-results activities --path --test-id --compact` and `export attachments --path --test-id --filter --output-path`. When the bundle is missing or the tool fails, the answer is one line saying so, and the refusal is otherwise what it was.
public enum RunnerFailureDiagnosis: Equatable, Sendable {
    /// The bundle was read and holds a failure.
    case digested(resultBundlePath: String, digest: RunnerActivityDigest, hierarchy: HierarchyExport)
    /// The bundle was read and records no failure to show.
    case nothingToShow(resultBundlePath: String)
    /// There is no bundle at the path, or `xcresulttool` could not read it.
    case unreadable(resultBundlePath: String, reason: String)
    /// The runner failed before its test started (SimWalk#124): the bundle holds no activities for the walk's test, only the failures its summary lists.
    case failedBeforeTest(resultBundlePath: String, failures: [StartFailure])

    /// The runner's one test, whose activities are the walk's.
    public static var walkTestID: String {
        "WalkRunner/testWalk()"
    }

    /// Reads the bundle at `resultBundlePath`, exporting the failure's hierarchy beside it (``exportDirectory(forResultBundle:)``).
    public static func read(resultBundlePath: String, testID: String = walkTestID, shell: Shell) -> RunnerFailureDiagnosis {
        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            return .unreadable(resultBundlePath: resultBundlePath, reason: "the runner wrote no result bundle")
        }
        let activities: Shell.Result
        do {
            activities = try xcresulttool(["get", "test-results", "activities", "--path", resultBundlePath, "--test-id", testID, "--compact"], shell: shell)
        } catch {
            return .unreadable(resultBundlePath: resultBundlePath, reason: "xcresulttool could not be run: \(error)")
        }
        guard activities.succeeded else {
            if let failed = failedBeforeTest(resultBundlePath: resultBundlePath, shell: shell) {
                return failed
            }
            return .unreadable(resultBundlePath: resultBundlePath, reason: "xcresulttool failed: \(activities.failureLine)")
        }
        guard !activities.truncated else {
            return .unreadable(resultBundlePath: resultBundlePath, reason: "xcresulttool's output was truncated")
        }
        guard let digest = RunnerActivityDigest.parse(Data(activities.standardOutput.utf8)) else {
            if let failed = failedBeforeTest(resultBundlePath: resultBundlePath, shell: shell) {
                return failed
            }
            return .nothingToShow(resultBundlePath: resultBundlePath)
        }
        return .digested(resultBundlePath: resultBundlePath, digest: digest, hierarchy: exportHierarchy(of: digest, from: resultBundlePath, testID: testID, shell: shell))
    }

    /// The failures the bundle's summary lists, when there are any.
    ///
    /// A runner that dies before `testWalk()` starts (the device asking for its passcode to allow UI automation, say) leaves a bundle with no such test: `get test-results activities --test-id` prints "Failed to find test with the provided identifier" and exits 0 with nothing on stdout, so the activities read has no failure to show. The reason is in `get test-results summary`'s `testFailures`, which is read only when the activities read gave nothing, so a bundle with a digest costs no second call. Any trouble reading the summary answers nil and the caller says what it said before.
    private static func failedBeforeTest(resultBundlePath: String, shell: Shell) -> RunnerFailureDiagnosis? {
        guard let summary = try? xcresulttool(["get", "test-results", "summary", "--path", resultBundlePath, "--compact"], shell: shell),
              summary.succeeded, !summary.truncated,
              let decoded = try? JSONDecoder().decode(Summary.self, from: Data(summary.standardOutput.utf8)),
              !decoded.testFailures.isEmpty
        else { return nil }
        return .failedBeforeTest(resultBundlePath: resultBundlePath, failures: decoded.testFailures)
    }

    /// Why a runner that timed out enabling automation mode did: a physical device's passcode prompt, worded to hold on a simulator too.
    private static var automationPromptLine: String {
        "UI automation could not be enabled in time: on a physical device, that is its prompt for the passcode to allow UI automation — unlock it, walk again, and enter the passcode on the device when the prompt appears (SimWalk#124)"
    }

    /// Where a bundle's hierarchy is exported: a directory beside it, named after it.
    public static func exportDirectory(forResultBundle path: String) -> String {
        (path.hasSuffix(".xcresult") ? String(path.dropLast(".xcresult".count)) : path) + "-attachments"
    }

    /// The lines the refusal prints under the runner's own error.
    public var lines: [String] {
        switch self {
        case let .digested(path, digest, hierarchy):
            let recent = digest.recentActivities.isEmpty ? [] : ["the last \(digest.recentActivities.count) activities before the failure:"] + digest.recentActivities.map { "  \($0)" }
            let earlier = digest.earlierFailures == 0 ? "" : " (the last of \(digest.earlierFailures + 1) recorded)"
            return ["result bundle: \(path)"] + recent + ["failure: \(digest.failure)\(earlier)"] + hierarchy.lines
        case let .nothingToShow(path):
            return ["the runner's result bundle records no failure to show: \(path)"]
        case let .failedBeforeTest(path, failures):
            let failureLines = failures.map { "failure: \($0.failureText) (\($0.testName))" }
            let prompt = failures.contains { $0.failureText.contains("enabling automation mode") } ? [Self.automationPromptLine] : []
            return ["result bundle: \(path)"] + failureLines + prompt
        case let .unreadable(path, reason):
            return ["the runner's result bundle could not be read — \(reason): \(path)"]
        }
    }

    private static func exportHierarchy(of digest: RunnerActivityDigest, from path: String, testID: String, shell: Shell) -> HierarchyExport {
        guard !digest.hierarchyAttachments.isEmpty else { return .nothingAttached }
        let directory = exportDirectory(forResultBundle: path)
        let result: Shell.Result
        do {
            result = try xcresulttool(["export", "attachments", "--path", path, "--test-id", testID, "--filter", "\(RunnerActivityDigest.hierarchyNamePrefix)*", "--output-path", directory], shell: shell)
        } catch {
            return .failed(reason: "xcresulttool could not be run: \(error)")
        }
        guard result.succeeded else {
            return .failed(reason: "xcresulttool failed: \(result.failureLine)")
        }
        let written = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        let files = digest.exportedHierarchyFiles(among: written)
        guard !files.isEmpty else {
            return .failed(reason: "the export wrote none of the failure's hierarchy attachments into \(directory)")
        }
        return .exported(files.map { URL(fileURLWithPath: directory).appendingPathComponent($0).path })
    }

    /// Bounded, so a wedged tool costs the refusal a line rather than the walk its answer.
    private static func xcresulttool(_ arguments: [String], shell: Shell) throws -> Shell.Result {
        try shell.run("/usr/bin/xcrun", ["xcresulttool"] + arguments, timeout: 120)
    }
}

public extension RunnerFailureDiagnosis {
    /// One entry of the summary's `testFailures`: what failed, and the text saying why.
    struct StartFailure: Equatable, Sendable, Decodable {
        public let testName: String
        public let failureText: String

        public init(testName: String, failureText: String) {
            self.testName = testName
            self.failureText = failureText
        }
    }

    /// The part of `get test-results summary` that is read.
    fileprivate struct Summary: Decodable {
        let testFailures: [StartFailure]
    }

    /// What came of exporting the hierarchy the failure's triage attached.
    enum HierarchyExport: Equatable, Sendable {
        /// The triage attached none — nothing to say.
        case nothingAttached
        /// Exported, to these files.
        case exported([String])
        /// Attached, and not exported.
        case failed(reason: String)

        var lines: [String] {
            switch self {
            case .nothingAttached:
                []
            case let .exported(paths):
                paths.map { "UI hierarchy at the failure, exported to: \($0)" }
            case let .failed(reason):
                ["the UI hierarchy at the failure could not be exported — \(reason)"]
            }
        }
    }
}
