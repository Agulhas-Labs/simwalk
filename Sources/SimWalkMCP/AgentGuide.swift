//
// Copyright © Agulhas Labs
//

import Foundation

/// The agent guide as a Claude Code user rule: installed from a source file, and removed again only if this tool is what put it there.
///
/// **The install stamps what it writes, and the uninstall removes nothing it cannot see its own stamp on.** The path `~/.claude/rules/simwalk.md` is a name anyone could have written by hand — it is the obvious name for notes about this tool — and an uninstall that deleted whatever was sitting there would take somebody's own writing with it. So the copy carries a marker line and the removal looks for it; a file without one is reported and left, exactly as a status line somebody else configured is.
///
/// A symlink is a third case and is left alone in both directions: it points into a checkout, so writing through it would silently revert a working tree to whatever this binary was built beside, and deleting it would take the link.
public struct AgentGuide {
    private let destination: URL

    public init(destination: URL) {
        self.destination = destination
    }

    /// The standard location: a path-scoped user rule, so it costs nothing in a session that never touches a walkbook, a capture bundle or a UI-test target.
    public static func standard() -> AgentGuide {
        AgentGuide(destination: SimWalkPaths.claudeRule)
    }

    /// The file this installs to, and the only one it will ever remove.
    public var fileURL: URL {
        destination
    }

    /// Copies `source` into place, stamped, reporting what it did.
    public func install(from source: URL) throws -> Outcome {
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path) {
            return .symlink(target: target)
        }
        let stamped = try Self.stamped(String(contentsOf: source, encoding: .utf8))
        if let existing = try? String(contentsOf: destination, encoding: .utf8), existing == stamped {
            return .unchanged
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(stamped.utf8).write(to: destination, options: .atomic)
        return .installed
    }

    /// Removes the guide, but only the one this tool wrote.
    ///
    /// Absence is decided on the file existing rather than on it being readable, for the reason the status-line shim's removal is: a file this cannot read is not a file that is not there, and saying so would report a clean sweep over one still in place.
    public func remove() throws -> Removal {
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path) {
            return .symlink(target: target)
        }
        guard FileManager.default.fileExists(atPath: destination.path) else { return .absent }
        guard let existing = try? String(contentsOf: destination, encoding: .utf8), Self.isOurs(existing) else {
            return .notOurs
        }
        try FileManager.default.removeItem(at: destination)
        return .removed
    }

    /// Whether a rule file carries this tool's stamp.
    public static func isOurs(_ contents: String) -> Bool {
        contents.contains(marker)
    }

    /// The line an installed copy carries, and the only thing an uninstall trusts.
    ///
    /// An HTML comment appended at the end rather than a line at the top, because the guide opens with YAML frontmatter that decides when it loads: anything inserted above the opening `---` stops it being frontmatter at all, and the rule would then load in every session or in none.
    public static var marker: String {
        "<!-- installed by `\(SimWalkPaths.binaryName) install-hook` — `\(SimWalkPaths.binaryName) uninstall-hook` removes it, and the next install overwrites it -->"
    }

    static func stamped(_ contents: String) -> String {
        isOurs(contents) ? contents : contents + (contents.hasSuffix("\n") ? "" : "\n") + marker + "\n"
    }
}

public extension AgentGuide {
    /// What the install did, so it can be reported rather than claimed.
    enum Outcome: Equatable, Sendable {
        case installed
        /// Already there, byte for byte — the re-run case.
        case unchanged
        /// A link into a checkout, which the install will not write through.
        case symlink(target: String)
    }

    /// What the removal did, so an uninstall can report it rather than claim a clean sweep.
    enum Removal: Equatable, Sendable {
        case removed
        /// Nothing was there.
        case absent
        /// A file without this tool's stamp — somebody's own, and not this one's to delete.
        case notOurs
        /// A link into a checkout, which the uninstall will not follow.
        case symlink(target: String)
    }
}
