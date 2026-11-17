//
// Copyright © Agulhas Labs
//

import Foundation

/// A runner whose test passed and whose one failure was `xcodebuild` saving its result bundle afterwards (SimWalk#289).
///
/// Seen on iOS 27.0 simulators, walks and dry runs alike: every screen captured, then `xcodebuild` exits non-zero printing `Error saving invocation record to resultBundlePath:… failed to import activity log, underlying error: fileSystemFailure(reason: "mkstemp: No such file or directory")`. The walk is whole; only `xcodebuild`'s own record of it is missing, so it is said as that rather than as a runner failure the answer survived.
struct ResultBundleSaveFailure {
    /// What `xcodebuild` prints when it cannot save the result bundle, as measured.
    static var signature: String {
        "Error saving invocation record to resultBundlePath"
    }

    /// The save failure's reason, cut short, when it is the run's only failure; `nil` otherwise.
    ///
    /// Only on positive evidence from `xcodebuild`'s own output that `test` ran and passed: its `Test Case '…test]' passed` line, and no test case failed, no failing-tests summary and no restart after a crash. Output cut off at the drain limit is no evidence either way.
    static func only(in result: Shell.Result, test: String) -> String? {
        guard !result.truncated else { return nil }
        let lines = (result.standardOutput + "\n" + result.standardError).split(separator: "\n").map(String.init)
        guard let saveLine = lines.first(where: { $0.contains(signature) }) else { return nil }
        let passed = lines.contains { $0.hasPrefix("Test Case '") && $0.contains(" \(test)]' passed") }
        let failed = lines.contains { line in
            (line.hasPrefix("Test Case '") && line.contains("' failed")) || line.hasPrefix("Failing tests:") || line.hasPrefix("Restarting after unexpected exit")
        }
        guard passed, !failed else { return nil }
        return reason(of: saveLine)
    }

    /// The innermost `reason: "…"` the line quotes — `mkstemp: No such file or directory` — or the line after the signature, cut to a readable length.
    static func reason(of line: String) -> String {
        if let start = line.range(of: "reason: \""), let end = line[start.upperBound...].firstIndex(of: "\"") {
            return String(line[start.upperBound ..< end])
        }
        let rest = line.components(separatedBy: signature).last?.drop { $0 == ":" || $0 == " " } ?? Substring(line)
        return rest.count > 120 ? "\(rest.prefix(120))…" : String(rest)
    }
}
