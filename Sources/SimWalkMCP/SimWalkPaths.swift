//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The per-user locations this tool writes outside a repository, named once so a writer and a reader cannot disagree about where something lives.
///
/// `~/.simwalk` already holds the usage log; the status line's scan cache goes beside it rather than under `~/.claude`, because it is this tool's own state and an uninstall should be able to find all of it in one place.
public struct SimWalkPaths {
    /// The executable's name, which is also the directory this tool owns under `$HOME`.
    public static var binaryName: String {
        "simwalk"
    }

    /// `~/.simwalk` — one directory across every repository, since the usage log and the status line's cache are both per-user rather than per-repo.
    public static var home: URL {
        HomeDirectories.simwalk()
    }

    /// Where the status line keeps one scan state per session — beside the usage log, wherever `SIMWALK_USAGE_LOG` has put it.
    ///
    /// **It follows the log because it is state *about* the log.** Each cached state carries a byte offset into the log it priced, so a cache read against a different log would resume at an offset that means nothing there — and the whole point of moving the log (a test, a review) is that nothing written under the move touches the real one, the status line's cache included.
    public static var statuslineCacheDirectory: URL {
        UsageLog.standard().directory.appendingPathComponent("statusline", isDirectory: true)
    }

    /// Whether `command` runs this tool.
    public static func namesThisTool(_ command: String) -> Bool {
        command.contains(binaryName)
    }
}
