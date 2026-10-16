//
// Copyright © Agulhas Labs
//

import ArgumentParser
@testable import SimWalkCLI
import SimWalkMCP
import Testing

/// What the root command offers, held to what reads it.
struct SimWalkCommandTests {
    /// The status line tells a shell *call* from a mention of the binary's name by the verb after it.
    ///
    /// That list lives in `SimWalkMCP`, which cannot see this target, so a subcommand added without landing there would be a face of the tool whose use the status line silently never counts. This is the one side that sees both.
    ///
    /// Every name a subcommand answers to is gathered, not just the one it spells: a subcommand declared without a `commandName` still has the one ArgumentParser derives for it, and an `aliases:` entry is a second name the shell knows. Reading `configuration.commandName` alone dropped both from the comparison and let the claim above go quietly untrue.
    ///
    /// `_commandName` is underscored ArgumentParser API, taken deliberately: it is public, it is the one thing that derives the implicit name, and there is no unprefixed equivalent. Its going away would be a compile error here rather than a wrong answer in the status line, which is the trade this test exists to make.
    @Test
    func theverbsTheStatusLineCountsAreTheCommandsOwnSubcommands() {
        // Gathered in a loop because both shorter spellings are closed to it: a `compactMap` closure is a
        // `preferKeyPath` violation, and the key path it asks for — over an existential metatype — crashes
        // SILGen in Swift 6.3.3.
        var subcommands: Set<String> = []
        for subcommand in SimWalkCommand.configuration.subcommands {
            subcommands.insert(subcommand._commandName)
            subcommands.formUnion(subcommand.configuration.aliases)
        }

        #expect(subcommands == TranscriptScan.invocationVerbs)
    }
}
