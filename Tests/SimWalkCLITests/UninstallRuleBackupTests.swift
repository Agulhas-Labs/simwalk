//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import Testing

/// Fieldwork keeps a differing file at the rule path as `<rule>.bak-<tool>` before replacing it; the uninstall takes that away with the rule.
struct UninstallRuleBackupTests {
    private static func uninstall(_ machine: UninstallNothingRegisteredTests.Machine) throws -> Answer {
        try UninstallHookCommand.answer(
            locations: machine.locations(),
            executable: "/usr/local/bin/simwalk",
            claude: RecordingClaude(config: machine.config)
        )
    }

    @Test
    func aBackupBesideTheRuleIsRemovedAndNamed() throws {
        let machine = try UninstallNothingRegisteredTests.Machine()
        let backup = SettingsBackupFile.url(beside: machine.rule, tool: .simwalk)
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("their own rule\n".utf8).write(to: backup)

        let answer = try Self.uninstall(machine)

        #expect(!FileManager.default.fileExists(atPath: backup.path))
        #expect(answer.text.contains(backup.lastPathComponent))
    }

    @Test
    func noBackupMeansNoExtraLine() throws {
        let machine = try UninstallNothingRegisteredTests.Machine()
        let backup = SettingsBackupFile.url(beside: machine.rule, tool: .simwalk)

        let answer = try Self.uninstall(machine)

        #expect(!answer.text.contains(backup.lastPathComponent))
    }
}
