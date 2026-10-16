//
// Copyright © Agulhas Labs
//

@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import Testing

/// What `registerServer` does with a failure to launch `claude` at all, as distinct from `claude` running and refusing.
struct ClaudeCommandLineTests {
    /// `Shell.run`'s own classification for a launch failure is `.runnerFailed` — right for the walk runner's own machinery, wrong here: `claude` being missing or broken from under this call is Claude Code's own configuration, the same shape `HookInstallError.claudeRefused` already names two lines down for `claude` running and failing.
    ///
    /// A caller of `registerServer` — `install-hook` — must not see the two differently.
    @Test
    func alaunchFailureIsRewrappedAsHookInstallErrorNotLeftAsAShellError() {
        let claude = ClaudeCommandLine(executable: "/usr/bin/claude", run: { executable, _ in
            throw ShellError.couldNotRun(executable: executable, reason: "no such file or directory")
        })

        let thrown = #expect(throws: HookInstallError.self) {
            try claude.registerServer(command: ["/path/to/simwalk", "mcp"])
        }

        #expect(thrown.flatMap(UsageFailureKind.of) == .setupFailed)
    }
}
