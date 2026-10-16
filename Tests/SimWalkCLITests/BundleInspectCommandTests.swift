//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle inspect`'s exit code, which had no reference at all until the verdict was made a value.
///
/// It printed a bundle's shortfall and its unsettled captures and exited 0 over both — indistinguishable from a clean bundle to anything not parsing stdout, on the one verb most likely to be pointed at a bundle nobody watched being written.
struct BundleInspectCommandTests {
    /// A bundle holding everything its walk asked for is a clean answer, and a clean answer exits 0.
    @Test
    func acompleteBundleExitsZero() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory)
        let recorder = StreamRecorder()

        try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        #expect(recorder.out.count == 1)
        let answer = try #require(recorder.out.first)

        #expect(answer.contains("ok — 1 of 1 screens captured · 1 capture"))
        // The on-disk half survives the reshaping: the manifest answers "what happened" and this answers
        // "what is here now", and they are the same answer only while someone is watching the walk.
        #expect(answer.contains("on disk — "))
        #expect(answer.contains("  progress — 1 capture, "))
        #expect(recorder.err.isEmpty)
    }

    /// The setup the host recorded after its handback is the one line `inspect` gives it, with a command it could not run under it — the record read a week later, which the walk's own answer is not.
    @Test
    func asetupRecordedInTheManifestIsPrintedWithWhatWasNotHandedBack() throws {
        let directory = try TemporaryDirectory()
        let record = CaptureManifest.SetupRecord(made: ["privacy grant location"], handedBack: ["location reset"], notHandedBack: ["xcrun simctl status_bar U clear"])
        let bundle = try record.write(into: Self.bundle(in: directory))
        let recorder = StreamRecorder()

        try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        let answer = try #require(recorder.out.first)

        #expect(try CaptureBundle.read(at: bundle.url).manifest.deviceSetup == record)
        #expect(answer.contains("setup: privacy grant location"))
        #expect(answer.contains("setup handed back: location reset"))
        #expect(answer.contains("⚠ setup not handed back — run: xcrun simctl status_bar U clear"))
    }

    /// A screen the walk never reached, and a capture taken before its tree settled, are qualifications of the answer — so the verdict says so and the code a pipeline reads says the same thing.
    @Test(arguments: [true, false])
    func aqualifiedBundleExitsTwoAndSaysWhichQualification(_ shortfall: Bool) throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, unreachable: shortfall ? ["power-detail"] : [], settled: shortfall)
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.err.isEmpty)
        let answer = try #require(recorder.out.first)
        #expect(answer.contains(shortfall ? "qualified — 1 screen unreachable" : "qualified — 1 capture taken before the tree settled"))
    }

    /// A bundle that cannot be read at all is a refused *call*, not a qualified answer — a different code, on stderr, in the verdict's own three words.
    @Test
    func abundleThatCannotBeReadRefusesRatherThanQualifying() throws {
        let directory = try TemporaryDirectory()
        let command = try BundleInspectCommand.parse([directory.url.appendingPathComponent("absent.simwalk").path])
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try command.run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.hasPrefix("refused — ") == true)
    }

    /// The answer prices itself last, and the log records what it priced — so a month of these lines can be added up without re-reading a single bundle.
    @Test
    func theAnswerEndsWithWhatItStoodInForAndTheLogRecordsIt() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory)
        let recorder = StreamRecorder()

        try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        let answer = try #require(recorder.out.first)
        #expect(answer.hasSuffix("A floor: only what this answer stood in for is counted."))
        let entry = try #require(try UsageReport.entries(at: Self.log(in: directory).fileURL).entries.first)
        #expect(entry.screenshots == 1)
        #expect(entry.imageTokens == 4070)
        // What the face put on the wire, terminator included — the figure the answer itself quotes.
        #expect(entry.answerBytes == (answer + "\n").utf8.count)
    }

    private static func bundle(in directory: TemporaryDirectory, unreachable: [String] = [], settled: Bool = true) throws -> CaptureBundle {
        try CaptureBundleFixture.write(
            in: directory,
            captures: [
                CaptureBundleFixture.Capture(
                    screenID: "progress",
                    state: Walkbook.CaptureState(theme: .light),
                    tree: CaptureBundleFixture.plainScreen(),
                    settled: settled
                ),
            ],
            unreachable: unreachable
        )
    }

    /// A failure no error type classifies is this command's own code over a bundle it has already read — `tool-error`, never a caller's mistake and never no kind at all.
    ///
    /// The bundle argument's own failures are `CaptureBundleError`s, which carry their own.
    @Test
    func anunmappedFailureIsRecordedAsToolError() throws {
        struct Unmapped: Error {}
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try BundleInspectCommand.parse(["x.simwalk"]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) { throw Unmapped() }
        }

        let entry = try #require(try UsageReport.entries(at: Self.log(in: directory).fileURL).entries.first)
        #expect(entry.tool == "bundle inspect")
        #expect(entry.kind == .toolError)
    }

    private static func command(for bundle: CaptureBundle) throws -> BundleInspectCommand {
        try BundleInspectCommand.parse([bundle.url.path])
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }
}
