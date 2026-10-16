//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkTestSupport
import Testing

/// `isPipe` is what keeps the `PIPESTATUS` nudge off a redirect to a file, where `$?` is correct (SimWalk#114).
struct StandardStreamsTests {
    @Test
    func bothEndsOfAPipeArePipes() {
        var ends: [Int32] = [0, 0]
        #expect(pipe(&ends) == 0)
        defer { close(ends[0])
            close(ends[1])
        }

        #expect(StandardStreams.isPipe(ends[0]))
        #expect(StandardStreams.isPipe(ends[1]))
    }

    @Test
    func aRegularFileIsNotAPipe() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("out.txt")
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        #expect(!StandardStreams.isPipe(handle.fileDescriptor))
    }

    @Test
    func devNullIsNotAPipe() throws {
        let handle = try #require(FileHandle(forWritingAtPath: "/dev/null"))
        defer { try? handle.close() }

        #expect(!StandardStreams.isPipe(handle.fileDescriptor))
    }

    @Test
    func aClosedDescriptorIsNotAPipe() {
        #expect(!StandardStreams.isPipe(-1))
    }
}
