//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// `~/.claude/rules/simwalk.md` is the obvious name for somebody's own notes about this tool, so the whole contract here is that an uninstall takes back only what an install put there.
struct AgentGuideTests {
    @Test
    func theInstalledCopyCarriesTheGuideAndTheMarkerThatSaysWhoWroteIt() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# Using simwalk\n")
        let guide = AgentGuide(destination: Self.destination(in: scratch))

        let outcome = try guide.install(from: source)
        let installed = try String(contentsOf: guide.fileURL, encoding: .utf8)

        #expect(outcome == .installed)
        #expect(installed.hasPrefix("# Using simwalk\n"))
        #expect(AgentGuide.isOurs(installed))
    }

    /// The marker goes at the end, because the guide opens with the YAML frontmatter that decides when it loads — anything above the opening `---` stops it being frontmatter at all.
    @Test
    func theMarkerDoesNotDisturbTheFrontmatterThatScopesTheRule() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "---\npaths:\n  - \"**/*.xcodeproj/**\"\n---\n\n# Using simwalk\n")
        let guide = AgentGuide(destination: Self.destination(in: scratch))

        _ = try guide.install(from: source)
        let installed = try String(contentsOf: guide.fileURL, encoding: .utf8)

        #expect(installed.hasPrefix("---\npaths:"))
        #expect(installed.hasSuffix(AgentGuide.marker + "\n"))
    }

    @Test
    func areInstallOfTheSameGuideChangesNothing() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# Using simwalk\n")
        let guide = AgentGuide(destination: Self.destination(in: scratch))

        _ = try guide.install(from: source)

        #expect(try guide.install(from: source) == .unchanged)
    }

    /// A symlink means the machine has the checkout and the rule *is* the repo file: writing through it would silently revert a working tree to whatever the binary was built beside.
    @Test
    func asymlinkedRuleIsNeitherWrittenThroughNorDeleted() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# from the checkout\n")
        let link = Self.destination(in: scratch)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let guide = AgentGuide(destination: link)

        #expect(try guide.install(from: source) == .symlink(target: source.path))
        #expect(try guide.remove() == .symlink(target: source.path))
        #expect(try String(contentsOf: source, encoding: .utf8) == "# from the checkout\n")
    }

    @Test
    func removalTakesTheInstalledCopy() throws {
        let scratch = try TemporaryDirectory()
        let source = try Self.source(in: scratch, "# Using simwalk\n")
        let guide = AgentGuide(destination: Self.destination(in: scratch))

        #expect(try guide.remove() == .absent)
        _ = try guide.install(from: source)
        #expect(try guide.remove() == .removed)
        #expect(!FileManager.default.fileExists(atPath: guide.fileURL.path))
    }

    /// The finding this exists for: a rule somebody wrote by hand, at the name this tool would have used, is not this tool's to delete.
    @Test
    func aguideThisToolDidNotWriteIsLeftInPlace() throws {
        let scratch = try TemporaryDirectory()
        let guide = AgentGuide(destination: Self.destination(in: scratch))
        try FileManager.default.createDirectory(at: guide.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# my own notes on simwalk\n".utf8).write(to: guide.fileURL)

        #expect(try guide.remove() == .notOurs)
        #expect(try String(contentsOf: guide.fileURL, encoding: .utf8) == "# my own notes on simwalk\n")
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
