//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// A device walk's measure runs (SimWalk#67, M4; Brief "M4, performance on a device", rulings 3–5): one `testMeasure` run per measured screen and state, each into its own result bundle, read with `xcresulttool` and deleted, before the walk's own run.
///
/// **A measure run that fails never fails the walk.** Its screen and state are left without a record and the answer names the run and why; the walk goes on to take its captures. A lease that cannot be renewed is the one exception, and refuses as it would before the walk.
struct DeviceMeasure {
    let runner: RunnerInvocation
    let shell: Shell
    let udid: String
    let walkbookJSON: String
    let settleMilliseconds: Int?
    let deviceAppearance: Walkbook.Theme?
    let runnerCommit: String?

    /// Runs every measure run `book` asks for, renewing `lease` before each; none when no screen of `book` is measured.
    func run(_ book: Walkbook, renewing lease: WalkLease) throws -> Outcome {
        var outcome = Outcome()
        for run in MeasureRun.runs(for: book) {
            try lease.requireRenewed(now: Date())
            switch Result(catching: { try measure(run) }) {
            case let .success(performance):
                outcome.performance.record(performance, for: run)
                outcome.measured.append("measured \(run.subject): \(performance.summary(appBundleID: book.appBundleID))")
            case let .failure(error):
                outcome.failed.append("measure run \(run.subject) failed, no record: \(error)")
            }
        }
        return outcome
    }

    /// One run and its record; the result bundle is deleted whatever came of it, so the runner's build directory keeps none.
    private func measure(_ run: MeasureRun) throws -> CaptureManifest.Performance {
        let resultBundlePath = runner.resultBundlePath(launchedAt: Date(), id: UUID().uuidString)
        defer { try? FileManager.default.removeItem(atPath: resultBundlePath) }
        defer { try? FileManager.default.removeItem(atPath: RunnerFailureDiagnosis.exportDirectory(forResultBundle: resultBundlePath)) }
        do {
            try runner.measureOnDevice(
                run,
                walkbookJSON: walkbookJSON,
                udid: udid,
                settleMilliseconds: settleMilliseconds,
                deviceAppearance: deviceAppearance,
                runnerCommit: runnerCommit,
                resultBundlePath: resultBundlePath
            )
        } catch let RunnerError.measureFailed(reason) {
            // A runner that fails before its test (a locked phone, automation mode never enabled) says why only in its bundle (SimWalk#124).
            let diagnosis = RunnerFailureDiagnosis.read(resultBundlePath: resultBundlePath, testID: MeasureRun.testIdentifier, shell: shell).lines
            throw RunnerError.measureFailed(reason: ([reason] + diagnosis).joined(separator: "\n"))
        }
        // Bounded, so a wedged tool costs the run its record rather than the walk its answer.
        let read = try shell.run("/usr/bin/xcrun", ["xcresulttool", "get", "test-results", "metrics", "--path", resultBundlePath], timeout: 120)
        guard read.succeeded else {
            throw MetricsUnread(reason: read.failureLine)
        }
        return try XCResultMetrics.performance(from: Data(read.standardOutput.utf8), test: MeasureRun.testIdentifier, iterations: run.iterations)
    }
}

extension DeviceMeasure {
    /// What the runs came to: the records the walk's runner files, and the answer's lines.
    struct Outcome {
        var performance = MeasuredPerformance()
        /// One `measured <screen>/<state>: …` line per record, in walkbook order.
        var measured: [String] = []
        /// One line per run that left no record, naming it and why.
        var failed: [String] = []
    }

    /// `xcresulttool` could not read a measure run's result bundle.
    struct MetricsUnread: Error, CustomStringConvertible {
        let reason: String

        var description: String {
            "xcresulttool could not read the result bundle's metrics: \(reason)"
        }
    }
}
