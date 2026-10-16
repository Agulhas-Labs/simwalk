//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle screen`'s exit code and its refusal before opening anything, on the same reasoning `bundle inspect`'s own tests hold to: the report is printed either way, so the code is what a pipeline actually gates on.
struct BundleScreenCommandTests {
    /// A screen with one clean capture answers with exit 0, and its text is on stdout.
    @Test
    func acleanScreenExitsZero() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])
        let recorder = StreamRecorder()

        try Self.command(for: bundle, step: 1).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        #expect(recorder.out.count == 1)
        let answer = try #require(recorder.out.first)
        #expect(answer.contains("Nothing here opens · StaticText ·"))
        #expect(recorder.err.isEmpty)
    }

    /// A capture taken before its tree settled is a qualified answer, and exits with the code that says so.
    @Test
    func aqualifiedCaptureExitsTwo() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen(), settled: false),
        ])
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command(for: bundle, step: 1).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(recorder.out.count == 1)
        #expect(recorder.err.isEmpty)
    }

    /// A step outside the walk's plan is refused before the tree is even opened.
    @Test
    func astepOutsideThePlanRefuses() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command(for: bundle, step: 2).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.contains("1 to 1") == true)
    }

    /// A bundle that cannot be read at all is a refused *call*, not a report about a step — a different code, on stderr, with nothing on stdout.
    @Test
    func abundleThatCannotBeReadRefuses() throws {
        let directory = try TemporaryDirectory()
        let command = try BundleScreenCommand.parse([directory.url.appendingPathComponent("absent.simwalk").path, "1"])
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try command.run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode.failure)
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.hasPrefix("refused — ") == true)
    }

    /// `<step>` refuses before anything is opened, on the same "refuse where refusing is cheaper than discovering" reasoning `WalkCommand` holds `--settle` to.
    @Test
    func astepLessThanOneIsRefusedAtParseTime() {
        #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk", "0"])
        }
    }

    /// A negative step on a terminal reaches the command's own refusal, not the parser's "Missing expected argument '<step>'" — which read `-1` as an unknown option and then said something false about it (SimWalk#20 round 3, finding 4).
    @Test
    func anegativeStepIsRefusedInTheCommandsOwnWords() {
        let thrown = #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk", "-1"])
        }
        let message = thrown.map { BundleScreenCommand.message(for: $0) } ?? ""

        #expect(message.contains("-1 is not one"))
        #expect(!message.contains("Missing expected argument"))
    }

    /// `--all` reaches the command as `listsOffScreen`, and is off without it (SimWalk#118).
    @Test
    func allParsesToListingOffScreenElements() throws {
        let with = try BundleScreenCommand.parse(["anywhere.simwalk", "1", "--all"])
        let without = try BundleScreenCommand.parse(["anywhere.simwalk", "1"])

        #expect(with.listsOffScreen)
        #expect(!without.listsOffScreen)
    }

    /// A screen id beginning with `-` is a step like any other, looked up rather than read as an option.
    @Test
    func adashLeadingScreenIDReachesTheCommandAsItsStep() throws {
        let command = try BundleScreenCommand.parse(["anywhere.simwalk", "-legacy"])

        #expect(command.step == ["-legacy"])
    }

    /// `--match` and `--state` take a value beginning with `-` as their value, in the two-token form a person types as well as the joined one.
    @Test
    func optionValuesBeginningWithADashAreTakenAsValues() throws {
        let command = try BundleScreenCommand.parse(["anywhere.simwalk", "1", "--match", "-2", "--state", "-x"])

        #expect(command.match == "-2")
        #expect(command.state == "-x")
        #expect(command.step == ["1"])
    }

    /// A missing step, and a second step where one was expected, are refused in the command's own words — the price of collecting the step as the parser's leftovers is saying what those leftovers were.
    ///
    /// Until SimWalk#20 round 4 the second token here was `--bogus`, which is now refused as the option it looks like (below).
    @Test
    func amissingOrSecondStepIsRefusedNamingWhatWasGiven() {
        let missing = #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk"])
        }
        let second = #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk", "1", "2"])
        }

        #expect(missing.map { BundleScreenCommand.message(for: $0) }?.contains("<step> is required") == true)
        #expect(second.map { BundleScreenCommand.message(for: $0) }?.contains("'1' was followed by '2'") == true)
    }

    /// A token beginning with `--` before any `--` is an option this command does not take, refused as one — never named as the step (`--bogus foo 1`), never looked up as a screen id (a lone `--bogus`), and never a second step (SimWalk#20 round 4, finding 8).
    @Test(arguments: [["--bogus", "foo", "1"], ["--bogus"], ["1", "--bogus"], ["--bogus=3", "1"]])
    func anunknownOptionIsRefusedAsAnOptionNeverAsAStep(_ tokens: [String]) {
        let thrown = #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk"] + tokens)
        }
        let message = thrown.map { BundleScreenCommand.message(for: $0) } ?? ""

        #expect(message.hasPrefix("'\(tokens.first { $0.hasPrefix("--") } ?? "")' is not an option this command takes"))
        #expect(!message.contains("names one screen"))
    }

    /// A single-dash token that is not a number, standing beside another step, is an option this command does not take — `-s light 1` is someone reaching for a short `--state`, refused as that, never as a first step followed by two more (SimWalk#20 round 4, finding 9) — while a lone one is still a screen id and a negative number still a step.
    @Test(arguments: [["-s", "light", "1"], ["1", "-s", "light"], ["-legacy", "2"]])
    func ashortOptionBesideAStepIsRefusedAsAnOption(_ tokens: [String]) {
        let thrown = #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk"] + tokens)
        }
        let message = thrown.map { BundleScreenCommand.message(for: $0) } ?? ""

        #expect(message.hasPrefix("'\(tokens.first { $0.hasPrefix("-") } ?? "")' is not an option this command takes"))
        #expect(!message.contains("names one screen"))
    }

    /// After the POSIX `--`, every token is the step: `-- -1` reaches the below-1 refusal rather than being refused as a second step, and a screen id beginning with `--` is looked up and answered.
    @Test
    func whatFollowsTheTerminatorIsTheStep() throws {
        let belowOne = #expect(throws: (any Error).self) {
            try BundleScreenCommand.parse(["anywhere.simwalk", "--", "-1"])
        }
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "--odd", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])

        let answer = try BundleScreenCommand.parse([bundle.url.path, "--", "--odd"]).answer()

        #expect(belowOne.map { BundleScreenCommand.message(for: $0) }?.contains("-1 is not one") == true)
        #expect(answer.text.contains("step 1 '--odd'"))
    }

    /// The call is logged under the query's own name, the one the MCP face logs a screen-scoped inspect under too — so `simwalk usage` prices both faces' one-screen answers as one verb.
    @Test
    func thecallIsLoggedAsBundleScreen() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])
        let recorder = StreamRecorder()

        try Self.command(for: bundle, step: 1).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        let text = try String(contentsOf: directory.url.appendingPathComponent("usage.jsonl"), encoding: .utf8)
        let entries = try text.split(separator: "\n").map { try JSONDecoder().decode(UsageLog.Entry.self, from: Data($0.utf8)) }

        #expect(entries.map(\.tool) == ["bundle screen"])
    }

    private static func command(for bundle: CaptureBundle, step: Int) throws -> BundleScreenCommand {
        try BundleScreenCommand.parse([bundle.url.path, String(step)])
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }
}
