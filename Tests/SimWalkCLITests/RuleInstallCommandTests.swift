//
// Copyright © Agulhas Labs
//

@testable import SimWalkCLI
import Testing

/// The note on a rule that cannot be refreshed names the command SimWalk has, `install-hook`, not the `install` the shared library would otherwise assume, and the routes SimWalk ships by: Homebrew and the release tarball, with no `install.sh` and no npm.
struct RuleInstallCommandTests {
    @Test
    func theNoteOnAMissingRuleNamesInstallHookAndSimWalksRoutes() {
        let note = SimWalkClaudeSetup.rule.noSourceReason(exists: true)

        #expect(note == "no SimWalk.md ships beside this binary to refresh it from (`simwalk install-hook` from Homebrew or the release tarball copies the SimWalk.md they ship)")
    }
}
