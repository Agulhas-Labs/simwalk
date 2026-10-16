//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation

/// The process a lease lives as long as, and whether it is still running.
///
/// `simwalk lease acquire` exits the moment it prints, and so does the shell a coding agent runs it from, so neither can be the holder: a lease held by either would be reclaimable before the walk it was taken for had started. The holder is the nearest ancestor that is not a shell — the agent's own process, or a terminal's login — which lives as long as the session asking.
public struct HolderProcess {
    /// Whether `pid` names a running process — `EPERM` is a process that exists and belongs to somebody else.
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    /// The nearest ancestor of this process that is not a shell or a command wrapper; the topmost of them when every ancestor below `launchd` is one.
    public static func sessionHolder() -> Int32 {
        var pid = getppid()
        while let process = info(of: pid), transient.contains(process.name), process.parent > 1 {
            pid = process.parent
        }
        return pid
    }

    /// A warning when `holder` is this command's own parent and not a process known to outlive it, `nil` otherwise.
    ///
    /// The holder search skips only the shells and wrappers it knows, so under any other wrapper (`sift run --`, make, python, npx, script, caffeinate) the parent it stops at exits with the command, and the lease is reclaimable at once. `parent` and `name` are injectable for a test.
    public static func unverifiedHolderWarning(holder: Int32, parent: Int32 = getppid(), name: String? = nil) -> String? {
        guard holder == parent else { return nil }
        let processName = name ?? Self.name(of: holder) ?? "unknown"
        guard !longLived.contains(processName) else { return nil }
        return "the holder is pid \(holder) (\(processName)), this command's parent, which may exit with it and free the lease at once — pass --holder-pid <pid> naming the session's long-lived process"
    }

    /// A process's short name, for a listing; `nil` once it is gone.
    public static func name(of pid: Int32) -> String? {
        info(of: pid)?.name
    }

    /// Processes that start and end with one command, and so cannot hold a lease past it.
    static let transient: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "ksh", "tcsh", "csh", "env", "nohup", "timeout", "xargs", "sandbox-exec"]

    /// Direct parents known to live as long as the session asking: the agent and the terminals.
    static let longLived: Set<String> = ["claude", "login", "Terminal", "iTerm2", "tmux", "screen", "sshd", "Warp", "ghostty", "kitty", "alacritty", "WezTerm"]

    private static func info(of pid: Int32) -> (name: String, parent: Int32)? {
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&query, 4, &process, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: process.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (name, process.kp_eproc.e_ppid)
    }
}
