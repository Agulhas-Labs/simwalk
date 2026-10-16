//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `SIMWALK_USAGE_LOG`, held to the built binary: what a test, a review or a mutation run writes lands in the file it names, and the state kept beside the log — the status line's cache, the report's redaction salt — goes with it.
///
/// **Driven as a process, deliberately.** Everything else in this suite injects its log, which is exactly why none of it could see the binary writing into the machine's own `~/.simwalk` — the reason this variable exists. `CFFIXED_USER_HOME` points the process's home at a scratch directory too (`homeDirectoryForCurrentUser` ignores `HOME` but honours it), so a regression here writes into that scratch home, where this test looks for it, and never into the real one.
struct UsageLogOverrideTests {
    /// A call recorded, a report read and a status line rendered, all under the variable — and nothing under the home the process would otherwise have used.
    @Test
    func everythingKeptBesideTheLogFollowsTheOverride() throws {
        let scratch = try TemporaryDirectory()
        let home = scratch.url.appendingPathComponent("home", isDirectory: true)
        let moved = scratch.url.appendingPathComponent("moved", isDirectory: true)
        let log = moved.appendingPathComponent("calls.jsonl")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let environment = ["CFFIXED_USER_HOME": home.path, UsageLog.overrideVariable: log.path]
        let binary = try Self.binary()
        let session = "session-\(UUID().uuidString)"
        let transcript = scratch.url.appendingPathComponent("\(session).jsonl")
        try Data((Self.walkCall + "\n").utf8).write(to: transcript)

        let validate = try Shell().run(binary.path, ["validate", scratch.url.appendingPathComponent("absent.json").path], environment: environment)
        // The MCP face's line for the session's walk — the CLI records no session, so only a line like this
        // one is the status line's to price, and only if it reads the log the variable names.
        UsageLog(fileURL: log, now: { Date() })
            .record(tool: "walk", target: "a.json", milliseconds: 1, succeeded: false, err: "no such file", session: session, kind: .inputRefused)
        let usage = try Shell().run(binary.path, ["usage"], environment: environment)
        let statusline = try Shell().run(binary.path, ["statusline", "--transcript", transcript.path], environment: environment)

        #expect(validate.status == AnswerVerdict.refusedExitCode)
        #expect(try UsageReport.entries(at: log).entries.map(\.tool) == ["validate", "walk"])
        // Redacted by default (SimWalk usage round 5, finding 6): the log sits outside home under a
        // scratch directory, so the header shows its basename rather than the full path.
        #expect(usage.standardOutput.hasPrefix("log: \(log.lastPathComponent)  (path redacted — outside home)  calls: 2"))
        #expect(statusline.standardOutput.trimmed == "simwalk 1 walk · 1 refused")
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("redaction-salt").path))
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("statusline").appendingPathComponent("\(session).json").path))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".simwalk").path))
    }

    /// One `mcp__simwalk__walk` call, in the shape a Claude Code transcript carries it — enough for the status line to have a session to cache.
    private static var walkCall: String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"call-1","name":"mcp__simwalk__walk","input":{"walkbook":"a.json"}}]}}"#
    }

    /// The `simwalk` this suite was built beside — `swift test` builds every product before running, so its absence is a failure rather than a skip.
    static func binary(sourceLocation: SourceLocation = #_sourceLocation) throws -> URL {
        let url = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("simwalk")
        try #require(FileManager.default.isExecutableFile(atPath: url.path), "no simwalk binary beside the test bundle at \(url.path)", sourceLocation: sourceLocation)
        return url
    }
}

extension UsageLogOverrideTests {
    /// A class, because `Bundle(for:)` locates the image a class was loaded from — which is the test bundle, beside the binary.
    final class BundleMarker {}
}
