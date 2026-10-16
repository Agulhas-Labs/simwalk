//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkDriver

/// The binary this process was launched from, identified by its bytes — which is how a walk finds the runner snapshot installed with it (SimWalk#16).
///
/// **Hashed once, as the process starts, and never again.** A Claude Code session keeps `simwalk mcp` running for hours, and a deploy removes the file and copies a new one to the same path under it. Hashing the path at walk time would then name the *new* binary while the old code ran — pairing the old CLI with the new runner, the skew the snapshot exists to prevent. So the two verbs that build a runner, `mcp` and `walk`, ask for this as they start, and every later question gets that first answer.
struct LaunchedBinary {
    /// This process's identity, taken the first time anything asks.
    static let launched = Identity(url: Bundle.main.executableURL?.resolvingSymlinksInPath())

    /// The running executable's path, symlinks resolved.
    static var url: URL? {
        launched.url
    }

    /// Its SHA-256 as first read, or `nil` when it could not be read.
    static var hash: String? {
        launched.hash
    }

    /// Takes the hash now, before a deploy can replace the file under this process.
    static func capture() {
        _ = launched
    }
}

extension LaunchedBinary {
    /// A binary's path and the hash of its bytes as they were when this was made — a value, so a file replaced afterwards does not change what it says.
    struct Identity: Equatable, Sendable {
        let url: URL?
        let hash: String?

        init(url: URL?) {
            self.url = url
            hash = url.flatMap(RunnerProject.hash(ofExecutableAt:))
        }
    }
}
