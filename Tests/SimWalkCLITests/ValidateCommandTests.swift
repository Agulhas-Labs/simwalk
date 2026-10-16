//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `validate`'s own half of the usage contract: what a failure it did not expect is recorded as.
struct ValidateCommandTests {
    /// A failure no error type classifies is this command's own code over a walkbook it has already loaded — `tool-error`, never a caller's mistake and never no kind at all.
    ///
    /// The walkbook argument's own failures are `WalkbookLoadError`s, which carry their own.
    @Test
    func anunmappedFailureIsRecordedAsToolError() throws {
        struct Unmapped: Error {}
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try ValidateCommand.parse(["book.json"]).run(log: log, emit: recorder.emit, emitError: recorder.emitError) { throw Unmapped() }
        }

        let entry = try #require(try UsageReport.entries(at: log.fileURL).entries.first)
        #expect(entry.tool == "validate")
        #expect(entry.kind == .toolError)
    }

    /// The default never stands in for a kind the error carries: a walkbook that is not there is the caller's own argument.
    @Test
    func amissingWalkbookIsStillInputRefused() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let command = try ValidateCommand.parse([directory.url.appendingPathComponent("absent.json").path])
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try command.run(log: log, emit: recorder.emit, emitError: recorder.emitError) { try command.answer() }
        }

        #expect(try UsageReport.entries(at: log.fileURL).entries.first?.kind == .inputRefused)
    }
}
