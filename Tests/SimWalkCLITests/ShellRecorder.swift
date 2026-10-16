//
// Copyright © Agulhas Labs
//

import SimWalkDriver

/// Stands in for a child process, recording what it was asked to run.
///
/// What this tool asks of `claude` is a command line, and the two things most easily got wrong about it are invisible from watching an install succeed: that the removal comes first, and that `--scope` sits before the `--`. Both are only checkable by looking at the vector, which is why running a process is a seam rather than a call.
final class ShellRecorder {
    private(set) var invocations: [(executable: String, arguments: [String])] = []
    private var results: [Shell.Result]

    /// `results` are handed back in order; anything past the end succeeds.
    init(results: [Shell.Result] = []) {
        self.results = results
    }

    var run: (String, [String]) throws -> Shell.Result {
        { [self] executable, arguments in
            invocations.append((executable, arguments))
            guard !results.isEmpty else {
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }
            return results.removeFirst()
        }
    }

    /// Just the argument vectors, which is what the assertions are about.
    var vectors: [[String]] {
        invocations.map(\.arguments)
    }
}
