//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// `bundle oracle`: the real-app finding through the command, its exit codes, and the one `answer()` both faces serve.
struct BundleOracleCommandTests {
    /// A real app's finding (measured on its walkbook, 2026-08-20), end to end through a real oracle process: the rolling window matches, midnight is shown beside it, and a clean answer exits 0.
    @Test
    func theExampleFigureMatchesTheRollingWindowAndExitsZero() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory)
        let recorder = StreamRecorder()

        try run.command.run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        let text = recorder.out.joined()

        #expect(text.contains("today/light-loc_en_us steps-today: 2,703 matches rolling24h (exact) — midnight 3326, rolling24h 2703 count"))
        #expect(text.contains("\nok — 1 of 1 figure checks matched\n"))
        #expect(recorder.err.isEmpty)
    }

    @Test
    func aFigureMatchingNoWindowExitsWithTheFindingsCode() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory, rolling24h: 2750)

        let recorder = try Self.expectExit(AnswerVerdict.qualifiedExitCode, running: run.command, in: directory)

        #expect(recorder.out.joined().contains("steps-today: 2,703 matches none — midnight 3326, rolling24h 2750"))
        #expect(recorder.out.joined().contains("qualified — 1 figure matches no window"))
    }

    /// Adding `figures` to a walkbook after a walk is the normal way to start using the oracle, so a walkbook that differs from the walked one qualifies; it does not refuse.
    @Test
    func aWalkbookChangedSinceTheWalkQualifiesRatherThanRefuses() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory, bundleWalkbookHash: "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0")

        let recorder = try Self.expectExit(AnswerVerdict.qualifiedExitCode, running: run.command, in: directory)

        let text = recorder.out.joined()

        #expect(text.contains("walkbook changed since the walk; figures matched by screen id"))
        #expect(text.contains("steps-today: 2,703 matches rolling24h"))
    }

    /// A figure nobody could check gets a line of its own and qualifies; silence would pass it.
    @Test
    func aFigureOnAScreenThatWasNotCapturedHasItsOwnLineAndQualifies() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory, extraScreen: "power-detail", unreachable: ["power-detail"])

        let recorder = try Self.expectExit(AnswerVerdict.qualifiedExitCode, running: run.command, in: directory)

        let text = recorder.out.joined()

        #expect(text.contains("power-detail power: screen not captured (unreachable)"))
        #expect(text.contains("1 figure on a screen that was not captured"))
        #expect(text.contains("today/light-loc_en_us steps-today: 2,703 matches rolling24h"))
    }

    @Test
    func aWalkbookWithNoOracleRefusesWithExitOne() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory, withOracle: false)
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try run.command.run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.hasPrefix("refused — ") == true)
        #expect(recorder.err.joined().contains("names no 'oracle'"))
    }

    @Test
    func aBundleWithoutCaptureTimesRefusesWithExitOne() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory)
        let manifestURL = run.bundle.url.appendingPathComponent(CaptureBundleLayout.manifestFileName)
        let stripped = try String(contentsOf: manifestURL, encoding: .utf8).replacing(#/"capturedAt"\s*:\s*"[^"]*",?/#, with: "")
        try Data(stripped.utf8).write(to: manifestURL)
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try run.command.run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.err.joined().contains("records no capture time"))
    }

    /// The MCP face serves the CLI's `answer()`: the tool's argument vector, run as the server runs it, prints what the command prints.
    @Test
    func theMCPFaceAnswersWhatTheCommandAnswers() throws {
        let directory = try TemporaryDirectory()
        let run = try Self.setUp(in: directory, rolling24h: 2750)

        let invocation = try MCPToolInvocation(tool: "oracle", arguments: ["bundle": run.bundle.url.path, "walkbook": run.walkbook.path])
        let served = try MCPToolRunner.answer(tool: invocation.tool, arguments: invocation.argumentVector)

        #expect(try served.text == (run.command.answer()).text)
        #expect(invocation.logName == "bundle oracle")
        #expect(served.verdict.isQualified)
    }
}

extension BundleOracleCommandTests {
    struct Run {
        let bundle: CaptureBundle
        let walkbook: URL
        let command: BundleOracleCommand
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }

    private static func expectExit(_ code: Int32, running command: BundleOracleCommand, in directory: TemporaryDirectory, sourceLocation: SourceLocation = #_sourceLocation) throws -> StreamRecorder {
        let recorder = StreamRecorder()
        let thrown = try #require(#expect(throws: ExitCode.self, sourceLocation: sourceLocation) {
            try command.run(log: log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        }, sourceLocation: sourceLocation)
        #expect(thrown == ExitCode(code), sourceLocation: sourceLocation)
        #expect(recorder.err.isEmpty, sourceLocation: sourceLocation)
        return recorder
    }

    /// A walkbook on disk beside a shell oracle that answers every request with that app's values, and a bundle of its Today screen.
    ///
    /// The bundle records the walkbook's own hash unless `bundleWalkbookHash` says otherwise, so the walkbook is "the one the bundle was walked from" by default.
    private static func setUp(
        in directory: TemporaryDirectory,
        rolling24h: Int = 2703,
        bundleWalkbookHash: String? = nil,
        extraScreen: String? = nil,
        unreachable: [String] = [],
        withOracle: Bool = true
    ) throws -> Run {
        var book = FigureFixture.figureWalkbook()
        book.oracle = withOracle ? Walkbook.Oracle(command: ["/bin/sh", "oracle.sh"]) : nil
        if !withOracle {
            // `figures` with no `oracle` is refused by the loader before the command sees it, so the walkbook that reaches `noOracle` names none.
            book.screens[0].figures = nil
        }
        if let extraScreen {
            book.screens.append(Walkbook.Screen(
                id: extraScreen,
                route: [.tap(label: "Power")],
                states: [Walkbook.CaptureState(theme: .light)],
                figures: [Walkbook.Figure(id: "power", element: "power", windows: ["midnight"])]
            ))
        }
        let walkbookURL = directory.url.appendingPathComponent("walkbook.json")
        try JSONEncoder().encode(book).write(to: walkbookURL)
        let script = "while IFS= read -r line; do echo '{\"values\":{\"midnight\":3326,\"rolling24h\":\(rolling24h)},\"unit\":\"count\"}'; done\n"
        try Data(script.utf8).write(to: directory.url.appendingPathComponent("oracle.sh"))
        let hash = try WalkbookIdentity.hash(of: WalkbookLoader.load(contentsOf: walkbookURL))
        let bundle = try FigureFixture.figureBundle(in: directory, unreachable: unreachable, walkbookHash: bundleWalkbookHash ?? hash)
        let command = try BundleOracleCommand.parse([bundle.url.path, "--walkbook", walkbookURL.path])
        return Run(bundle: bundle, walkbook: walkbookURL, command: command)
    }
}
