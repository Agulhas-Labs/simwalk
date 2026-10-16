//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A reader polling the progress file sees the old file or the new one, never a torn one, and the writes leave nothing beside it (`Docs/SIMWALK-PROGRESS.md` §3).
struct ProgressWriterAtomicityTests {
    /// A large state written many times while another thread reads and decodes it in a loop: a write in place would hand that reader a truncated or half-written file within a few hundred writes.
    @Test
    func aConcurrentReaderNeverSeesATornFileAndNoTemporaryIsLeft() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let writer = ProgressWriter(url: url, clock: { Date() }, pid: 1, minInterval: 0)
        writer.begin(tool: "walk")
        let tally = ReadTally()
        let reading = DispatchGroup()
        DispatchQueue.global().async(group: reading) {
            Self.readUntilStopped(url, into: tally)
        }
        for index in 1 ... 400 {
            writer.commit { $0.lastScreenshotPath = String(repeating: "\(index % 10)", count: 200_000 + index) }
        }
        tally.stop()
        reading.wait()
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        #expect(tally.decoded > 0)
        #expect(tally.torn == 0)
        #expect(left == ["s.json"])
    }

    private static func readUntilStopped(_ url: URL, into tally: ReadTally) {
        while !tally.isStopped {
            guard let data = try? Data(contentsOf: url) else { continue }
            let progress = try? WalkProgress.decoder().decode(WalkProgress.self, from: data)
            tally.count(decoded: progress != nil)
        }
    }
}

extension ProgressWriterAtomicityTests {
    /// What the reader thread saw, shared with the test thread.
    final class ReadTally: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        private var decodedReads = 0
        private var tornReads = 0

        var isStopped: Bool {
            lock.withLock { stopped }
        }

        var decoded: Int {
            lock.withLock { decodedReads }
        }

        var torn: Int {
            lock.withLock { tornReads }
        }

        func stop() {
            lock.withLock { stopped = true }
        }

        func count(decoded: Bool) {
            lock.withLock {
                if decoded {
                    decodedReads += 1
                } else {
                    tornReads += 1
                }
            }
        }
    }
}
