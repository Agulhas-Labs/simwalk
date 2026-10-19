//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// One mirror call at a time per Mac: an exclusive `flock` on `~/.simwalk/mirror/.lock`, held for a call's whole length (Brief §8).
///
/// There is one phone and one Mirroring window, so two agents' calls would interleave their events — one's tap landing in the middle of the other's drag. The lock is an ``ExclusiveFileLock``, which the system drops when its holder dies, so a call killed mid-way cannot wedge the next.
public struct MirrorCallLock: Sendable {
    /// The lock file, `<root>/mirror/.lock`.
    public let file: URL

    /// The lock under `root` — `~/.simwalk` on a Mac, a scratch directory in a test.
    public init(root: URL) {
        file = root.appendingPathComponent("mirror", isDirectory: true).appendingPathComponent(".lock")
    }

    /// The machine's own lock, under the account home's `.simwalk` (``HomeDirectories/account()``) as the lease store is — never moved by `HOME` or any other environment variable, since a lock a second caller could not see would not keep its events apart.
    public static func standard() -> MirrorCallLock {
        MirrorCallLock(root: HomeDirectories.account())
    }

    /// Runs `body` holding the lock, waiting for a call already holding it to finish; the directory is made first, since the lock file's own create does not make it.
    public func withLock<Value>(_ body: () throws -> Value) throws -> Value {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ExclusiveFileLock(file: file).withLock(body)
    }
}
