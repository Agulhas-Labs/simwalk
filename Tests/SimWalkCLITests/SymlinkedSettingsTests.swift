//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// A `settings.json` kept in a dotfiles repository and linked into `~/.claude` is a deliberate arrangement, so the install and the uninstall write through the link rather than replacing it with a copy that would leave the dotfiles file out of date.
struct SymlinkedSettingsTests {
    private static var executable: String {
        "/usr/local/bin/simwalk"
    }

    /// The install changes the file the link leads to, the link stays a link, and the backup sits beside the file that changed.
    @Test
    func theInstallWritesThroughASymlinkedSettingsFile() throws {
        let directory = try TemporaryDirectory()
        let elsewhere = directory.url.appendingPathComponent("dotfiles/settings.json")
        let link = directory.url.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        let before = Data("{\"model\":\"sonnet\"}\n".utf8)
        try before.write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        let answer = try Self.install(settings: link, in: directory)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == elsewhere.path)
        let written = try String(contentsOf: elsewhere, encoding: .utf8)
        #expect(written.contains("hook pre-tool-use"))
        #expect(written.contains("\"model\""))
        #expect(try Data(contentsOf: elsewhere.appendingPathExtension("bak-simwalk")) == before)
        #expect(!FileManager.default.fileExists(atPath: link.appendingPathExtension("bak-simwalk").path))
        #expect(answer.text.contains("hook: PreToolUse registered"))
    }

    /// The uninstall takes the hook back out of the file the link leads to, and leaves the link.
    @Test
    func theUninstallWritesThroughASymlinkedSettingsFile() throws {
        let directory = try TemporaryDirectory()
        let elsewhere = directory.url.appendingPathComponent("dotfiles/settings.json")
        let link = directory.url.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"model\":\"sonnet\"}\n".utf8).write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        _ = try Self.install(settings: link, in: directory)

        _ = try UninstallHookCommand.answer(locations: Self.locations(settings: link, in: directory), executable: Self.executable, claude: RecordingClaude(config: directory.url.appendingPathComponent("claude.json")))

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == elsewhere.path)
        #expect(try !String(contentsOf: elsewhere, encoding: .utf8).contains("hook pre-tool-use"))
    }

    private static func locations(settings: URL, in directory: TemporaryDirectory) -> HookLocations {
        HookLocations(
            settings: settings,
            config: directory.url.appendingPathComponent("claude.json"),
            rule: directory.url.appendingPathComponent("claude/rules/simwalk.md"),
            segments: nil,
            visibility: StatuslineVisibility(cacheDirectory: directory.url.appendingPathComponent("simwalk/statusline")),
            runner: RunnerStore(directory: directory.url.appendingPathComponent("simwalk/runner")),
            runnerBuilds: RunnerBuilds(directory: directory.url.appendingPathComponent("simwalk/runner-builds")),
            installedBinary: directory.url.appendingPathComponent("bin/simwalk")
        )
    }

    /// The whole install against a scratch home, with no runner to snapshot and no guide to copy: the settings file is the claim.
    private static func install(settings: URL, in directory: TemporaryDirectory) throws -> Answer {
        try InstallHookCommand.answer(
            locations: locations(settings: settings, in: directory),
            executable: executable,
            claude: RecordingClaude(config: directory.url.appendingPathComponent("claude.json")),
            guide: .missing(reason: "not under test"),
            runnerSource: RunnerSnapshotSource(checkout: nil, binaryHash: nil, run: { _, _ in Shell.Result(status: 0, standardOutput: "", standardError: "") })
        )
    }
}
