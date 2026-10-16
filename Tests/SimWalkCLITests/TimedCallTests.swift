//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// The CLI contract the README states, pinned: answers on stdout, refusals on stderr, the exit code the answer's own verdict names, one log line either way — and a log that cannot be written changing none of the other three.
struct TimedCallTests {
    @Test
    func ananswerGoesToStdoutAndIsLoggedAsASuccess() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        try TimedCall.run(tool: "validate", target: "book.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError) {
            Self.answer
        }

        #expect(recorder.out == [Self.answer.text])
        #expect(recorder.err.isEmpty)
        let entry = try #require(try Self.entries(in: directory).first)
        #expect(entry.succeeded)
        #expect(entry.tool == "validate")
        #expect(entry.target == "book.json")
        #expect(entry.error == nil)
    }

    /// A refusal is a verdict like any other, so it is written in the same three words the other two are — `refused — <reason>` — rather than as a bare error description that reads as a crash.
    @Test
    func aRefusalGoesToStderrExitsNonZeroAndIsLoggedWithItsReason() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let refusal = WalkbookLoadError.unreadable(source: "/absent.json", reason: "no such file")

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "validate", target: "/absent.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError, isStdoutPiped: Self.notPiped) {
                throw refusal
            }
        })

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err == ["refused — \(refusal.description)"])
        let entry = try #require(try Self.entries(in: directory).first)
        #expect(!entry.succeeded)
        #expect(entry.error == refusal.description)
    }

    /// SimWalk#40: a pipeline's status is its last command's, so `simwalk walk … | tail` reports `tail`'s exit over a refusal's — the one place that still reaches the caller is stderr, which a pipe never captures.
    @Test
    func apipedRefusalAddsTheExitCodeToStderrSincePipestatusIsWhatSurvives() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let refusal = WalkbookLoadError.unreadable(source: "/absent.json", reason: "no such file")

        #expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "validate", target: "/absent.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError, isStdoutPiped: Self.piped) {
                throw refusal
            }
        }

        #expect(recorder.err == [
            "refused — \(refusal.description)",
            "exit 1 — read ${PIPESTATUS[0]} (bash) / ${pipestatus[1]} (zsh), not $?",
        ])
    }

    /// A failure's kind is read off the thrown error, the same value `UsageFailureKind.of(_:)` answers — this is the one call site that has to actually do that reading, not just be able to.
    @Test
    func arefusalsKindIsReadOffTheThrownErrorAndRecorded() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "validate", target: "/absent.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError) {
                throw WalkbookLoadError.unreadable(source: "/absent.json", reason: "no such file")
            }
        }

        let entry = try #require(try Self.entries(in: directory).first)
        #expect(entry.kind == .inputRefused)
    }

    /// An error from a site nothing has mapped records the call site's own default — never no kind at all, which `simwalk usage` would read back as `unclassified`.
    ///
    /// Every call site states one: there is no default for a call site to forget.
    ///
    /// (This used to pin the opposite — a call site with no default recording no kind — which is the gap the required parameter now closes.)
    @Test
    func anunmappedRefusalRecordsItsCallSitesDefaultRatherThanNoKind() throws {
        struct Unmapped: Error, CustomStringConvertible {
            var description: String {
                "something this codebase has never classified"
            }
        }
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "validate", target: "book.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError) {
                throw Unmapped()
            }
        }

        let entry = try #require(try Self.entries(in: directory).first)
        #expect(entry.kind == .toolError)
    }

    /// An error from a site nothing has mapped falls back to the call site's own default when it names one — `install-hook`, `uninstall-hook` and `walk` each know what an error their own internals did not classify means, and record that rather than leaving `simwalk usage` to call it `unclassified`.
    @Test
    func arefusalWithADefaultKindFallsBackToItWhenNothingIsMapped() throws {
        struct Unmapped: Error, CustomStringConvertible {
            var description: String {
                "something this codebase has never classified"
            }
        }
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "install-hook", target: nil, log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .setupFailed) {
                throw Unmapped()
            }
        }

        let entry = try #require(try Self.entries(in: directory).first)
        #expect(entry.kind == .setupFailed)
    }

    /// The default never overrides an error that already has an opinion — it is a fallback for the gap, not a floor under every unmapped-looking call.
    @Test
    func adefaultKindNeverOverridesAnErrorThatIsAlreadyClassified() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "walk", target: "book.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .runnerFailed) {
                throw WalkbookLoadError.unreadable(source: "/absent.json", reason: "no such file")
            }
        }

        let entry = try #require(try Self.entries(in: directory).first)
        #expect(entry.kind == .inputRefused)
    }

    /// A qualified answer is printed and logged exactly as a clean one is; only the exit code differs, and it is read off the verdict rather than decided by the command.
    @Test
    func aQualifiedAnswerIsStillPrintedAndLoggedAndExitsTwo() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let qualified = Answer(header: "walkbook: abcd1234", verdict: .qualified(["1 screen unreachable"], detail: "0 of 1 screens captured"))

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "walk", target: "book.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError, isStdoutPiped: Self.notPiped) {
                qualified
            }
        })

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.out == [qualified.text])
        #expect(recorder.err.isEmpty)
        #expect(try Self.entries(in: directory).first?.succeeded == true)
    }

    /// The same nudge for a qualified answer, not just a refusal: `walk`'s own exit 2 is the one `$?` loses to `tail` too.
    @Test
    func apipedQualifiedAnswerAddsTheExitCodeToStderr() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let qualified = Answer(header: "walkbook: abcd1234", verdict: .qualified(["1 screen unreachable"], detail: "0 of 1 screens captured"))

        #expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "walk", target: "book.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError, isStdoutPiped: Self.piped) {
                qualified
            }
        }

        #expect(recorder.out == [qualified.text])
        #expect(recorder.err == ["exit 2 — read ${PIPESTATUS[0]} (bash) / ${pipestatus[1]} (zsh), not $?"])
    }

    /// What the answer stood in for is what the log records, so a report over a month of lines prices the same calls the answers did.
    @Test
    func ameasuredAnswerRecordsWhatItStoodInForOnItsLogLine() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()
        let measured = Answer(
            header: "build: abcd1234",
            verdict: .unqualified("1 of 1 screens captured · 1 capture"),
            weighing: ContextSaving(screenshotTokens: [4070, 4070], treeBytes: 40000, servedBytes: 0)
        )

        try TimedCall.run(tool: "bundle inspect", target: "x.simwalk", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError) {
            measured
        }

        let entry = try #require(try Self.entries(in: directory).first)

        #expect(entry.screenshots == 2)
        #expect(entry.imageTokens == 8140)
        #expect(entry.treeBytes == 40000)
        #expect(entry.answerBytes == measured.saving?.servedBytes)
        #expect(entry.tokensSaved == measured.saving?.savedTokens)
    }

    /// An answer that stood in for nothing records nothing, rather than a saving of zero: an absence and a zero are different claims, and only one of them is true of a validation.
    @Test
    func ananswerThatStoodInForNothingRecordsNoMeasurement() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        try TimedCall.run(tool: "validate", target: "book.json", log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError) {
            Self.answer
        }

        let entry = try #require(try Self.entries(in: directory).first)

        #expect(entry.screenshots == nil)
        #expect(entry.imageTokens == nil)
        #expect(entry.treeBytes == nil)
        #expect(entry.answerBytes == nil)
        #expect(entry.tokensSaved == nil)
    }

    @Test
    func aLogThatCannotBeWrittenChangesNeitherTheOutputNorTheExit() throws {
        let recorder = StreamRecorder()
        let unwritable = UsageLog(directory: URL(fileURLWithPath: "/dev/null/simwalk"), now: { Date(timeIntervalSince1970: 0) })

        try TimedCall.run(tool: "validate", target: nil, log: unwritable, emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError) {
            Self.answer
        }

        #expect(recorder.out == [Self.answer.text])
        #expect(recorder.err.isEmpty)
    }

    @Test
    func aLogThatCannotBeWrittenStillLetsARefusalRefuse() throws {
        let recorder = StreamRecorder()
        let unwritable = UsageLog(directory: URL(fileURLWithPath: "/dev/null/simwalk"), now: { Date(timeIntervalSince1970: 0) })

        #expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "validate", target: nil, log: unwritable, emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError, isStdoutPiped: Self.notPiped) {
                throw WalkbookLoadError.unreadable(source: "/absent.json", reason: "no such file")
            }
        }

        #expect(recorder.err.count == 1)
    }

    /// A clean answer that stands in for nothing — the shape `validate` gives.
    private static let answer = Answer(header: "walkbook: abcd1234  screens: 1  steps: 1", verdict: .unqualified("walkbook 'x' against com.example.app · 1 capture planned"))

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }

    /// Named rather than inline so `TimedCall.run`'s trailing closure stays the only closure literal at the call site (`isStdoutPiped:` and `body`/`walk` would otherwise both be literals).
    private static func piped() -> Bool {
        true
    }

    private static func notPiped() -> Bool {
        false
    }

    private static func entries(in directory: TemporaryDirectory) throws -> [UsageLog.Entry] {
        let url = directory.url.appendingPathComponent("usage.jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try JSONDecoder().decode(UsageLog.Entry.self, from: Data(line.utf8))
        }
    }
}
