//
// Copyright © Agulhas Labs
//

import SimWalkCore
@testable import SimWalkMCP
import Testing

/// Which of this module's own errors the usage log counts as an `input-refused` bad argument versus a `setup-failed` Claude Code configuration problem.
struct UsageFailureKindTests {
    /// `MCPError` reports the kind its constructor stated, whichever that is — it has no default of its own to fall back to, so a constructor cannot forget one and land on the kind the headline hides.
    @Test
    func mcpErrorReportsTheKindItWasBuiltWith() {
        #expect(UsageFailureKind.of(MCPError(message: "x", kind: .inputRefused)) == .inputRefused)
        #expect(UsageFailureKind.of(MCPError(message: "x", kind: .toolError)) == .toolError)
    }

    /// `MCPToolInvocation` refusing an unknown tool or a bad argument is always a bad argument, and states so itself.
    ///
    /// (`MCPToolRunner.parsed`, in `SimWalkCLI`, states `.inputRefused` for `validate()` and `.toolError` for anything else — pinned in `MCPFaceTests`.)
    @Test
    func aninvocationsOwnRefusalsAreInputRefused() {
        let unknownTool = #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "nope", arguments: [:])
        }
        let missingArgument = #expect(throws: MCPError.self) {
            try MCPToolInvocation(tool: "validate", arguments: [:])
        }

        #expect(unknownTool?.kind == .inputRefused)
        #expect(missingArgument?.kind == .inputRefused)
    }

    /// The settings file `install-hook`/`uninstall-hook` merge into is usually Claude Code's own default path, not something the caller typed — Claude Code's own configuration, the same shape as `HookInstallError`.
    @Test
    func statuslineRegistrationErrorIsSetupFailed() {
        let error = StatuslineRegistrationError.settingsNotAnObject(path: "/nope/settings.json")

        #expect(UsageFailureKind.of(error) == .setupFailed)
    }
}
