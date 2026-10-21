//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `session start` launches the app with UIKit animations off on a simulator, `--animations` keeps them (SimWalk#154).
struct SessionAnimationsTests {
    private static var libraryPath: String {
        "/libs/animations-1.dylib"
    }

    /// The default simulator start hands the runner the library and says so in the header.
    @Test
    func aSimulatorStartSwitchesAnimationsOffByDefault() throws {
        let fixture = try SessionCommandTests.Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(SessionCommandTests.ready) }

        let answer = try fixture.start(["--device", "UDID-1", "--app", "com.example.live"], animationsLibrary: { URL(fileURLWithPath: Self.libraryPath) })

        let command = try #require(fixture.processes.spawned.first)
        #expect(command.environment[AnimationsOptIn.hostEnvironmentKey] == Self.libraryPath)
        #expect(answer.header.hasSuffix("  animations: off"))
    }

    /// `--animations` builds nothing and passes nothing.
    @Test
    func animationsKeepsThemOnAndBuildsNoLibrary() throws {
        let fixture = try SessionCommandTests.Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(SessionCommandTests.ready) }
        var builds = 0

        let answer = try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--animations"], animationsLibrary: {
            builds += 1
            return URL(fileURLWithPath: Self.libraryPath)
        })

        let command = try #require(fixture.processes.spawned.first)
        #expect(command.environment[AnimationsOptIn.hostEnvironmentKey] == nil)
        #expect(builds == 0)
        #expect(answer.header.hasSuffix("  animations: on"))
    }

    /// A library that cannot be built refuses the start before the runner is spawned, with part of the walk's text.
    @Test
    func aLibraryThatCannotBeBuiltRefusesTheStartBeforeTheRunnerIsSpawned() throws {
        let fixture = try SessionCommandTests.Fixture()

        let refusal = #expect(throws: WalkCommand.AnimationsLibraryError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live"], animationsLibrary: { throw CocoaError(.fileWriteNoPermission) })
        }

        #expect(refusal?.description.hasSuffix("; --animations walks without it") == true)
        #expect(fixture.processes.spawned.isEmpty)
    }

    /// A physical device gets no library and says `on`, with or without the flag.
    @Test(arguments: [[], ["--animations"]])
    func aDeviceStartPassesNoLibraryAndSaysOn(extra: [String]) throws {
        let fixture = try SessionStartDeviceTests.Fixture()
        var builds = 0

        let answer = try fixture.start(["--device", SessionStartDeviceTests.udid, "--team", "TEAM", "--app", "com.example.live"] + extra, animationsLibrary: {
            builds += 1
            return URL(fileURLWithPath: Self.libraryPath)
        })

        let command = try #require(fixture.processes.spawned.first)
        #expect(command.environment[AnimationsOptIn.hostEnvironmentKey] == nil)
        #expect(builds == 0)
        #expect(answer.header.hasSuffix("  animations: on"))
    }

    /// `--state` may not set the animations variable either: a session has one animation state.
    @Test
    func aStateCannotSetTheAnimationsVariable() throws {
        let fixture = try SessionCommandTests.Fixture()

        let refusal = #expect(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"light","environment":{"SIMWALK_ANIMATIONS":"on"}}"#])
        }

        #expect(refusal == .stateSetsAnimations(variable: "SIMWALK_ANIMATIONS"))
        #expect(refusal?.description == "--state sets SIMWALK_ANIMATIONS in its environment, which a state may not set: a session has one animation state; pass --animations to keep animations on")
    }

    /// The outermost faces, which no behavioural test can enter without a real compile, hand down the standard provider: the CLI's `walk` (walk and dry run) and `session start`, and the MCP face through `MCPToolRunner.answer`'s default, which `MCPCommand` relies on by passing none. Code lines only, so a comment cannot satisfy it; the paths below these are pinned by `AnimationsHandDownTests`.
    @Test
    func theOutermostFacesHandDownTheStandardProvider() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/SimWalkCLI")
        func count(_ needle: String, in file: String) throws -> Int {
            try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .reduce(0) { $0 + $1.components(separatedBy: needle).count - 1 }
        }

        #expect(try count("animationsLibrary: Self.standardAnimationsLibrary(), interruption: cancellation, note: StandardStreams.emitError)", in: "WalkCommand.swift") == 1)
        #expect(try count("animationsLibrary: Self.standardAnimationsLibrary(), note: StandardStreams.emitError)", in: "WalkCommand.swift") == 1)
        #expect(try count("animationsLibrary: WalkCommand.standardAnimationsLibrary(), note: StandardStreams.emitError)", in: "SessionStartCommand.swift") == 1)
        #expect(try count("animationsLibrary: ([String: String]) -> WalkCommand.AnimationsLibrary = { WalkCommand.standardAnimationsLibrary(environment: $0) }", in: "MCPToolRunner.swift") == 1)
        #expect(try count("animationsLibrary:", in: "MCPCommand.swift") == 0)
    }
}
