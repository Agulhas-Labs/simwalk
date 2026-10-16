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

    /// The same answer from a stated invocation — the only way either of its two branches is checkable, since a test cannot choose the process it is running in.
    static func resolve(
        arguments: [String] = CommandLine.arguments,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let argument0 = arguments.first ?? SimWalkPaths.binaryName
        if argument0.contains("/") {
            return URL(fileURLWithPath: argument0).standardizedFileURL.path
        }
        // Resolved through PATH, so there is no path here to standardise — record the conventional install
        // location rather than a bare name, which a hook's shell could resolve to something else entirely.
        return installed(home: home).path
    }

    /// The conventional install location, `~/.local/bin/simwalk` — where a deploy puts the binary, and so the binary whose runner a prune keeps whichever binary runs it (SimWalk#22).
    static func installed(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/bin/\(SimWalkPaths.binaryName)")
    }
}
