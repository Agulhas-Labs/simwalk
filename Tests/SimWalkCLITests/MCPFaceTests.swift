//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The claim the MCP face is built on: it serves *the CLI's* answers, argument definitions and refusals included — checkable only where both faces are in scope.
struct MCPFaceTests {
    /// End to end through the protocol: a real walkbook, the real dispatch, and the text a terminal would have shown.
    @Test
    func averbAnsweredOverTheProtocolIsWordForWordWhatTheCLIWouldPrint() async throws {
        let directory = try TemporaryDirectory()
        let walkbook = directory.url.appendingPathComponent("smoke.json")
        try Data(Self.walkbook.utf8).write(to: walkbook)

        let responses = try await Self.send([
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
                "name": "validate",
                "arguments": ["walkbook": walkbook.path],
            ]],
        ])

        let expected = try ValidateCommand.parse([walkbook.path]).answer()
        let result = try #require(responses.first?["result"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)

        #expect(text == expected.text)
        #expect(result["isError"] as? Bool == false)
        #expect(text.contains("ok — 1 capture planned"))
    }

    /// `inspect` with a `step` is `bundle screen` underneath, with no second tool to look up — end to end, the two must print identically, since the CLI subcommand is the only place either face's answer comes from.
    @Test
    func ainspectWithAStepAnswersWhatBundleScreenWouldHave() async throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])

        let responses = try await Self.send([
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
                "name": "inspect",
                "arguments": ["bundle": bundle.url.path, "step": 1],
            ]],
        ])

        let expected = try BundleScreenCommand.parse([bundle.url.path, "1"]).answer()
        let result = try #require(responses.first?["result"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)

        #expect(text == expected.text)
        #expect(result["isError"] as? Bool == false)
        #expect(text.contains("Nothing here opens"))
    }

    /// A `step` of `"-1"` — a string, which the schema allows — is refused over the wire in words about the caller's argument, never as the parser's "Missing expected argument '<step>'", which was false (SimWalk#20 round 3, finding 4).
    @Test
    func anegativeStepGivenAsAStringIsRefusedInTheToolsOwnWordsEndToEnd() async throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])

        let responses = try await Self.send([
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
                "name": "inspect",
                "arguments": ["bundle": bundle.url.path, "step": "-1"],
            ]],
        ])

        let result = try #require(responses.first?["result"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)

        #expect(result["isError"] as? Bool == true)
        #expect(text.hasPrefix("refused — inspect was given a 'step' of -1"))
        #expect(!text.contains("Missing expected argument"))
    }

    /// A screen id beginning with `--` is a step over the wire too: the invocation puts the step after `--`, so the command's refusal of an option it does not take never catches a screen id (SimWalk#20 round 4, finding 8).
    @Test
    func ascreenIDBeginningWithTwoDashesIsAStepEndToEnd() async throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "--odd", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])

        let responses = try await Self.send([
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
                "name": "inspect",
                "arguments": ["bundle": bundle.url.path, "step": "--odd", "match": "Nothing"],
            ]],
        ])

        let result = try #require(responses.first?["result"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)

        #expect(result["isError"] as? Bool == false)
        #expect(text.contains("step 1 '--odd'"))
    }

    /// A numeric screen id with leading zeros reaches its screen over the wire: `"007"` re-spelled as `7` was a position past the walk's end, refused, where the id names a screen (SimWalk#20 round 4, finding 9).
    @Test
    func anumericScreenIDKeepsItsSpellingEndToEnd() async throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [
            CaptureBundleFixture.Capture(screenID: "007", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen()),
        ])

        let responses = try await Self.send([
            ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": [
                "name": "inspect",
                "arguments": ["bundle": bundle.url.path, "step": "007"],
            ]],
        ])

        let result = try #require(responses.first?["result"] as? [String: Any])
        let text = try #require((result["content"] as? [[String: Any]])?.first?["text"] as? String)

        #expect(result["isError"] as? Bool == false)
        #expect(text.contains("step 1 '007'"))
    }

    /// `inspect`'s routing reads the vector's shape, not its first word: a plain inspect of a bundle whose path is literally `screen` is still a whole-bundle inspect, refused about that path, and never `bundle screen` with its path taken for the command name.
    @Test
    func aplainInspectOfABundleSpelledScreenIsStillAnInspect() {
        #expect(throws: CaptureBundleError.self) {
            try MCPToolRunner.answer(tool: .inspect, arguments: ["screen"])
        }
    }

    /// The MCP face has no options of its own: they are the subcommand's, parsed by the subcommand — so a refusal it makes of its own arguments reaches an MCP caller in the words it wrote.
    ///
    /// This is `WalkCommand.validate()` refusing a caller's own argument — `MCPToolInvocation` cannot see across commands, so a bad `--settle` is only caught here — and it is `.inputRefused` like any other bad argument, not the parser and the command disagreeing about the shape of the call.
    @Test
    func acommandsOwnRefusalOfItsArgumentsReachesTheCallerInItsOwnWords() {
        let thrown = #expect(throws: MCPError.self) {
            try MCPToolRunner.answer(tool: .walk, arguments: ["book.json", "--output", "out.simwalk", "--settle", "0"])
        }

        #expect(thrown?.message.contains("--settle takes a quiet period in milliseconds greater than zero") == true)
        #expect(thrown?.kind == .inputRefused)
    }

    /// A parse failure that is not `validate()` — an argument vector the MCP face built that its own command rejects — means the two disagree with each other, not that a caller's argument was bad.
    ///
    /// `MCPToolInvocation` has already checked every JSON argument by the time this runs, so this can only be this server's own bug: `.toolError`, not `.inputRefused`.
    @Test
    func aparserFailureThatIsNotTheCommandsOwnValidationIsToolError() {
        let thrown = #expect(throws: MCPError.self) {
            try MCPToolRunner.answer(tool: .walk, arguments: ["book.json", "--output", "out.simwalk", "--settle"])
        }

        #expect(thrown?.kind == .toolError)
    }

    /// Only ArgumentParser's own wrapper is read as a command's `validate()` refusal — an error that merely borrows its shape is not, because reading one as a caller's refusal is the direction that hides a failure.
    @Test
    func anerrorShapedLikeArgumentParsersWrapperIsNotReadAsAValidationRefusal() {
        let lookalike = Lookalike(parserError: .userValidationError("borrowed"))

        #expect(!MCPToolRunner.isCommandsOwnValidationFailure(lookalike))
    }

    /// A refusal reaches the caller as the verb's own, with no walk attempted: the output path is checked from the argument itself, before a device is resolved or a build is started.
    @Test
    func awalkRefusesFromItsArgumentsBeforeAnythingIsBooted() throws {
        let directory = try TemporaryDirectory()
        let walkbook = directory.url.appendingPathComponent("smoke.json")
        try Data(Self.walkbook.utf8).write(to: walkbook)
        // A directory that exists and is not named as a bundle: a path where nothing exists is completed with `.simwalk` instead (SimWalk#107).
        let output = directory.url.appendingPathComponent("not-a-bundle")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": walkbook.path,
            "output": output.path,
        ])

        let owned = ["SIMWALK_USAGE_LOG": directory.url.appendingPathComponent("usage.jsonl").path]

        #expect(throws: CaptureBundleError.self) {
            try MCPToolRunner.answer(tool: .walk, arguments: invocation.argumentVector, environment: owned, animationsLibrary: { _ in { URL(fileURLWithPath: "/libs/animations-1.dylib") } })
        }
    }

    /// The `=` form is what carries a negative quiet period past the parser: `--settle -3` reads as an option with no value, so the caller would get ArgumentParser's sentence about its own syntax instead of the tool's about their argument.
    @Test
    func anegativeSettleReachesTheCommandsOwnRefusalEndToEnd() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "book.json", "output": "out.simwalk", "settle": -3,
        ])

        let thrown = #expect(throws: MCPError.self) {
            try MCPToolRunner.answer(tool: .walk, arguments: invocation.argumentVector)
        }

        #expect(thrown?.message.contains("--settle takes a quiet period in milliseconds greater than zero") == true)
        #expect(thrown?.message.contains("-3") == true)
        #expect(thrown?.kind == .inputRefused)
    }

    /// A screen id spelled like an option reaches `walk` as a screen id, parsed by the command's own definitions — not as a quiet period of zero that the command would then refuse in the caller's name.
    @Test
    func ascreenIDSpelledLikeAnOptionIsParsedAsAScreenID() throws {
        let invocation = try MCPToolInvocation(tool: "walk", arguments: [
            "walkbook": "book.json", "output": "out.simwalk", "screenIDs": ["--settle=0"],
        ])

        let command = try WalkCommand.parse(invocation.argumentVector)

        #expect(command.screens == ["--settle=0"])
        #expect(command.settle == nil)
        #expect(command.walkbook == "book.json")
    }

    /// A walkbook named like an option is a walkbook the command goes looking for, and a missing one is the caller's own mistake — `WalkbookLoadError`, `input-refused` — rather than the parser rejecting a vector this server built.
    ///
    /// Relative names, because that is the shape that broke: an absolute path starts with `/` and was never read as a flag.
    @Test
    func awalkbookNamedLikeAnOptionIsLookedForRatherThanRejectedAsAFlag() throws {
        for name in ["-x.json", "--version"] {
            let invocation = try MCPToolInvocation(tool: "validate", arguments: ["walkbook": name])

            let thrown = #expect(throws: WalkbookLoadError.self) {
                try MCPToolRunner.answer(tool: .validate, arguments: invocation.argumentVector)
            }

            #expect(thrown.map(Self.source)?.hasSuffix("/\(name)") == true)
            #expect(thrown.flatMap(UsageFailureKind.of) == .inputRefused)
        }
    }

    /// The walkbook a `WalkbookLoadError` names.
    private static func source(of error: WalkbookLoadError) -> String {
        switch error {
        case let .unreadable(source, _), let .malformed(source, _), let .invalid(source, _):
            source
        }
    }

    /// A walkbook as a data file, because that is what the loader reads — a model built in Swift would exercise the encoder instead.
    private static var walkbook: String {
        """
        {
          "name": "smoke",
          "appBundleID": "com.example.app",
          "screens": [
            { "id": "today", "route": [{ "tab": { "label": "Today" } }], "states": [{ "theme": "light" }] }
          ]
        }
        """
    }

    private static func send(_ requests: [[String: Any]]) async throws -> [[String: Any]] {
        let input = Pipe()
        let output = Pipe()
        let server = SimWalkMCPServer(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            log: { _ in },
            usage: nil,
            session: nil,
            answering: { try MCPToolRunner.answer(tool: $0, arguments: $1, cancellation: $2, started: $3) }
        )
        for request in requests {
            var line = try JSONSerialization.data(withJSONObject: request)
            line.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: line)
        }
        try input.fileHandleForWriting.close()
        await server.run()
        try output.fileHandleForWriting.close()

        let written = try output.fileHandleForReading.readToEnd() ?? Data()
        // Every line, or a failure: the Brief's carved-in-stone rule is that this stream carries JSON-RPC
        // and nothing else, and a filter that skipped what it could not parse would let a stray `print`
        // through while the suite stayed green.
        return try written.split(separator: 0x0A, omittingEmptySubsequences: true).map { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw StrayOutput(line: String(bytes: line, encoding: .utf8) ?? "<not UTF-8>")
            }
            return object
        }
    }
}

extension MCPFaceTests {
    /// An error with the shape ArgumentParser's internal `CommandError` has — a `parserError` whose case is `userValidationError` — and none of its identity.
    struct Lookalike: Error {
        let parserError: Shape
    }

    /// The case label the reflection reads, carried by a type that is not ArgumentParser's.
    enum Shape {
        case userValidationError(String)
    }

    /// A line on the server's stdout that is not a JSON-RPC message — the one thing that stream may never carry.
    struct StrayOutput: Error, CustomStringConvertible {
        let line: String

        var description: String {
            "the MCP server wrote a line to stdout that is not JSON-RPC: \(line)"
        }
    }
}
