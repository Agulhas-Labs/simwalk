//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
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
    /// **A bare `simwalk` is found the way a shell finds it, by searching `PATH`, and the answer is the path as `PATH` spells it — not symlink-resolved.** `brew install` links `/opt/homebrew/bin/simwalk` to `../Cellar/simwalk/<version>/bin/simwalk`; registering the link survives `brew upgrade`, where registering its target would point at a Cellar directory the upgrade removes. A guess at `~/.local/bin` would be worse than either: a packaged install never puts anything there, so the registration would name a path that holds nothing. **A `PATH` match counts only when it is the running binary** — its symlink-resolved path equals the running executable's. A shell that cached `simwalk` as one install while `brew install` put another earlier on `PATH` would otherwise register the second and pair the runner with the first's hash (SimWalk#139). Entries that hold some other `simwalk` are passed over. When no `PATH` entry is the running binary, it falls back to the running process's own executable.
    static func resolve(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processExecutable: URL? = Bundle.main.executableURL,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> String {
        let argument0 = arguments.first ?? SimWalkPaths.binaryName
        if argument0.contains("/") {
            return URL(fileURLWithPath: argument0).standardizedFileURL.path
        }
        if let found = onPath(argument0, environment: environment, running: processExecutable, workingDirectory: workingDirectory) {
            return found
        }
        return processExecutable?.standardizedFileURL.path ?? argument0
    }

    /// The first `<directory>/<name>` on `PATH` that is an executable regular file and is the running binary — a symlink counted by what it points at, but reported as itself.
    ///
    /// Empty and relative entries are skipped: the first means the working directory, the second depends on it, and neither names one place for a hook's shell to find later.
    private static func onPath(_ name: String, environment: [String: String], running: URL?, workingDirectory: URL) -> String? {
        let manager = FileManager.default
        let runningPath = running?.resolvingSymlinksInPath().path
        for directory in (environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: false) where directory.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: String(directory), relativeTo: workingDirectory).appendingPathComponent(name).standardizedFileURL
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue, manager.isExecutableFile(atPath: candidate.path),
               runningPath == nil || candidate.resolvingSymlinksInPath().path == runningPath
            {
                return candidate.path
            }
        }
        return nil
    }

    /// The conventional install location, `~/.local/bin/simwalk` — where a deploy puts the binary, and so the binary whose runner a prune keeps whichever binary runs it (SimWalk#22).
    static func installed(home: URL = HomeDirectories.user()) -> URL {
        home.appendingPathComponent(".local/bin/\(SimWalkPaths.binaryName)")
    }
}
