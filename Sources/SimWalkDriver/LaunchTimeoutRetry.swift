//
// Copyright © Agulhas Labs
//

import Foundation

/// Runs a walk's runner once, and once more when it stopped on a launch timeout before writing anything (SimWalk#266).
///
/// On a freshly booted, loaded simulator the runner's first `app.launch()` sometimes fails with `Timed out attempting to launch app.` while the app is fine. Running the runner again costs one more attempt; it is done only when the failure is that timeout and the output path holds nothing, so a second runner can never overwrite or mix with what the first wrote. There is never a third attempt, no pause between the two, and nothing is deleted.
public struct LaunchTimeoutRetry {
    /// Runs `attempt` with `resultBundlePath`, and again with `nextResultBundlePath()` when it failed on the launch timeout and `output` holds nothing.
    ///
    /// - Parameters:
    ///   - stopped: Whether the work was stopped; a stopped run reads nothing and is not repeated.
    ///   - diagnose: Reads a result bundle, called only after a failure.
    public static func run(
        resultBundlePath: String,
        nextResultBundlePath: () -> String,
        output: URL,
        stopped: () -> Bool,
        diagnose: (String) -> RunnerFailureDiagnosis,
        attempt: (String) throws -> Void
    ) -> Run {
        let firstFailure: any Error
        do {
            try attempt(resultBundlePath)
            return Run(failure: nil, resultBundlePath: resultBundlePath)
        } catch {
            firstFailure = error
        }
        if stopped() {
            return Run(failure: firstFailure, resultBundlePath: resultBundlePath)
        }
        let firstDiagnosis = diagnose(resultBundlePath)
        guard firstDiagnosis.isLaunchTimeout else {
            return Run(failure: firstFailure, resultBundlePath: resultBundlePath, diagnosis: firstDiagnosis)
        }
        guard holdsNothing(output) else {
            return Run(failure: firstFailure, resultBundlePath: resultBundlePath, diagnosis: firstDiagnosis, notRetriedForOutput: true)
        }
        let secondPath = nextResultBundlePath()
        do {
            try attempt(secondPath)
            return Run(failure: nil, resultBundlePath: secondPath, firstResultBundlePath: resultBundlePath)
        } catch {
            return Run(failure: error, resultBundlePath: secondPath, diagnosis: diagnose(secondPath), firstResultBundlePath: resultBundlePath)
        }
    }

    /// The lines a refusal prints under its failure: the last runner's `diagnosis`, led by a line naming the first runner's result bundle when a second runner ran, and followed by what `checkingLaunch` says when the diagnosis is the launch timeout.
    ///
    /// `checkingLaunch` is asked at most once, and only after the diagnosis has been read as a launch timeout.
    public static func diagnosisLines(diagnosis: RunnerFailureDiagnosis?, retry: Run?, checkingLaunch: (RunnerFailureDiagnosis) -> String?) -> [String] {
        var lines: [String] = []
        if let first = retry?.firstResultBundlePath {
            lines.append("the first runner timed out launching the app (result bundle: \(first)); what follows is the second runner's")
        }
        guard let diagnosis else {
            return lines
        }
        lines += diagnosis.lines
        if diagnosis.isLaunchTimeout, let check = checkingLaunch(diagnosis) {
            lines.append(check)
        }
        return lines
    }

    /// Whether nothing exists at `url`, or it is a directory with no entries; a directory that cannot be listed counts as holding something.
    static func holdsNothing(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return true
        }
        guard isDirectory.boolValue, let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return entries.isEmpty
    }
}

public extension LaunchTimeoutRetry {
    /// How the runner(s) ended.
    struct Run: Equatable {
        /// The last runner's failure; `nil` when it succeeded.
        public let failure: (any Error)?
        /// The last runner's result bundle path.
        public let resultBundlePath: String
        /// The last runner's diagnosis, when it was read here; `nil` means not read, and the caller reads it when it needs it.
        public let diagnosis: RunnerFailureDiagnosis?
        /// The first runner's result bundle path; set only when a second runner ran.
        public let firstResultBundlePath: String?
        /// The first runner timed out launching, but the output held something, so it was not run again.
        public let notRetriedForOutput: Bool

        public init(failure: (any Error)?, resultBundlePath: String, diagnosis: RunnerFailureDiagnosis? = nil, firstResultBundlePath: String? = nil, notRetriedForOutput: Bool = false) {
            self.failure = failure
            self.resultBundlePath = resultBundlePath
            self.diagnosis = diagnosis
            self.firstResultBundlePath = firstResultBundlePath
            self.notRetriedForOutput = notRetriedForOutput
        }

        /// How many runners ran: two when the first one's result bundle is recorded, else one.
        public var attempts: Int {
            firstResultBundlePath == nil ? 1 : 2
        }

        /// The line saying a second runner wrote the `product` (`bundle` for a walk, `report` for a dry run), so a reader is not told the first run succeeded; `nil` unless a second runner ran.
        ///
        /// It is shown only when a bundle or report was read, and a second runner that failed can still have left one.
        public func note(writing product: String) -> String? {
            guard let firstResultBundlePath else {
                return nil
            }
            return "the first runner timed out launching the app before it captured anything; a second runner wrote this \(product) (first runner's result bundle: \(firstResultBundlePath))"
        }

        public static func == (lhs: Run, rhs: Run) -> Bool {
            lhs.failure.map { "\($0)" } == rhs.failure.map { "\($0)" }
                && lhs.resultBundlePath == rhs.resultBundlePath
                && lhs.diagnosis == rhs.diagnosis
                && lhs.firstResultBundlePath == rhs.firstResultBundlePath
                && lhs.notRetriedForOutput == rhs.notRetriedForOutput
        }
    }
}
