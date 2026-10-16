//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `note(session:arguments:workingDirectory:)` retries once when it loses the race with ``CallAttribution/pruneSlips()``'s `rmdir` — which can remove a session directory it judges empty and stale between `note`'s own `createDirectory` and its write — rather than dropping the slip silently (SimWalk#37 item 5).
struct CallAttributionTests {
    @Test
    func anrmdirBetweenCreateAndWriteIsSurvivedByOneRetry() throws {
        let directory = try TemporaryDirectory()
        let root = directory.url
        let sessionDirectory = root.appendingPathComponent("s1", isDirectory: true)
        // The seam ``CallAttribution`` exists for: land the race — another hook's `pruneSlips()` removing
        // this session directory — in the exact gap `note` itself cannot see, between its own
        // `createDirectory` and its first write.
        nonisolated(unsafe) var raced = false
        let attribution = CallAttribution(directory: root, environment: [:], afterFirstCreate: {
            guard !raced else { return }
            raced = true
            try? FileManager.default.removeItem(at: sessionDirectory)
        })

        attribution.note(session: "s1", arguments: ["walk", "x.json"], workingDirectory: nil)

        let names = try FileManager.default.contentsOfDirectory(atPath: sessionDirectory.path)

        #expect(names.count == 1)
        #expect(raced)
    }
}
