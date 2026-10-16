//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A run ending with its result (`Docs/SIMWALK-PROGRESS.md` §3): the result file first, then the terminal write naming it.
struct ProgressWriterResultTests {
    /// The writer reads its clock inside every write, before the progress bytes exist — so the clock sees what was on disk at the moment the terminal state was written.
    @Test
    func theResultFileExistsWhenTheProgressFileFirstNamesIt() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resultURL = ProgressLocation.resultURL(session: "s", in: directory)
        let probe = ResultProbe(resultURL)
        let writer = ProgressWriter(url: ProgressLocation.progressURL(session: "s", in: directory), clock: probe.read, pid: 1)
        writer.begin(tool: "walk")
        let result = WalkResultCodingTests.exampleValue()
        let readsBefore = probe.seen.count
        writer.finish(writing: result, to: resultURL, as: .done)
        let progress = try ProgressWriterTests.read(writer.url)
        let written = try WalkResult.decoder().decode(WalkResult.self, from: Data(contentsOf: resultURL))

        #expect(probe.seen.prefix(readsBefore).allSatisfy { !$0 })
        #expect(Array(probe.seen.dropFirst(readsBefore)) == [true])
        #expect(progress.phase == .done)
        #expect(progress.resultPath == resultURL.path)
        #expect(written == result)
    }

    @Test
    func aResultThatCannotBeWrittenStillEndsTheRunWithNoResultPath() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("file")
        try Data().write(to: blocker)
        let writer = ProgressWriter(url: directory.appendingPathComponent("s.json"), clock: { Date(timeIntervalSince1970: 1_790_931_600) }, pid: 1)
        writer.begin(tool: "walk")
        writer.finish(writing: WalkResultCodingTests.exampleValue(), to: blocker.appendingPathComponent("s.result.json"), as: .failed, error: "runner exited 65")
        let progress = try ProgressWriterTests.read(writer.url)

        #expect(progress.phase == .failed)
        #expect(progress.error == "runner exited 65")
        #expect(progress.resultPath == nil)
    }
}

extension ProgressWriterResultTests {
    /// A fixed clock that records, each time it is read, whether the result file exists.
    final class ResultProbe: @unchecked Sendable {
        private let lock = NSLock()
        private let url: URL
        private var observations: [Bool] = []

        init(_ url: URL) {
            self.url = url
        }

        var seen: [Bool] {
            lock.withLock { observations }
        }

        var read: @Sendable () -> Date {
            { [self] in
                let exists = FileManager.default.fileExists(atPath: url.path)
                lock.withLock { observations.append(exists) }
                return Date(timeIntervalSince1970: 1_790_931_600)
            }
        }
    }
}
