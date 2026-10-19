//
// Copyright © Agulhas Labs
//

import Foundation

/// Answers a walk handle from the progress files alone, for a walk this server did not run.
///
/// The precedence table, rows 1–11, is in `Docs/Reference.md` ("Bounded walks"); nothing here writes a file. Only row 7 waits: a walk still running is re-read once a second up to the budget, each read re-applying rows 2–11, and the `running` line is the answer at the budget. The wait suspends on the injected `clock` and `sleep`, so a test never sleeps.
public struct WalkStatusReader: Sendable {
    /// The usage log's directory; the files are under `progress/` in it (``ProgressLocation``).
    public let directory: URL
    public let process: WalkProcessProbe

    public init(directory: URL, process: WalkProcessProbe = .system) {
        self.directory = directory
        self.process = process
    }

    /// The answer for `handle`.
    ///
    /// - Parameters:
    ///   - budget: the longest row 7 waits, in seconds.
    ///   - clock: seconds on a monotonic clock.
    ///   - sleep: suspends for the given seconds.
    public func status(
        of handle: String,
        budget: TimeInterval,
        clock: @Sendable () -> TimeInterval,
        sleep: @Sendable (TimeInterval) async -> Void
    ) async -> WalkStatus {
        guard let parsed = WalkHandle(parsing: handle) else {
            return Self.refusal("\(handle) is not a walk handle")
        }
        let began = clock()
        while true {
            switch evaluate(parsed) {
            case let .answer(status):
                return status
            case let .running(progress):
                let remaining = budget - (clock() - began)
                guard remaining > 0 else {
                    return WalkStatus(text: Self.runningLine(parsed, progress), isError: false)
                }
                await sleep(min(1, remaining))
            }
        }
    }

    /// The progress file of the walk `handle` names, or `nil` when it is missing, unreadable, or another run's.
    public func progress(of handle: WalkHandle) -> WalkProgress? {
        let url = ProgressLocation.progressDirectory(in: directory).appendingPathComponent(handle.stem + ".json")
        guard let data = try? Data(contentsOf: url), let progress = try? WalkProgress.decoder().decode(WalkProgress.self, from: data), handle.names(progress) else {
            return nil
        }
        return progress
    }

    /// The `running` line, its pieces from `progress`.
    ///
    /// Its grammar is `running — <handle>: <phase>[, step <i>/<n>[ <screen>]][, <failed> failed, <passed> of <planned> passed]; call walk_status with this handle`. A final phase, which the file reaches before the walk returns, prints as `finishing`.
    public static func runningLine(_ handle: WalkHandle, _ progress: WalkProgress) -> String {
        var line = "running — \(handle.text): \(progress.phase.isTerminal ? "finishing" : progress.phase.rawValue)"
        if let step = progress.currentStep, step.index >= 1, let total = step.total {
            line += ", step \(step.index)/\(total)" + (step.screen.map { " \($0)" } ?? "")
        }
        if let matches = progress.matches, matches.planned > 0 {
            line += ", \(matches.failed) failed, \(matches.passed) of \(matches.planned) passed"
        }
        return line + "; call walk_status with this handle"
    }
}

private extension WalkStatusReader {
    enum Evaluation {
        case answer(WalkStatus)
        case running(WalkProgress)
    }

    /// Rows 2–11, once.
    func evaluate(_ handle: WalkHandle) -> Evaluation {
        let url = ProgressLocation.progressDirectory(in: directory).appendingPathComponent(handle.stem + ".json")
        guard let data = try? Data(contentsOf: url) else {
            return .answer(Self.refusal(FileManager.default.fileExists(atPath: url.path) ? "the progress file for \(handle.text) is unreadable" : "no walk \(handle.text)"))
        }
        if let refusal = schemaRefusal(data, handle) {
            return .answer(refusal)
        }
        guard let progress = try? WalkProgress.decoder().decode(WalkProgress.self, from: data) else {
            return .answer(Self.refusal("the progress file for \(handle.text) is unreadable"))
        }
        guard handle.names(progress) else {
            return .answer(Self.refusal("the walk \(handle.text) was replaced by a later run under \(handle.stem)"))
        }
        guard progress.tool != "session" else {
            return .answer(Self.refusal("\(handle.text) is a live session, not a walk"))
        }
        guard progress.phase.isTerminal else {
            if process.isAlive(pid: progress.pid, since: progress.startedAt) {
                return .running(progress)
            }
            return .answer(Self.refusal("the walk \(handle.text) ended without finishing: the process running it exited"))
        }
        return .answer(ended(handle, progress))
    }

    /// Row 3's schema half: a file that parses but is not schema 1.
    func schemaRefusal(_ data: Data, _ handle: WalkHandle) -> WalkStatus? {
        struct Schema: Decodable {
            let schemaVersion: Int
        }
        guard let schema = try? JSONDecoder().decode(Schema.self, from: data) else {
            return Self.refusal("the progress file for \(handle.text) is unreadable")
        }
        guard schema.schemaVersion == WalkProgress.currentSchemaVersion else {
            return Self.refusal("the progress file for \(handle.text) is schema \(schema.schemaVersion), and this server reads \(WalkProgress.currentSchemaVersion)")
        }
        return nil
    }

    /// Rows 8–11: the walk is over.
    func ended(_ handle: WalkHandle, _ progress: WalkProgress) -> WalkStatus {
        if let path = progress.resultPath {
            return endedAnswer(handle, path: path)
        }
        if let error = progress.error {
            return Self.refusal("the walk \(handle.text) ended: \(error)")
        }
        if progress.tool == "walk --dry-run" {
            return WalkStatus(text: AnswerVerdict.unqualified("the dry run \(handle.text) finished; a dry run keeps no result file").line, isError: false)
        }
        return Self.refusal("the walk \(handle.text) ended but its result file was not written")
    }

    /// Row 8: the header from `result.json`, the verdict line, then `result: <path>`.
    func endedAnswer(_ handle: WalkHandle, path: String) -> WalkStatus {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let result = try? WalkResult.decoder().decode(WalkResult.self, from: data)
        else {
            return Self.refusal("the result file for \(handle.text) is unreadable: \(path)")
        }
        let counts = "\(result.counts.failed) failed, \(result.counts.passed) of \(result.counts.planned) matched"
        let verdict: AnswerVerdict = switch result.verdict {
        case .passed: .unqualified(counts)
        case .failed: .qualified([], detail: counts)
        case .refused: .refused(result.failures.first?.reason ?? counts)
        }
        let header = "walk: '\(result.walkName)'  app: \(result.app)  device: \(result.device.name) (\(result.device.osVersion))"
        return WalkStatus(text: [header, verdict.line, "result: \(path)"].joined(separator: "\n"), isError: verdict.exitCode == AnswerVerdict.refusedExitCode)
    }

    static func refusal(_ reason: String) -> WalkStatus {
        WalkStatus(text: AnswerVerdict.refused(reason).line, isError: true)
    }
}
