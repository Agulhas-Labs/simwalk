//
// Copyright © Agulhas Labs
//

import Foundation

/// The CLI's sanctioned output path: stdout is the product, stderr the complaint channel.
///
/// Deliberately avoids the global printing helper — the repo bans it as a logging habit, and a CLI should be explicit about which stream it writes anyway (the MCP face makes stdout discipline load-bearing).
struct StandardStreams {
    /// One-time SIGPIPE suppression so `simwalk … | head` ends quietly instead of dying at the write syscall.
    private static let ignoreSigpipe: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    static func emit(_ text: String) {
        _ = ignoreSigpipe
        try? FileHandle.standardOutput.write(contentsOf: Data((text + "\n").utf8))
    }

    static func emitError(_ text: String) {
        _ = ignoreSigpipe
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
    }

    /// Whether stdout is a pipe — the seam `TimedCall` reads to decide whether its exit-code nudge is worth printing (SimWalk#40).
    ///
    /// A pipe, not merely "not a terminal": `simwalk … > out.txt` is a file, `$?` is right there, and the `PIPESTATUS` advice would be wrong and land in the captured output (SimWalk#114).
    static func isStdoutPiped() -> Bool {
        isPipe(STDOUT_FILENO)
    }

    /// True only when `descriptor` is a FIFO.
    ///
    /// A regular file, `/dev/null`, a socket or a terminal is not a pipeline whose status hides this process's own. A failed `fstat` answers false: no nudge beats a wrong one (SimWalk#114).
    static func isPipe(_ descriptor: Int32) -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFIFO
    }
}
