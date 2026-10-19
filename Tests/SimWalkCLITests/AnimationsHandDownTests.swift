//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// Every hand from the library provider to the runner (SimWalk#154), each seen with a recording fake provider so nothing compiles a library or reads the machine's `~/.simwalk`.
struct AnimationsHandDownTests {
    private static var libraryPath: String {
        "/libs/animations-1.dylib"
    }

    private static var library: WalkCommand.AnimationsLibrary {
        { URL(fileURLWithPath: libraryPath) }
    }

    private static var refusingShell: Shell {
        Shell(script: { _, _, _ in throw ShellReached() })
    }

    /// `walked`, which the CLI's `walk` answers through, hands the library to the walk.
    @Test
    func walkedHandsTheLibraryToTheRunner() throws {
        let walk = try WalkProgressWiringTests.Walk()

        _ = try walk.performWalked([], animationsLibrary: Self.library)

        #expect(walk.runnerEnvironments.map { $0[AnimationsOptIn.hostEnvironmentKey] } == [Self.libraryPath])
    }

    /// A dry run's runner is launched with the library.
    @Test
    func aDryRunHandsTheLibraryToTheRunner() throws {
        let walk = try WalkProgressWiringTests.Walk()
        let book = try WalkbookLoader.load(from: Data(WalkProgressWiringTests.Walk.oneScreenJSON.utf8), source: "book.json")
        let report = try RouteProbeFixture.report(of: book, outcomes: [], buildHash: AppBuildIdentity.hash(ofAppAt: walk.appPath))

        _ = try walk.performDryRun(leaving: report, of: book, animationsLibrary: Self.library)

        #expect(walk.runnerEnvironments.map { $0[AnimationsOptIn.hostEnvironmentKey] } == [Self.libraryPath])
    }

    /// The MCP face offers a walk, and a dry run, the provider it is given.
    @Test(arguments: [false, true])
    func theMCPFaceOffersAWalkAndADryRunTheProvider(dryRun: Bool) throws {
        let walk = try WalkProgressWiringTests.Walk()
        let recording = Recording()
        let output = walk.directory.url.appendingPathComponent(dryRun ? "probe.json" : "mcp.simwalk")
        let environment = ["SIMWALK_USAGE_LOG": walk.directory.url.appendingPathComponent("usage.jsonl").path]

        #expect(throws: WalkCommand.AnimationsLibraryError.self) {
            try MCPToolRunner.answer(
                tool: .walk,
                arguments: [walk.walkbookPath, "--output", output.path] + (dryRun ? ["--dry-run"] : []),
                environment: environment,
                walking: MCPToolRunner.WalkSeams(
                    shell: Self.refusingShell,
                    runner: { WalkCommandTests.runner },
                    builds: WalkCommandTests.builds(in: walk.directory),
                    leases: WalkCommandTests.leases(in: walk.directory)
                ),
                animationsLibrary: { _ in recording.provider }
            )
        }

        #expect(recording.calls == 1)
    }

    /// The MCP session start offers the provider it is given.
    @Test
    func theMCPSessionStartOffersTheProvider() throws {
        let fixture = try SessionCommandTests.Fixture()
        let recording = Recording()

        #expect(throws: WalkCommand.AnimationsLibraryError.self) {
            try MCPToolRunner.sessionAnswer(
                ["start", "--device", "UDID-1", "--app", "com.example.live"],
                store: fixture.store,
                processes: fixture.processes,
                pause: fixture.pause,
                now: fixture.now,
                shell: Shell(script: fixture.script.run),
                runner: { throw RunnerRefused() },
                builds: RunnerBuilds(directory: fixture.directory.url.appendingPathComponent("runner-builds", isDirectory: true)),
                environment: [:],
                logFileURL: fixture.directory.url.appendingPathComponent("usage.jsonl"),
                animationsLibrary: recording.provider
            )
        }

        #expect(recording.calls == 1)
    }

    /// The second pass over a screen refused on appearance is launched with the library too.
    @Test
    func theAppearanceRetryPassHandsTheLibraryToItsRunner() throws {
        let (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let writes = try (bundle: WalkCommandTests.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
        let script = try WalkCommandTests.WalkScript(appPath: WalkCommandTests.fakeApp(in: directory), runnerStatus: 0, writes: writes, retryWrites: WalkCommandTests.progressAgain(in: retryDirectory, refusingDark: true).url)
        let command = try WalkCommand.parse([WalkCommandTests.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])

        _ = try command.performWalk(shell: Shell(script: script.run), pause: { _ in }, now: script.now, runner: { WalkCommandTests.runner }, builds: WalkCommandTests.builds(in: directory), leases: WalkCommandTests.leases(in: directory), animationsLibrary: Self.library)

        let launched = script.calls.filter { $0.arguments.contains("test-without-building") }.map { $0.environment[AnimationsOptIn.hostEnvironmentKey] }
        #expect(launched == [Self.libraryPath, Self.libraryPath])
    }

    /// A `--screens` id the walkbook lacks is refused before the library is built.
    @Test
    func anUnknownScreensIDIsRefusedBeforeTheLibraryIsBuilt() throws {
        let walk = try WalkProgressWiringTests.Walk()
        let recording = Recording()

        #expect(throws: (any Error).self) {
            try walk.perform(["--screens", "nowhere"], animationsLibrary: recording.provider)
        }

        #expect(recording.calls == 0)
        #expect(walk.runnerEnvironments.isEmpty)
    }

    /// The library is built after the runner is resolved: a walk whose runner cannot be had never builds it (SimWalk#154).
    @Test
    func theLibraryIsBuiltOnlyAfterTheRunnerIsResolved() throws {
        let walk = try WalkProgressWiringTests.Walk()
        let recording = Recording()

        #expect(throws: RunnerRefused.self) {
            try walk.performWalked([], runner: { throw RunnerRefused() }, animationsLibrary: recording.provider)
        }

        #expect(recording.calls == 0)
    }
}

extension AnimationsHandDownTests {
    /// A shell that refuses every child, so a hand that regresses to the real one fails here instead of reaching a device.
    private struct ShellReached: Error {}

    private struct RunnerRefused: Error {}

    /// A provider that records each call and fails, so a caller that reaches it is seen without anything past it running.
    private final class Recording {
        private(set) var calls = 0

        var provider: WalkCommand.AnimationsLibrary {
            { [self] in
                calls += 1
                throw CocoaError(.fileWriteNoPermission)
            }
        }
    }
}
