//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkTestSupport
import Testing

/// What SimWalk hands the shared rule install: the shipped file, the installed name, and what happens to a rule already there.
///
/// `~/.claude/rules/simwalk.md` is the obvious name for somebody's own notes about this tool, so a differing rule is kept before it is replaced.
struct AgentGuideTests {
    @Test
    func theInstalledRuleIsTheShippedGuideByteForByteWithTheFrontmatterIntact() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "---\npaths:\n  - \"**/*.xcodeproj/**\"\n---\n\n# Using simwalk\n")

        let outcome = try SimWalkClaudeSetup.rule.install(source: source, destination: Self.destination(in: scratch))
        let installed = try String(contentsOf: Self.destination(in: scratch), encoding: .utf8)

        #expect(outcome.written == [Self.destination(in: scratch).path])
        #expect(outcome.lines.first?.hasPrefix("rule: installed ") == true)
        #expect(installed.hasPrefix("---\npaths:"))
        #expect(try installed == String(contentsOf: source, encoding: .utf8))
    }

    @Test
    func areInstallOfTheSameGuideChangesNothing() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# Using simwalk\n")

        _ = try SimWalkClaudeSetup.rule.install(source: source, destination: Self.destination(in: scratch))
        let again = try SimWalkClaudeSetup.rule.install(source: source, destination: Self.destination(in: scratch))

        #expect(again.written.isEmpty)
        #expect(again.lines.first?.hasPrefix("rule: already installed") == true)
    }

    /// A rule that differs, including one an older install stamped with its marker line, is kept once as `.bak-simwalk` and replaced.
    @Test
    func aDifferingRuleIncludingALegacyMarkedOneIsBackedUpOnceAndReplaced() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# Using simwalk\n")
        let destination = Self.destination(in: scratch)
        let legacy = "# Using simwalk\n<!-- installed by `simwalk install-hook` — `simwalk uninstall-hook` removes it, and the next install overwrites it -->\n"
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: destination)

        let outcome = try SimWalkClaudeSetup.rule.install(source: source, destination: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "# Using simwalk\n")
        #expect(try String(contentsOf: destination.appendingPathExtension("bak-simwalk"), encoding: .utf8) == legacy)
        #expect(outcome.lines.first?.contains(".bak-simwalk") == true)
    }

    /// A symlink means the machine has the checkout and the rule *is* the repo file: writing through it would silently revert a working tree to whatever the binary was built beside.
    @Test
    func asymlinkedRuleIsNeitherWrittenThroughNorDeleted() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# from the checkout\n")
        let link = Self.destination(in: scratch)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)

        let installed = try SimWalkClaudeSetup.rule.install(source: source, destination: link)
        let removed = SimWalkClaudeSetup.rule.uninstall(destination: link)

        #expect(installed.written.isEmpty)
        #expect(removed.written.isEmpty)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == source.path)
        #expect(try String(contentsOf: source, encoding: .utf8) == "# from the checkout\n")
    }

    @Test
    func removalTakesTheInstalledCopy() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# Using simwalk\n")
        let destination = Self.destination(in: scratch)

        #expect(SimWalkClaudeSetup.rule.uninstall(destination: destination).lines.isEmpty)
        _ = try SimWalkClaudeSetup.rule.install(source: source, destination: destination)
        let removed = SimWalkClaudeSetup.rule.uninstall(destination: destination)

        #expect(removed.lines.first?.hasPrefix("rule: removed ") == true)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    /// The installed copy's path, deliberately in a directory of its own: `SimWalk.md` and `simwalk.md` are one file on a case-insensitive filesystem, so a source and a destination side by side would be the same file and every assertion here would be about nothing.
    private static func destination(in scratch: TemporaryDirectory) -> URL {
        scratch.url.appendingPathComponent("rules/simwalk.md")
    }

    private static func source(in scratch: TemporaryDirectory, _ contents: String) throws -> URL {
        let url = scratch.url.appendingPathComponent("SimWalk.md")
        try Data(contents.utf8).write(to: url)
        return url
    }
}
