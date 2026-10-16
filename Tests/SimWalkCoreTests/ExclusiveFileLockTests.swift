//
// Copyright © Agulhas Labs
//

import Foundation
import os
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `ExclusiveFileLock`'s release, against a copy of its descriptor still open elsewhere.
struct ExclusiveFileLockTests {
    /// The lock is free once `withLock` returns even while a copy of its descriptor is still open — as a child another thread is spawning holds one until its exec (SimWalk#71), which a close alone would leave holding the lock.
    @Test
    func theLockIsFreeOnReturnWhileACopyOfItsDescriptorIsStillOpen() throws {
        let directory = try TemporaryDirectory()
        let copy = OSAllocatedUnfairLock<Int32>(initialState: -1)
        var lock = ExclusiveFileLock(file: directory.url.appendingPathComponent("book", isDirectory: true))
        try FileManager.default.createDirectory(at: lock.file, withIntermediateDirectories: true)
        lock.takeLock = { descriptor, operation in
            copy.withLock { $0 = dup(descriptor) }
            return flock(descriptor, operation)
        }

        try lock.withLock {}
        defer { close(copy.withLock(\.self)) }
        let fresh = open(lock.file.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        defer { close(fresh) }

        #expect(copy.withLock(\.self) >= 0)
        #expect(fresh >= 0)
        #expect(flock(fresh, LOCK_EX | LOCK_NB) == 0)
    }
}
