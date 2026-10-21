//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `--junit <file>` through the commands: what is refused up front, that no exit code moves, and what a failed write or a qualified verdict leaves in the file.
struct JUnitCommandTests {
    private static let light = Walkbook.CaptureState(theme: .light)

    @Test
    func aWalkDryRunRefusesJunitBecauseItCapturesNothing() {
        #expect(throws: (any Error).self) {
            try WalkCommand.parse(["walkbook.json", "--output", "out.json", "--dry-run", "--junit", "report.xml"])
        }
    }

    /// An empty path and an existing directory are refused at parse time, on every command that takes the flag.
    @Test
    func anEmptyPathAndADirectoryAreRefusedUpFront() throws {
        let directory = try TemporaryDirectory()

        for path in ["", directory.url.path] {
            #expect(throws: (any Error).self) { try BundleAuditCommand.parse(["x.simwalk", "--junit", path]) }
            #expect(throws: (any Error).self) { try BundleDiffCommand.parse(["a.simwalk", "b.simwalk", "--junit", path]) }
            #expect(throws: (any Error).self) { try BundleOracleCommand.parse(["x.simwalk", "--walkbook", "w.json", "--junit", path]) }
            #expect(throws: (any Error).self) { try WalkCommand.parse(["w.json", "--output", "o.simwalk", "--junit", path]) }
        }
    }

    /// A diff's exit code, answer and stderr are the same with the flag, and the file's failures are the diff's counted flags.
    @Test
    func aDiffExitsAndPrintsTheSameWithAndWithoutTheFlag() throws {
        let directory = try TemporaryDirectory()
        let reference = try CaptureBundleFixture.write(in: directory, captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Self.light, tree: CaptureBundleFixture.mixedScreen())])
        let other = try TemporaryDirectory()
        let run = try CaptureBundleFixture.write(in: other, captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Self.light, tree: CaptureBundleFixture.plainScreen())])
        let file = directory.url.appendingPathComponent("diff.xml")
        let plain = StreamRecorder()
        let flagged = StreamRecorder()

        let first = try Self.exit { try BundleDiffCommand.parse([reference.url.path, run.url.path]).run(log: Self.log(in: directory), emit: plain.emit, emitError: plain.emitError) }
        let second = try Self.exit { try BundleDiffCommand.parse([reference.url.path, run.url.path, "--junit", file.path]).run(log: Self.log(in: directory), emit: flagged.emit, emitError: flagged.emitError) }

        #expect(first == second)
        #expect(plain.out == flagged.out)
        #expect(plain.err == flagged.err)
        let counted = BundleDiff.compare(run: run, against: reference).flagCount
        #expect(try String(contentsOf: file, encoding: .utf8).contains("failures=\"\(counted)\""))
    }

    /// An oracle's exit code and answer are the same with the flag; its file's failures are the answer's unmatched checks.
    @Test
    func anOracleExitsAndPrintsTheSameWithAndWithoutTheFlag() throws {
        let directory = try TemporaryDirectory()
        let walkbook = try Self.oracleWalkbook(in: directory, figures: true)
        let bundle = try FigureFixture.figureBundle(in: directory, walkbookHash: Self.hash(of: walkbook))
        let file = directory.url.appendingPathComponent("oracle.xml")
        let plain = StreamRecorder()
        let flagged = StreamRecorder()

        let first = try Self.exit { try BundleOracleCommand.parse([bundle.url.path, "--walkbook", walkbook.path]).run(log: Self.log(in: directory), emit: plain.emit, emitError: plain.emitError) }
        let second = try Self.exit { try BundleOracleCommand.parse([bundle.url.path, "--walkbook", walkbook.path, "--junit", file.path]).run(log: Self.log(in: directory), emit: flagged.emit, emitError: flagged.emitError) }

        #expect(first == second)
        #expect(plain.out == flagged.out)
        let xml = try String(contentsOf: file, encoding: .utf8)
        #expect(xml.contains("failures=\"0\"") == (first == 0))
    }

    /// A walkbook with an `oracle` and no `figures` checks nothing and qualifies; the file says so in a failing case rather than reporting zero tests.
    @Test
    func anOracleWithNoFiguresWritesOneFailingCaseCarryingTheVerdict() throws {
        let directory = try TemporaryDirectory()
        let walkbook = try Self.oracleWalkbook(in: directory, figures: false)
        let bundle = try FigureFixture.figureBundle(in: directory, walkbookHash: Self.hash(of: walkbook))
        let file = directory.url.appendingPathComponent("oracle.xml")
        let recorder = StreamRecorder()

        let code = try Self.exit { try BundleOracleCommand.parse([bundle.url.path, "--walkbook", walkbook.path, "--junit", file.path]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) }

        #expect(code == AnswerVerdict.qualifiedExitCode)
        let xml = try String(contentsOf: file, encoding: .utf8)
        #expect(xml.contains("tests=\"1\" failures=\"1\""))
        #expect(xml.contains("nothing was checked"))
        #expect(recorder.out.joined().contains("nothing was checked"))
    }

    /// A write that cannot land qualifies the answer: exit 2, whatever the answer was.
    @Test
    func aWriteThatFailsQualifiesTheAnswerThroughFinish() throws {
        let directory = try TemporaryDirectory()
        let output = JUnitOutput(path: directory.url.path, command: "bundle audit")
        output.report = JUnitReport(command: "bundle audit", cases: [JUnitCase(classname: "c", name: "n", result: .passed)])
        let answer = Answer(header: "h", verdict: .unqualified("ok"))

        let finished = output.finish(answer)

        #expect(finished.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(finished.verdict.line.contains("JUnit file not written: "))
        #expect(output.finish(refusal: "no")?.contains("JUnit file not written: ") == true)
    }

    /// An exit-2 run never writes an all-green file.
    @Test
    func aQualifiedAnswerWithNoFailingCaseWritesAFailingVerdictCase() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("out.xml")
        let output = JUnitOutput(path: file.path, command: "bundle audit")
        output.report = JUnitReport(command: "bundle audit", cases: [JUnitCase(classname: "c", name: "n", result: .passed)])
        let answer = Answer(header: "h", verdict: .qualified(["2 screens unreachable"], detail: "d"))

        _ = output.finish(answer)
        let xml = try String(contentsOf: file, encoding: .utf8)

        #expect(xml.contains("failures=\"1\""))
        #expect(xml.contains("<testcase classname=\"simwalk\" name=\"verdict\">"))
        #expect(xml.contains(answer.verdict.line))
    }

    // MARK: helpers

    private static func oracleWalkbook(in directory: TemporaryDirectory, figures: Bool) throws -> URL {
        var book = FigureFixture.figureWalkbook()
        book.oracle = Walkbook.Oracle(command: ["/bin/sh", "oracle.sh"])
        if !figures {
            book.screens[0].figures = nil
        }
        let url = directory.url.appendingPathComponent("walkbook.json")
        try JSONEncoder().encode(book).write(to: url)
        let script = "while IFS= read -r line; do echo '{\"values\":{\"midnight\":3326,\"rolling24h\":2703},\"unit\":\"count\"}'; done\n"
        try Data(script.utf8).write(to: directory.url.appendingPathComponent("oracle.sh"))
        return url
    }

    private static func hash(of walkbook: URL) throws -> String {
        try WalkbookIdentity.hash(of: WalkbookLoader.load(contentsOf: walkbook))
    }

    private static func exit(_ body: () throws -> Void) throws -> Int32 {
        do {
            try body()
            return 0
        } catch let code as ExitCode {
            return code.rawValue
        }
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }
}
