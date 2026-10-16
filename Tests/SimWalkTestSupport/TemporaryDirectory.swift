//
// Copyright © Agulhas Labs
//

import Foundation

/// A scratch directory that removes itself when the test that made it goes out of scope.
///
/// A class rather than a struct so `deinit` is the cleanup — bundle tests write real directories, and a leaked one would leave the next run reading the previous run's bytes.
///
/// One target rather than a copy in each test target: both suites write real directories, and a fix to the cleanup — a directory a test left read-only, say — has to land once or the two copies drift apart while each still compiles.
public final class TemporaryDirectory {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simwalk-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
