//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation

/// Whether Claude Code's own CLI is there to register with, and the runner that drives it.
///
/// The registration itself is the shared library's (`ClaudeMcpInstall`): `claude` owns its file format, and the library reads that file back to confirm what `claude mcp add` did.
struct ClaudeCommandLine {
    /// The runner for the `claude` on `environment`'s PATH, or `nil` when there is none.
    ///
    /// A PATH walk rather than a `which` subprocess: the question is exactly "would running `claude` find something", and asking a shell to answer it costs a process and can be answered by a function or an alias this tool could not then execute. It decides the install's shape: without `claude` the runner is still installed and every Claude Code registration is skipped together.
    static func runner(environment: [String: String] = ProcessInfo.processInfo.environment) -> (any ClaudeMcpRunner)? {
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("claude").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return ClaudeCLI(environment: environment)
            }
        }
        return nil
    }
}
