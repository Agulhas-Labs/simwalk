//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `--junit <file>`: the XML a CI reporter reads, and the promise that it changes nothing else about the command.
struct JUnitReportTests {
    /// The five XML characters are escaped in attributes and text, a line break survives an attribute, and a control character XML forbids is dropped.
    @Test
    func theRendererEscapesAndPrintsEveryKindOfCase() {
        let report = JUnitReport(command: "bundle audit", cases: [
            JUnitCase(classname: "a&b", name: "<x> \"q\" 'r'", result: .passed),
            JUnitCase(classname: "rule", name: "f", result: .failed("one & two\nthree\u{1}")),
            JUnitCase(classname: "rule", name: "e", result: .errored("<boom>")),
            JUnitCase(classname: "rule", name: "s", result: .skipped("not run")),
        ])

        #expect(report.render() == """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites name="simwalk bundle audit" tests="4" failures="1" errors="1" skipped="1">
          <testsuite name="simwalk bundle audit" tests="4" failures="1" errors="1" skipped="1">
            <testcase classname="a&amp;b" name="&lt;x&gt; &quot;q&quot; &apos;r&apos;"/>
            <testcase classname="rule" name="f">
              <failure message="one &amp; two&#10;three">one &amp; two
        three</failure>
            </testcase>
            <testcase classname="rule" name="e">
              <error message="&lt;boom&gt;">&lt;boom&gt;</error>
            </testcase>
            <testcase classname="rule" name="s">
              <skipped message="not run">not run</skipped>
            </testcase>
          </testsuite>
        </testsuites>

        """)
    }

    /// A refusal is one `<error>` case carrying the refusal line.
    @Test
    func aRefusalIsOneErrorCaseCarryingTheRefusalLine() {
        let report = JUnitReport.refusal(command: "walk", reason: "no device")

        #expect(report.cases == [JUnitCase(classname: "simwalk walk", name: "refused", result: .errored("refused — no device"))])
        #expect(report.errors == 1)
    }

    /// Findings fail one case each — equal to the answer's tally — and the exit code, the answer and the bytes written are the same with and without the flag.
    @Test
    func anAuditWritesOneFailingCasePerFindingAndChangesNoExitCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "you", state: Walkbook.CaptureState(theme: .light), tree: LabelTreeFixture.screen([LabelTreeFixture.element("Switch", y: 100)])),
        ])
        let file = directory.url.appendingPathComponent("audit.xml")
        let second = directory.url.appendingPathComponent("audit2.xml")

        let plain = StreamRecorder()
        let withFlag = StreamRecorder()
        let first = try Self.exit { try BundleAuditCommand.parse([bundle.url.path]).run(log: Self.log(in: directory), emit: plain.emit, emitError: plain.emitError) }
        let flagged = try Self.exit { try BundleAuditCommand.parse([bundle.url.path, "--junit", file.path]).run(log: Self.log(in: directory), emit: withFlag.emit, emitError: withFlag.emitError) }
        _ = try Self.exit { try BundleAuditCommand.parse([bundle.url.path, "--junit", second.path]).run(log: Self.log(in: directory), emit: { _ in }, emitError: { _ in }) }

        #expect(first == flagged)
        #expect(first == AnswerVerdict.qualifiedExitCode)
        #expect(plain.out == withFlag.out)
        let xml = try String(contentsOf: file, encoding: .utf8)
        #expect(xml.contains("failures=\"1\""))
        #expect(xml.contains("classname=\"unlabelledControl\" name=\"you · light · Switch at y=100\""))
        #expect(try Data(contentsOf: file) == Data(contentsOf: second))
    }

    /// A clean run still writes passing cases: a file with none reads as missing results.
    @Test
    func aCleanAuditWritesPassingCases() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button")),
        ])
        try CaptureBundleFixture.decodeScreenshots(of: bundle)
        let file = directory.url.appendingPathComponent("audit.xml")

        try BundleAuditCommand.parse([bundle.url.path, "--junit", file.path]).run(log: Self.log(in: directory), emit: { _ in }, emitError: { _ in })

        let xml = try String(contentsOf: file, encoding: .utf8)

        #expect(xml.contains("failures=\"0\""))
        #expect(xml.contains("<testcase classname=\"unlabelledControl\" name=\"unlabelledControl\"/>"))
    }

    /// A diff of a bundle against itself passes one case per compared state.
    @Test
    func aDiffAgainstItselfPassesEveryComparedState() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button")),
        ])
        let file = directory.url.appendingPathComponent("diff.xml")

        try BundleDiffCommand.parse([bundle.url.path, bundle.url.path, "--junit", file.path]).run(log: Self.log(in: directory), emit: { _ in }, emitError: { _ in })

        let xml = try String(contentsOf: file, encoding: .utf8)

        #expect(xml.contains("tests=\"1\" failures=\"0\""))
        #expect(xml.contains("<testcase classname=\"progress\" name=\"light\"/>"))
    }

    /// A walk's captured states pass, and a screen the walk never reached fails as one `(screen)` case with the line the answer prints.
    @Test
    func aWalkPassesCapturesAndFailsAnUnreachableScreen() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(
            in: directory,
            captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button"))],
            unreachable: ["power-detail"]
        )

        let report = JUnitWalkCases.report(of: bundle)

        #expect(report.cases.first == JUnitCase(classname: "progress", name: "light", result: .passed))
        #expect(report.failures == 1)
        let failure = try #require(report.cases.last)
        #expect(failure.classname == "power-detail")
        #expect(failure.name == "(screen)")
        #expect(report.cases.count - report.failures == 1)
    }

    /// An oracle check maps every outcome to a case — `matches` passes, the rest fail with the rendered line, a state not captured fails too — and the counts equal the text answer's tally.
    @Test
    func anOracleCheckMapsEveryOutcomeAndItsCountsEqualTheAnswers() throws {
        let directory = try TemporaryDirectory()
        let light = Walkbook.CaptureState(theme: .light)
        let dark = Walkbook.CaptureState(theme: .dark)
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(
                id: "today",
                outcome: .stateNotApplied(reason: "dark rendered as light"),
                captures: [CaptureBundleFixture.Capture(screenID: "today", state: light, tree: FigureFixture.screen(text: "2,703"))],
                refusedStates: [dark]
            ),
        ])
        var walkbook = FigureFixture.figureWalkbook()
        walkbook.screens[0].states = [light, dark]
        let figure = OnScreenFigure(printed: "2,703", value: 2703, fractionDigits: 0, unit: nil)
        let expected = [FigureCheck.WindowValue(window: "midnight", value: 2703)]
        let outcomes: [(String, FigureCheck.Outcome)] = [
            ("matched", .matches(windows: ["midnight"], figure: figure, expected: expected, unit: nil, attribution: nil)),
            ("none", .matchesNone(figure: figure, expected: expected, unit: nil, attribution: nil)),
            ("absent", .notOnScreen(element: "steps-today")),
            ("unread", .unreadable(reason: "two numbers")),
            ("broken", .oracleFailed(reason: "no answer")),
        ]
        let checks = outcomes.map { FigureCheck(screenID: "today", stateSlug: light.slug, figureID: $0.0, outcome: $0.1) }
        let summary = try OracleSummary(checks, of: bundle, against: walkbook)

        let report = JUnitOracleCases.report(summary)

        #expect(report.cases.map(\.classname) == Array(repeating: "today", count: 6))
        #expect(report.cases.map(\.name) == checks.map { "\($0.figureID) · \(light.slug)" } + ["steps-today · \(dark.slug)"])
        #expect(report.cases.first?.result == .passed)
        #expect(report.cases.dropFirst().prefix(4).map(\.result) == checks.dropFirst().map { .failed($0.rendered) })
        #expect(report.cases.last?.result == .failed("today/\(dark.slug) steps-today: state not captured (refused, state not applied)"))
        let line = summary.answer().verdict.line
        #expect(line.contains("\(report.cases.count - report.failures) of \(report.cases.count) figure checks matched"))
    }

    /// A refusal still leaves a report; an unreadable bundle writes its one `<error>` case and the exit code is the refusal's.
    @Test
    func aRefusedCommandWritesTheRefusalAsAnErrorCase() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("audit.xml")
        let command = try BundleAuditCommand.parse([directory.url.appendingPathComponent("absent.simwalk").path, "--junit", file.path])

        let code = try Self.exit { try command.run(log: Self.log(in: directory), emit: { _ in }, emitError: { _ in }) }

        #expect(code == AnswerVerdict.refusedExitCode)
        let xml = try String(contentsOf: file, encoding: .utf8)
        #expect(xml.contains("errors=\"1\""))
        #expect(xml.contains("<error message=\"refused — "))
    }

    /// A `--junit` path whose directory is missing is refused at parse time, before any work.
    @Test
    func aMissingDirectoryIsRefusedUpFront() {
        #expect(throws: (any Error).self) {
            try BundleAuditCommand.parse(["x.simwalk", "--junit", "/nonexistent-directory/out.xml"])
        }
        #expect(throws: (any Error).self) {
            try BundleDiffCommand.parse(["a.simwalk", "b.simwalk", "--junit", "/nonexistent-directory/out.xml"])
        }
    }

    /// A write that fails after the run qualifies the answer and leaves the rest alone.
    @Test
    func aFailedWriteQualifiesTheAnswer() {
        let answer = Answer(header: "h", verdict: .unqualified("ok detail"))

        let qualified = answer.qualified(by: "JUnit file not written: disk full")

        #expect(qualified.verdict == .qualified(["JUnit file not written: disk full"], detail: "ok detail"))
        #expect(qualified.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
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
