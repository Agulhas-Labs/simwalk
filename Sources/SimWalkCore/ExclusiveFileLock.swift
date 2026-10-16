//
// Copyright © Agulhas Labs
//

import Foundation

/// An exclusive `flock(2)` on a lock file or a directory, held for one closure: how two processes on one machine take turns at a load-modify-write without a server between them.
///
/// **The lock is never the file it guards.** An atomic write replaces its file by rename, so a lock held on the old inode would guard nothing the next reader opens. A `file` with a directory path (``URL/hasDirectoryPath``) locks that directory, opened read-only and never created, so a lock can guard a file without leaving one of its own. Any other `file` is a lock file, created when missing and **left in place** after the unlock: removing it would let a waiter still blocked on the unlinked inode and a newcomer on a fresh one both hold it. The system drops the lock when the holder's process dies, so a holder killed mid-way cannot wedge the next.
///
/// **The lock is released by an explicit unlock before the close**, not by the close alone. A lock goes with its open file, and a close releases it only once no descriptor refers to that file — and a child any thread is spawning holds a copy of every descriptor until its exec, close-on-exec or not (SimWalk#71). Close-on-exec only keeps the copy from outliving the exec.
public struct ExclusiveFileLock: Sendable {
    public let file: URL
    /// Takes the lock (`flock(2)`'s own arguments and answer) — the seam a test holds a copy of the descriptor through, as a child another thread is spawning does until its exec (SimWalk#71).
    var takeLock: @Sendable (Int32, Int32) -> Int32 = { flock($0, $1) }

    public init(file: URL) {
        self.file = file
    }

    /// Runs `body` once the lock is held, waiting for as long as another holder keeps it, and releases it as `body` returns or throws.
    public func withLock<Value>(_ body: () throws -> Value) throws -> Value {
        let descriptor = file.hasDirectoryPath ? open(file.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC) : open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw failure()
        }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        while takeLock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw failure()
            }
        }
        return try body()
    }

    private func failure() -> Unavailable {
        Unavailable(file: file, reason: String(cString: strerror(errno)))
    }
}

public extension ExclusiveFileLock {
    /// The lock could not be opened or taken — a lock file's directory missing or not writable, or a locked directory missing, say — so nothing guarded by it ran.
    struct Unavailable: LocalizedError, Equatable, Sendable {
        public let file: URL
        public let reason: String

        public var errorDescription: String? {
            "could not lock \(file.path): \(reason)"
        }
    }
}
