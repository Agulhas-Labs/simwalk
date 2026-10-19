//
// Copyright © Agulhas Labs
//

@testable import SimWalkCLI
import Testing

/// The note on a rule that cannot be refreshed names the command SimWalk has, `install-hook`, not the `install` the shared library would otherwise assume.
struct RuleInstallCommandTests {
    @Test
    func theNoteOnAMissingRuleNamesInstallHook() {
        let note = SimWalkClaudeSetup.rule.noSourceReason(exists: true)

        #expect(note.contains("`simwalk install-hook` from Homebrew or npm"))
        #expect(!note.contains("`simwalk install` "))
    }
}
