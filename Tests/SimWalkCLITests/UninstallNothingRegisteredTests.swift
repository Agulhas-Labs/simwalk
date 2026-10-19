//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkDriver
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// The uninstall on a machine that never registered the server: the real `claude mcp remove` exits 1 for an absent name, so the uninstall must not ask it.
struct UninstallNothingRegisteredTests {
    @Test
    func uninstallingWithNothingRegisteredAnswersSoAndDoesNotAskClaude() throws {
        let machine = try Machine()
        let recorder = RecordingClaude(config: machine.config)

        let answer = try UninstallHookCommand.answer(locations: machine.locations(), executable: "/usr/local/bin/simwalk", claude: recorder)

        #expect(answer.verdict.exitCode == 0)
        #expect(answer.text.contains("mcp: nothing registered"))
        #expect(recorder.vectors.filter { $0.prefix(2) == ["mcp", "remove"] }.isEmpty)
    }
}

extension UninstallNothingRegisteredTests {
    /// A throwaway machine with no settings, no rule and no server.
    struct Machine {
        let directory: TemporaryDirectory

        init() throws {
            directory = try TemporaryDirectory()
        }

        var rule: URL {
            directory.url.appendingPathComponent("claude/rules/simwalk.md")
        }

        var config: URL {
            directory.url.appendingPathComponent("claude.json")
        }

        func locations() -> HookLocations {
            HookLocations(
                settings: directory.url.appendingPathComponent("claude/settings.json"),
                config: config,
                rule: rule,
                segments: nil,
                visibility: StatuslineVisibility(cacheDirectory: directory.url.appendingPathComponent("simwalk/statusline")),
                runner: RunnerStore(directory: directory.url.appendingPathComponent("simwalk/runner")),
                runnerBuilds: RunnerBuilds(directory: directory.url.appendingPathComponent("simwalk/runner-builds")),
                installedBinary: directory.url.appendingPathComponent("bin/simwalk")
            )
        }
    }
}
