//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkDriver

/// Where the install takes the runner from, and which binary it pairs it with — the machine's own checkout and binary in use, a scratch repository in a test.
struct RunnerSnapshotSource {
    /// The checkout the runner is copied out of, or `nil` for a packaged build, which has none and installs only the tree shipped beside the binary.
    let checkout: URL?
    /// The SHA-256 of the binary being installed, as it was launched; `nil` when it could not be read.
    let binaryHash: String?
    /// Spawns `git`.
    let run: (String, [String]) throws -> Shell.Result
    /// Whether to replace a runner this binary is already paired with (`--repoint-runner`).
    var repoint = false
    /// The running binary, symlinks resolved — which decides whether it is a development build, and so whether the install prunes, and where the shipped runner tree would be; `nil` when unknown.
    var executable: URL?
}
