//
// Copyright © Agulhas Labs
//

import Foundation

/// The environment a child of SimWalk gets, with the parent's repository-locating `GIT_*` variables removed.
///
/// **Git exports `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and more into every hook it runs**, and a `git` child that inherits them works on the repository the hook is for, whatever `-C` it was given. A suite run from a pre-push hook once committed fixture commits onto the pushing worktree's `HEAD` that way. So the variables that say *which* repository are removed, and the child targets the checkout it names; the ones that say *how* git runs (`GIT_SSH_COMMAND`, `GIT_CONFIG_*`, credential helpers) are kept, because a package resolution under `xcodebuild` or `swift` may need them.
public struct GitEnvironment {
    /// The variables that point git at a repository, a work tree, an index or an object store.
    static var locating: Set<String> {
        [
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_COMMON_DIR", "GIT_NAMESPACE",
            "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_QUARANTINE_PATH",
            "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM",
        ]
    }

    /// `base` without the repository-locating variables.
    public static func scrubbed(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        base.filter { !locating.contains($0.key) }
    }
}
