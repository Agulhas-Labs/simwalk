//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import Testing

/// A `claude` that is on PATH but cannot launch throws out of the shared install rather than reporting a failure; the install-hook command is where that becomes a refusal naming what was already written.
struct InstallClaudeLaunchFailureTests {
    @Test
    func aClaudeThatCannotLaunchIsARefusalNamingWhatWasWritten() throws {
        let scratch = try HookInstallTests.Scratch()
        let executable = "/Users/x/.local/bin/simwalk"

        let error = try #require(throws: HookInstallError.self) {
            try InstallHookCommand.answer(
                locations: scratch.locations(),
                executable: executable,
                claude: BrokenClaude(),
                guide: .found(scratch.guideSource),
                runnerSource: scratch.runnerSource
            )
        }
        guard case let .claudeRefused(failures, written) = error else {
            Issue.record("expected claudeRefused, got \(error)")
            return
        }

        #expect(failures.contains { $0.contains("could not run") && $0.contains("Exec format error") })
        #expect(failures.contains { $0.contains(SimWalkClaudeSetup.server.manual(binary: executable)) })
        #expect(!written.isEmpty)
        #expect(written.contains { $0.contains("simwalk.md") || $0.contains("rule") })
        #expect(UsageFailureKind.of(error) == .setupFailed)
    }
}

extension InstallClaudeLaunchFailureTests {
    struct CannotLaunch: Error, CustomStringConvertible {
        var description: String {
            "posix_spawn failed: Exec format error"
        }
    }

    struct BrokenClaude: ClaudeMcpRunner {
        func run(_: [String]) throws -> Subprocess.Output? {
            throw CannotLaunch()
        }
    }
}
