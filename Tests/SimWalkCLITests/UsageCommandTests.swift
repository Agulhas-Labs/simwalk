//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// The one verb that reads the log instead of writing to it.
struct UsageCommandTests {
    @Test
    func thereportIsWrittenForTheLogItWasPointedAt() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 3, succeeded: true)
        let recorder = StreamRecorder()

        try UsageCommand.parse(["--log", log.fileURL.path]).run(emit: recorder.emit, emitError: recorder.emitError, saltFile: Self.salt(in: directory))

        let answer = try #require(recorder.out.first)

        #expect(answer.contains("calls: 1"))
        #expect(answer.contains("ok — 0 failures across 1 call"))
        #expect(answer.contains("validate      1   p50 3ms   p90 3ms"))
        #expect(recorder.err.isEmpty)
    }

    /// A report that declares its own malformed lines exits on that declaration, because it goes through `TimedCall` like every other verb rather than around it.
    @Test
    func areportShortByAtornLineExitsTwo() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 3, succeeded: true)
        let handle = try FileHandle(forWritingTo: log.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"ms":1,"#.utf8))
        try handle.close()
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try UsageCommand.parse(["--log", log.fileURL.path]).run(emit: recorder.emit, emitError: recorder.emitError, saltFile: Self.salt(in: directory))
        })

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.out.first?.contains("qualified — 1 malformed line skipped · 0 failures across 1 call") == true)
    }

    /// A log that cannot be read refuses through the same path every other verb refuses through: stderr, the verdict's three words, exit 1.
    @Test
    func alogThatCannotBeReadRefusesOnStderr() throws {
        let directory = try TemporaryDirectory()
        let path = directory.url.appendingPathComponent("usage.jsonl")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try UsageCommand.parse(["--log", path.path]).run(emit: recorder.emit, emitError: recorder.emitError, saltFile: Self.salt(in: directory))
        })

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.hasPrefix("refused — \(path.path): ") == true)
    }

    /// Reading the log must not add to it, or a machine whose usage is checked daily would report checking as its most-used verb.
    @Test
    func readingTheLogDoesNotAppendToIt() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 3, succeeded: true)
        let recorder = StreamRecorder()

        try UsageCommand.parse(["--log", log.fileURL.path]).run(emit: recorder.emit, emitError: recorder.emitError, saltFile: Self.salt(in: directory))

        #expect(try UsageReport.entries(at: log.fileURL).entries.count == 1)
    }

    /// Failure reasons are pseudonymised unless the caller asks otherwise — a report is built to be pasted, and a reason quotes whatever the call was pointed at.
    @Test
    func reasonsArePseudonymisedByDefaultAndPrintedUnderUnredact() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "/private/example.json", milliseconds: 3, succeeded: false, err: "the walk did not complete: /private/example.json crashed", kind: .runnerFailed)
        let redacted = StreamRecorder()
        let unredacted = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try UsageCommand.parse(["--log", log.fileURL.path]).run(emit: redacted.emit, emitError: redacted.emitError, saltFile: Self.salt(in: directory))
        }
        #expect(throws: ExitCode.self) {
            try UsageCommand.parse(["--log", log.fileURL.path, "--unredact"]).run(emit: unredacted.emit, emitError: unredacted.emitError, saltFile: Self.salt(in: directory))
        }

        let shared = try #require(redacted.out.first)
        let owned = try #require(unredacted.out.first)
        #expect(!shared.contains("/private/example.json crashed"))
        #expect(shared.contains("reason-"))
        #expect(owned.contains("1  the walk did not complete: /private/example.json crashed"))
        #expect(!owned.contains("reason-"))
    }

    /// `--since` narrows the report to the window it names, and the header says which window that is.
    @Test
    func sinceNarrowsTheReportAndTheHeaderSaysSo() throws {
        let directory = try TemporaryDirectory()
        let old = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let recent = UsageLog(directory: directory.url, now: { Date() })
        old.record(tool: "walk", target: "a.json", milliseconds: 3, succeeded: false, err: "the walk did not complete: crash", kind: .runnerFailed)
        recent.record(tool: "validate", target: "book.json", milliseconds: 3, succeeded: true)
        let recorder = StreamRecorder()

        try UsageCommand.parse(["--log", old.fileURL.path, "--since", "3d"]).run(emit: recorder.emit, emitError: recorder.emitError, saltFile: Self.salt(in: directory))

        let answer = try #require(recorder.out.first)

        #expect(answer.contains("window: 3d from "))
        #expect(answer.contains("calls: 1 of 2"))
        #expect(answer.contains("ok — 0 failures across 1 call"))
    }

    /// A window spelled some other way is refused while the arguments are parsed, saying what would be accepted.
    ///
    /// `-3d` is in the list deliberately: it starts with `-`, so without `parsing: .unconditional` ArgumentParser reads it as an unrecognised option and reports its own "Missing value for '--since'" — never reaching `UsageCommand.window`, and never saying what a caller should have written instead.
    @Test
    func asinceThatNamesNoWindowIsRefused() {
        for spelling in ["3", "3w", "0d", "d", "1.5d", "-3d"] {
            let thrown = #expect(throws: (any Error).self) {
                try UsageCommand.parse(["--since", spelling])
            }

            #expect(thrown.map { UsageCommand.message(for: $0) }?.contains("such as 3d or 12h") == true, "\(spelling)")
        }
    }

    private static func salt(in directory: TemporaryDirectory) -> URL {
        directory.url.appendingPathComponent("redaction-salt")
    }

    /// `--log` alone, with no `SIMWALK_USAGE_LOG` and no explicit `saltFile:` override, still keeps the salt beside the log it names — the default used to be `Redactor.defaultSaltFile`, bound to the standard log's own directory regardless of what `--log` said.
    @Test
    func thesaltFollowsDashLogEvenWithNoOverrideAnywhere() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "crash", kind: .runnerFailed)
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try UsageCommand.parse(["--log", log.fileURL.path]).run(emit: recorder.emit, emitError: recorder.emitError)
        }

        #expect(FileManager.default.fileExists(atPath: Self.salt(in: directory).path))
    }

    /// A log with nothing that failed must not create the salt merely because `usage` ran without `--unredact`.
    @Test
    func thesaltIsNotCreatedOverALogWithNoFailures() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)
        let recorder = StreamRecorder()

        try UsageCommand.parse(["--log", log.fileURL.path]).run(emit: recorder.emit, emitError: recorder.emitError, saltFile: Self.salt(in: directory))

        #expect(!FileManager.default.fileExists(atPath: Self.salt(in: directory).path))
    }

    /// The header's log path is redacted to a bare basename when the log sits outside home and the caller did not ask for `--unredact` — the same overclaiming help text said a redacted report was "safe to share unless you say otherwise" while this path still printed in full.
    @Test
    func theHeaderRedactsTheLogPathUnlessUnredacted() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        log.record(tool: "validate", target: "book.json", milliseconds: 1, succeeded: true)
        let redacted = StreamRecorder()
        let unredacted = StreamRecorder()

        try UsageCommand.parse(["--log", log.fileURL.path]).run(emit: redacted.emit, emitError: redacted.emitError, saltFile: Self.salt(in: directory))
        try UsageCommand.parse(["--log", log.fileURL.path, "--unredact"]).run(emit: unredacted.emit, emitError: unredacted.emitError, saltFile: Self.salt(in: directory))
        let redactedAnswer = try #require(redacted.out.first)
        let unredactedAnswer = try #require(unredacted.out.first)

        #expect(redactedAnswer.hasPrefix("log: \(log.fileURL.lastPathComponent)  (path redacted — outside home)"))
        #expect(!redactedAnswer.contains(directory.url.path))
        #expect(unredactedAnswer.hasPrefix("log: \(log.fileURL.path)"))
    }
}
