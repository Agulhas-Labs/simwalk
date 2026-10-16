//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// What `git` says about a working tree, asked the way a snapshot needs it asked: whether its files are exactly its `HEAD`.
///
/// **"Clean" has to mean the bytes on disk are the commit's, and `git status` alone does not say that** (the SimWalk#16 review, reproduced in a scratch repository). `status.showUntrackedFiles=no` in somebody's config hides an untracked file that a snapshot then copies, and a file marked `--skip-worktree` or `--assume-unchanged` reads clean with local edits in it. Either way a snapshot named for a clean commit would hold code that is not that commit. So untracked files are asked for explicitly, whatever the config says, and any file `git` has been told to stop looking at makes the tree dirty — its bytes are not something `git` can vouch for.
public struct GitWorkingTree {
    /// The full SHA of `HEAD`.
    public static func head(of root: URL, run: (String, [String]) throws -> Shell.Result) throws -> String {
        try git(["rev-parse", "HEAD"], in: root, run: run).trimmed
    }

    /// Whether the tree holds anything other than `HEAD`: a change, an untracked file, or a file `git` has been told not to look at.
    public static func isDirty(_ root: URL, run: (String, [String]) throws -> Shell.Result) throws -> Bool {
        let changed = try !git(["status", "--porcelain", "--untracked-files=all"], in: root, run: run).trimmed.isEmpty
        // `ls-files -v` tags a skip-worktree file `S` and an assume-unchanged one with a lowercase letter.
        let unwatched = try git(["ls-files", "-v"], in: root, run: run)
            .split(separator: "\n")
            .contains { line in line.first.map { $0 == "S" || $0.isLowercase } ?? false }
        return changed || unwatched
    }

    /// Every file a build of the tree could read — tracked and untracked, ignored ones left out — as paths relative to `root`, sorted.
    public static func files(of root: URL, run: (String, [String]) throws -> Shell.Result) throws -> [String] {
        try git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], in: root, run: run)
            .split(separator: "\0")
            .map(String.init)
            .filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
            .sorted()
    }

    private static func git(_ arguments: [String], in root: URL, run: (String, [String]) throws -> Shell.Result) throws -> String {
        let result = try run("/usr/bin/git", ["-C", root.path] + arguments)
        guard result.succeeded else {
            throw RunnerStoreError.notACheckout(path: root.path, reason: result.failureLine)
        }
        return result.standardOutput
    }
}
