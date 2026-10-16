//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The segment file dropped into sift's status-line directory: written once, left alone on a re-run, repointed when the binary moves, and removed only when it is ours.
struct StatuslineSegmentsTests {
    @Test
    func theShimIsWrittenExecutableAndRunsThisBinarysStatusline() throws {
        let directory = try TemporaryDirectory()
        let segments = StatuslineSegments(directory: directory.url.appendingPathComponent("statusline.d", isDirectory: true))

        let outcome = try segments.install(executable: "/Users/x/.local/bin/simwalk")
        let script = try String(contentsOf: segments.fileURL, encoding: .utf8)

        #expect(outcome == .written)
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("exec \"/Users/x/.local/bin/simwalk\" statusline"))
        #expect(FileManager.default.isExecutableFile(atPath: segments.fileURL.path))
    }

    /// Re-running the installer is the upgrade path, so an unchanged path has to be free rather than a rewrite reported as work.
    @Test
    func asecondInstallAtTheSamePathChangesNothing() throws {
        let directory = try TemporaryDirectory()
        let segments = StatuslineSegments(directory: directory.url)

        _ = try segments.install(executable: "/Users/x/.local/bin/simwalk")

        #expect(try segments.install(executable: "/Users/x/.local/bin/simwalk") == .unchanged)
    }

    @Test
    func amovedBinaryIsRepointedRatherThanLeftStale() throws {
        let directory = try TemporaryDirectory()
        let segments = StatuslineSegments(directory: directory.url)

        _ = try segments.install(executable: "/opt/simwalk")
        let outcome = try segments.install(executable: "/Users/x/.local/bin/simwalk")
        let script = try String(contentsOf: segments.fileURL, encoding: .utf8)

        #expect(outcome == .written)
        #expect(script.contains("/Users/x/.local/bin/simwalk"))
        #expect(!script.contains("/opt/simwalk\" statusline"))
    }

    /// A file that lost its executable bit is a status line that silently lost half of itself, so it is rewritten rather than reported as already there.
    @Test
    func afileThatIsNoLongerExecutableIsWrittenAgain() throws {
        let directory = try TemporaryDirectory()
        let segments = StatuslineSegments(directory: directory.url)
        _ = try segments.install(executable: "/Users/x/.local/bin/simwalk")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: segments.fileURL.path)

        #expect(try segments.install(executable: "/Users/x/.local/bin/simwalk") == .written)
        #expect(FileManager.default.isExecutableFile(atPath: segments.fileURL.path))
    }

    @Test
    func removalTakesOurOwnShimAndNothingElse() throws {
        let directory = try TemporaryDirectory()
        let segments = StatuslineSegments(directory: directory.url)

        #expect(try segments.remove() == .absent)
        _ = try segments.install(executable: "/Users/x/.local/bin/simwalk")
        #expect(try segments.remove() == .removed)
        #expect(!FileManager.default.fileExists(atPath: segments.fileURL.path))

        try Data("#!/bin/sh\necho hello\n".utf8).write(to: segments.fileURL)

        #expect(try segments.remove() == .notOurs)
        #expect(FileManager.default.fileExists(atPath: segments.fileURL.path))
    }
}
