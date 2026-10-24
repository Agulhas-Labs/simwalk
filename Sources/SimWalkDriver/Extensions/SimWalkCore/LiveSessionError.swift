//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

public extension LiveSessionError {
    /// This error with what the runner left behind, when it is a runner that stopped without writing an exit record (SimWalk#240): its result bundle's account of the failure (``RunnerFailureDiagnosis``) — a killed or crashed runner app reads "Test crashed with signal kill." there — and the last lines of `xcodebuild`'s output in `runner.log`.
    ///
    /// **Without them a dead runner is a bare loss**: the answer said only that the runner stopped, so a runner killed under load read the same as one that crashed on the app, and nothing was left to tell them apart once the session was ended and its directory removed. Read only once the runner is gone, so the bundle is as whole as `xcodebuild` left it. Anything else is returned as it is, and so is a stopped runner that kept neither file.
    func explained(by layout: LiveSessionLayout, testID: String, shell: Shell) -> LiveSessionError {
        guard case let .runnerExited(number, nil, cause) = self, cause.isEmpty else { return self }
        var found: [String] = []
        if FileManager.default.fileExists(atPath: layout.resultBundle.path) {
            found += RunnerFailureDiagnosis.read(resultBundlePath: layout.resultBundle.path, testID: testID, shell: shell).lines
        }
        if let log = try? String(contentsOf: layout.runnerLog, encoding: .utf8) {
            let tail = Self.outputTail(of: log)
            if !tail.isEmpty {
                found += ["the last of xcodebuild's output (\(layout.runnerLog.path)):"] + tail.map { "  \($0)" }
            }
        }
        return .runnerExited(number: number, exit: nil, cause: found)
    }

    /// The last ``outputTailLength`` lines of `xcodebuild`'s output that say something: blank lines and its own timestamped `[MT]` diagnostics, which fill the end of every run's log alike, are left out.
    private static func outputTail(of log: String) -> [String] {
        let lines = log.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains(" [MT] ") }
        return Array(lines.suffix(outputTailLength))
    }

    /// How many lines of `xcodebuild`'s output a stopped runner's answer quotes.
    private static var outputTailLength: Int {
        6
    }
}
