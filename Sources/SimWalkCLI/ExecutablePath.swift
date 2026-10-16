//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkMCP

/// Where this process's executable lives, as a registration has to spell it.
///
/// Read from the invocation rather than hard-coded, so an install to somewhere other than the conventional location registers the binary that is actually running — the alternative is a `settings.json` and an MCP entry pointing at a path that may hold nothing.
struct ExecutablePath {
    /// This process's own path.
    static var current: String {
        resolve()
    }

    /// The same answer from a stated invocation — the only way either of its branches is checkable, since a test cannot choose the process it is running in.
    ///
    /// **A bare `simwalk` is found the way a shell finds it, by searching `PATH`, and the answer is the path as `PATH` spells it — not symlink-resolved.** `brew install` links `/opt/homebrew/bin/simwalk` to `../Cellar/simwalk/<version>/bin/simwalk`; registering the link survives `brew upgrade`, where registering its target would point at a Cellar directory the upgrade removes. A guess at `~/.local/bin` would be worse than either: a packaged install never puts anything there, so the registration would name a path that holds nothing. Only when no `PATH` entry holds the name does it fall back to the running process's own executable.
    static func resolve(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processExecutable: URL? = Bundle.main.executableURL
    ) -> String {
        let argument0 = arguments.first ?? SimWalkPaths.binaryName
        if argument0.contains("/") {
            return URL(fileURLWithPath: argument0).standardizedFileURL.path
        }
        if let found = onPath(argument0, environment: environment) {
            return found
        }
        return processExecutable?.standardizedFileURL.path ?? argument0
    }

    /// The first `<directory>/<name>` on `PATH` that is an executable regular file — a symlink counted by what it points at, but reported as itself.
    ///
    /// Empty and relative entries are skipped: the first means the working directory, the second depends on it, and neither names one place for a hook's shell to find later.
    private static func onPath(_ name: String, environment: [String: String]) -> String? {
        let manager = FileManager.default
        for directory in (environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: false) where directory.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).standardizedFileURL
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue, manager.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }

    /// The conventional install location, `~/.local/bin/simwalk` — where a deploy puts the binary, and so the binary whose runner a prune keeps whichever binary runs it (SimWalk#22).
    static func installed(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/bin/\(SimWalkPaths.binaryName)")
    }
}
