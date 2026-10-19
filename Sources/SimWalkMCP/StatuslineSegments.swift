//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The segment file this tool contributes to sift's status line.
///
/// Claude Code has **one** `statusLine` slot. sift takes it and runs every executable in `~/.sift/statusline.d/` with the same status-line JSON on stdin, appending each one's first line of output to its own — so on a machine that has sift, a second tool asking for the slot is a fight nobody needs, and dropping a script in that directory is the whole registration. Where sift is absent, ``StatuslineRegistration`` takes the slot directly.
///
/// The script is a two-line shim rather than a symlink to the binary, because sift hands the file its stdin and expects a first line back: the shim is where `statusline` — the subcommand that reads that JSON — is named.
public struct StatuslineSegments {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The standard location: sift's own segment directory.
    public static func standard() -> StatuslineSegments {
        StatuslineSegments(directory: siftHome.appendingPathComponent("statusline.d", isDirectory: true))
    }

    /// Whether sift is on this machine to carry a segment at all.
    ///
    /// Decided on sift's home directory rather than on its binary: the directory is what sift itself keys everything else off, and a machine that has run sift once has it.
    public static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: siftHome.path)
    }

    /// The file this tool writes, and the only one it will ever remove.
    public var fileURL: URL {
        directory.appendingPathComponent(SimWalkPaths.binaryName)
    }

    /// Writes the shim, reporting whether anything changed.
    ///
    /// Rewritten when the binary has moved and left alone when it has not, so re-running `install-hook` on every upgrade is free and an install to a different path repoints rather than duplicating. The executable bit is part of what is checked: a segment file sift cannot run is a status line that silently lost half of itself.
    public func install(executable: String) throws -> Outcome {
        let script = Self.script(executable: executable)
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8),
           existing == script, FileManager.default.isExecutableFile(atPath: fileURL.path)
        {
            return .unchanged
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
        return .written
    }

    /// Removes the shim, but only when it is the one this tool wrote.
    ///
    /// Absence is decided on the file existing, not on it being readable as text: a binary somebody dropped at this path is emphatically *not* ours, and reporting it as "nothing was there" would claim a clean sweep over a file still sitting in another tool's directory.
    public func remove() throws -> Removal {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
        guard let existing = try? String(contentsOf: fileURL, encoding: .utf8), Self.isOurs(existing) else {
            return .notOurs
        }
        try FileManager.default.removeItem(at: fileURL)
        return .removed
    }

    /// Whether a segment file found at our path is one of ours.
    ///
    /// Checked rather than assumed from the file's name: the directory belongs to another tool, and a file there that this one did not write is not this one's to delete.
    public static func isOurs(_ script: String) -> Bool {
        SimWalkPaths.namesThisTool(script) && script.contains("statusline")
    }
}

private extension StatuslineSegments {
    /// sift's per-user directory, which is where its segment directory lives.
    static var siftHome: URL {
        HomeDirectories.sift()
    }

    static func script(executable: String) -> String {
        """
        #!/bin/sh
        # Written by `\(SimWalkPaths.binaryName) install-hook`; removed by `\(SimWalkPaths.binaryName) uninstall-hook`.
        exec "\(executable)" statusline

        """
    }
}

public extension StatuslineSegments {
    /// What the install did, so it can be reported rather than claimed.
    enum Outcome: Equatable, Sendable {
        case written
        /// Already there, pointing at this binary — the re-run case.
        case unchanged
    }

    /// What the removal did, so an uninstall can report it rather than claim a clean sweep.
    enum Removal: Equatable, Sendable {
        case removed
        /// Nothing of ours was there.
        case absent
        /// A file this tool did not write sits at our path, and an uninstall will not take it.
        case notOurs
    }
}
