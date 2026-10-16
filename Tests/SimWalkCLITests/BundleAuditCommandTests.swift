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

/// `bundle audit`'s exit code, which is the half of the verdict a pipeline reads.
///
/// The contract had exactly one reference — the implementation — so nothing said that a bundle whose screens were never opened, or whose rows disagree, reaches a caller as anything other than a pass. The report is printed on every branch, so stdout cannot be the signal.
struct BundleAuditCommandTests {
    /// A bundle that holds everything and types its rows uniformly is a pass, and a pass exits 0.
    @Test
    func aCompleteAndConsistentBundleExitsZero() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button")),
        ])
        let recorder = StreamRecorder()

        try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        #expect(recorder.out.count == 1)
        #expect(recorder.err.isEmpty)
    }

    /// Screens the walk never opened: exit 0 here is what made an unexamined bundle indistinguishable from a clean one.
    @Test
    func aBundleWhoseScreensWereNeverOpenedExitsWithTheFindingsCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(
            in: directory,
            captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button"))],
            unreachable: ["power-detail"]
        )

        try Self.expectFindingsExit(auditing: bundle, in: directory)
    }

    /// A capture taken before its tree stopped changing is evidence recorded mid-motion, and a verdict resting on it is qualified.
    @Test
    func aBundleCapturedBeforeItsTreeSettledExitsWithTheFindingsCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button"), settled: false),
        ])

        try Self.expectFindingsExit(auditing: bundle, in: directory)
    }

    /// The finding itself: complete coverage, and rows of one shape typed two ways.
    @Test
    func aBundleWhoseRowsAreTypedTwoWaysExitsWithTheFindingsCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.mixedScreen()),
        ])

        try Self.expectFindingsExit(auditing: bundle, in: directory)
    }

    /// A bundle that cannot be read at all is a refused *call*, not a qualified verdict — a different code, on stderr, with nothing on stdout.
    @Test
    func aBundleThatCannotBeReadRefusesRatherThanReportingAFinding() throws {
        let directory = try TemporaryDirectory()
        let command = try BundleAuditCommand.parse([directory.url.appendingPathComponent("absent.simwalk").path])
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try command.run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode.failure)
        #expect(thrown != ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.count == 1)
    }

    /// The report is printed either way — the code is what a script gates on, not the absence of an answer.
    private static func expectFindingsExit(
        auditing bundle: CaptureBundle,
        in directory: TemporaryDirectory,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self, sourceLocation: sourceLocation) {
            try command(for: bundle).run(log: log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        }, sourceLocation: sourceLocation)

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode), sourceLocation: sourceLocation)
        #expect(recorder.out.count == 1, sourceLocation: sourceLocation)
        #expect(recorder.err.isEmpty, sourceLocation: sourceLocation)
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
            try BundleAuditCommand.parse(["x.simwalk"]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError) { throw Unmapped() }
        }

        let entry = try #require(try UsageReport.entries(at: Self.log(in: directory).fileURL).entries.first)
        #expect(entry.tool == "bundle audit")
        #expect(entry.kind == .toolError)
    }

    /// The new rules' finding reaches the exit code the same way the disclosure rule's does: an enabled switch with no label is a qualified answer.
    @Test
    func anUnlabelledSwitchExitsWithTheFindingsCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.labelBundle(in: directory)
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.out.joined().contains("[unlabelledControl] 1 found"))
    }

    /// `--only` restricts the run: the same bundle, asked only for the duplicate rule, has nothing to find and does not print the other rules.
    @Test
    func onlyRestrictsTheRunToTheNamedRule() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.labelBundle(in: directory)
        let recorder = StreamRecorder()

        try BundleAuditCommand.parse([bundle.url.path, "--only", "duplicateLabel"])
            .run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        #expect(recorder.out.joined().contains("[duplicateLabel] not applicable"))
        #expect(!recorder.out.joined().contains("[unlabelledControl]"))
    }

    /// A repeated `--only` runs each rule named.
    @Test
    func aRepeatedOnlyRunsSeveralRules() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.labelBundle(in: directory)
        let recorder = StreamRecorder()

        #expect(throws: ExitCode.self) {
            try BundleAuditCommand.parse([bundle.url.path, "--only", "duplicateLabel", "--only", "unlabelledControl"])
                .run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        }

        let text = recorder.out.joined()
        #expect(text.contains("[duplicateLabel] not applicable"))
        #expect(text.contains("[unlabelledControl] 1 found"))
        #expect(!text.contains("[symbolNameLabel]"))
    }

    /// A rule name nobody wrote is refused before anything is read, and the refusal lists the rules that exist.
    @Test
    func anUnknownOnlyNameIsRefusedListingTheRules() {
        let message = BundleAuditCommand.message(for: parseError(["x.simwalk", "--only", "unlabeledControl"]))
        #expect(message.contains("'unlabeledControl' is not a bundle audit rule"))
        for name in AuditRuleName.allCases {
            #expect(message.contains(name.rawValue))
        }
    }

    /// On the MCP path the same refusal is the caller's: `.inputRefused`, in the command's own words.
    @Test
    func anUnknownOnlyNameOnTheMCPPathIsAnInputRefusal() {
        let thrown = #expect(throws: MCPError.self) {
            try MCPToolRunner.answer(tool: .audit, arguments: ["x.simwalk", "--only=nope"])
        }

        #expect(thrown?.kind == .inputRefused)
        #expect(thrown?.message.contains("'nope' is not a bundle audit rule") == true)
    }

    private func parseError(_ arguments: [String]) -> Error {
        do {
            _ = try BundleAuditCommand.parse(arguments)
            return ExitCode.success
        } catch {
            return error
        }
    }

    private static func labelBundle(in directory: TemporaryDirectory) throws -> CaptureBundle {
        try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(
                screenID: "you",
                state: Walkbook.CaptureState(theme: .light),
                tree: LabelTreeFixture.screen([LabelTreeFixture.element("Switch", y: 100)])
            ),
        ])
    }

    private static func command(for bundle: CaptureBundle) throws -> BundleAuditCommand {
        try BundleAuditCommand.parse([bundle.url.path])
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }

    @Test
    func theWalkbookOptionParsesAndIsOptional() throws {
        #expect(try BundleAuditCommand.parse(["x.simwalk"]).walkbook == nil)
        #expect(try BundleAuditCommand.parse(["x.simwalk", "--walkbook", "w.json"]).walkbook == "w.json")
    }

    /// Budgets are tightened after a walk, so a walkbook that is not the one the bundle was walked from qualifies the answer rather than refusing it — as `bundle oracle` does.
    @Test
    func aWalkbookOtherThanTheWalkedOneQualifiesTheAudit() throws {
        let directory = try TemporaryDirectory()
        let motion = CaptureManifest.Motion(settleMilliseconds: 900, readIntervalMilliseconds: 100, readCount: 10, shifts: [])
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "you", captures: [
                CaptureBundleFixture.Capture(screenID: "you", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button"), motion: motion),
            ]),
        ])
        let walkbook = directory.url.appendingPathComponent("walk.json")
        let json = #"{"name":"w","appBundleID":"a","screens":[{"id":"you","route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}],"budgets":{"settleMs":500}}]}"#
        try Data(json.utf8).write(to: walkbook)

        let answer = try BundleAuditCommand.parse([bundle.url.path, "--only", "motionBudget", "--walkbook", walkbook.path]).answer()

        #expect(answer.text.contains("walkbook changed since the walk; budgets matched by screen id"))
        #expect(answer.text.contains("settle 900 ms > budget 500 ms"))
    }

    /// A `--screens` walk records the hash of its subset; the full walkbook it was narrowed from is still the plan, so it must not read as changed.
    @Test
    func aSubsetWalkAuditedAgainstItsFullWalkbookIsNotQualifiedAsChanged() throws {
        let directory = try TemporaryDirectory()
        let motion = CaptureManifest.Motion(settleMilliseconds: 900, readIntervalMilliseconds: 100, readCount: 10, shifts: [])
        let json = #"{"name":"w","appBundleID":"a","screens":[{"id":"you","route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}],"budgets":{"settleMs":500}},{"id":"other","route":[{"tab":{"label":"Other"}}],"states":[{"theme":"light"}]}]}"#
        let walkbook = directory.url.appendingPathComponent("walk.json")
        try Data(json.utf8).write(to: walkbook)
        let subsetHash = try WalkbookIdentity.hash(of: WalkbookSubset.narrow(WalkbookLoader.load(contentsOf: walkbook), to: ["you"]))
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "you", captures: [
                CaptureBundleFixture.Capture(screenID: "you", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.screen(rowType: "Button"), motion: motion),
            ]),
        ], walkbookHash: subsetHash)

        let answer = try BundleAuditCommand.parse([bundle.url.path, "--only", "motionBudget", "--walkbook", walkbook.path]).answer()

        #expect(!answer.text.contains("walkbook changed since the walk"))
        #expect(answer.text.contains("settle 900 ms > budget 500 ms"))
    }

    /// Named by `--only` over nothing to check, `ok — 0 rules` would read as a pass: refused as input, with why.
    @Test
    func motionBudgetNamedWithoutBudgetsIsRefusedAsInput() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.labelBundle(in: directory)
        let bare = try BundleAuditCommand.parse([bundle.url.path, "--only", "motionBudget"])
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try bare.run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode.failure)
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.joined().contains("motionBudget has no budgets to check: pass --walkbook with a walkbook whose screens state \"budgets\""))

        let walkbook = directory.url.appendingPathComponent("none.json")
        try Data(#"{"name":"w","appBundleID":"a","screens":[{"id":"you","route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}]}]}"#.utf8).write(to: walkbook)
        let stated = #expect(throws: InputRefusal.self) {
            try BundleAuditCommand.parse([bundle.url.path, "--only", "motionBudget", "--walkbook", walkbook.path]).answer()
        }
        #expect(stated?.message == "motionBudget has no budgets to check: the walkbook passed states no \"budgets\"")
    }

    /// A walkbook with a motion budget only has nothing for `performanceBudget` to check, and the reverse: each rule is refused by name over the other's budgets.
    @Test
    func eachBudgetRuleIsRefusedByNameOverTheOtherKindsBudgets() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.labelBundle(in: directory)
        let motionOnly = directory.url.appendingPathComponent("motion.json")
        try Data(#"{"name":"w","appBundleID":"a","screens":[{"id":"you","route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}],"budgets":{"settleMs":500}}]}"#.utf8).write(to: motionOnly)
        let performanceOnly = directory.url.appendingPathComponent("performance.json")
        try Data(#"{"name":"w","appBundleID":"a","screens":[{"id":"you","route":[{"tab":{"label":"You"}}],"states":[{"theme":"light"}],"budgets":{"launchMs":500}}]}"#.utf8).write(to: performanceOnly)

        let noPerformance = #expect(throws: InputRefusal.self) {
            try BundleAuditCommand.parse([bundle.url.path, "--only", "performanceBudget", "--walkbook", motionOnly.path]).answer()
        }
        let noMotion = #expect(throws: InputRefusal.self) {
            try BundleAuditCommand.parse([bundle.url.path, "--only", "motionBudget", "--walkbook", performanceOnly.path]).answer()
        }

        #expect(noPerformance?.message.hasPrefix("performanceBudget has no budgets to check") == true)
        #expect(noMotion?.message.hasPrefix("motionBudget has no budgets to check") == true)
        // Each names the kind it lacks: the walkbook does state budgets.
        #expect(noPerformance?.message.contains("states no performance \"budgets\"") == true)
        #expect(noMotion?.message.contains("states no motion \"budgets\"") == true)
    }

    @Test
    func motionBudgetNamedWithoutBudgetsOnTheMCPPathIsAnInputRefusal() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.labelBundle(in: directory)

        let thrown = #expect(throws: InputRefusal.self) {
            try MCPToolRunner.answer(tool: .audit, arguments: ["--only=motionBudget", "--", bundle.url.path])
        }

        #expect(UsageFailureKind.of(thrown ?? InputRefusal("")) == .inputRefused)
        #expect(thrown?.message.contains("motionBudget has no budgets to check") == true)
    }

    /// An all-rules run without budgets keeps the not-run heading and refuses nothing.
    @Test
    func aDefaultRunWithoutBudgetsJustSaysMotionBudgetWasNotRun() throws {
        let directory = try TemporaryDirectory()
        let answer = try Self.command(for: Self.labelBundle(in: directory)).answer()

        #expect(answer.text.contains("[motionBudget] not run — no walkbook budgets (pass --walkbook)"))
    }
}
