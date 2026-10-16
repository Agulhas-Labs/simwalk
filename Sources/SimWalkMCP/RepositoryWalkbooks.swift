//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The walkbooks a repository keeps where the agent guide says a repository keeps them — `Docs/Walkbooks/*.json` — found from a session's working directory (SimWalk#12).
///
/// **Two places, because a session stands anywhere in a repository.** The working directory's own `Docs/Walkbooks`, and the one at the root of the git working tree it is in, found by walking up to the nearest `.git` — a file in a worktree, a directory in a checkout — rather than by running `git`, since this is read before every shell call a session makes and on every status-line render. Nothing above the working tree is looked at: a walkbook in a parent repository is not this repository's.
///
/// Each path is spelled relative to the working directory, `..` and all, because it is handed back as the argument of a `simwalk walk` the session will run from there.
public struct RepositoryWalkbooks {
    /// The directory a walkbook is kept in, relative to a repository's root.
    public static var directory: String {
        "Docs/Walkbooks"
    }

    /// Every `*.json` in the walkbook directories that serve `workingDirectory`, in name order, each spelled relative to it — whether or not it loads.
    public static func candidates(from workingDirectory: String) -> [String] {
        // Resolved first: the walk up to `.git` and the `../` prefix it hands back are both computed
        // lexically, but the kernel resolves a path with `..` in it physically — so a working directory
        // reached through a symlinked directory would have its offered path resolve somewhere else
        // entirely, and the load in ``loaded(from:)`` would fail silently (SimWalk#37 item 1).
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true).resolvingSymlinksInPath()
        var found: [String] = []
        for (depth, root) in roots(from: base) {
            let folder = root.appendingPathComponent(directory, isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            let prefix = String(repeating: "../", count: depth)
            found += names.sorted().filter { $0.hasSuffix(".json") }.map { prefix + directory + "/" + $0 }
        }
        return found
    }

    /// Whether `workingDirectory` is served by a walkbook that loads — the status line's question, asked with the same test the hook offers by (SimWalk#37 item 4): a `*.json` that does not load is not a walkbook either can do anything with, so neither says one is here.
    public static func exist(from workingDirectory: String) -> Bool {
        !loaded(from: workingDirectory).isEmpty
    }

    /// The walkbooks that serve `workingDirectory` and load — a file that does not is not one a walk could run, so it is not offered.
    public static func loaded(from workingDirectory: String) -> [Found] {
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true).resolvingSymlinksInPath()
        return candidates(from: workingDirectory).compactMap { path in
            guard let walkbook = try? WalkbookLoader.load(contentsOf: base.appendingPathComponent(path)) else { return nil }
            return Found(path: path, screens: walkbook.screens.count, states: walkbook.screens.reduce(0) { $0 + $1.states.count })
        }
    }
}

public extension RepositoryWalkbooks {
    /// One walkbook that loads: where it is from the working directory, and what one walk of it captures.
    struct Found: Equatable, Sendable {
        /// The path a `simwalk walk` run from the working directory is handed.
        public let path: String

        /// The screens one walk visits.
        public let screens: Int

        /// The states captured across them — each a screenshot and an accessibility tree.
        public let states: Int
    }
}

private extension RepositoryWalkbooks {
    /// The working directory, and the root of the working tree it is in where that is somewhere else — each with how many levels above the working directory it stands.
    ///
    /// The working directory alone when it is in no working tree.
    static func roots(from base: URL) -> [(depth: Int, url: URL)] {
        var current = base
        var depth = 0
        while !FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return [(0, base)] }
            current = parent
            depth += 1
        }
        return depth == 0 ? [(0, base)] : [(0, base), (depth, current)]
    }
}
