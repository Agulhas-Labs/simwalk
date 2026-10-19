//
// Copyright © Agulhas Labs
//

import Darwin
import Fieldwork
import Foundation

/// The real ``LiveSessionProcesses``: `posix_spawn`, `waitpid`, `sysctl`, `getpgid`, `killpg`.
public struct LiveSessionSystemProcesses: LiveSessionProcesses {
    public init() {}

    /// Starts the runner detached from the caller's process group and descriptors.
    ///
    /// **Reaped by the process that spawned it, whenever it exits.** A runner spawned by `simwalk mcp` is a child of a server that outlives it, and only that server can reap it: left unreaped it is a zombie, which still answers `kill(pid, 0)`, so a CLI `end` read a dead runner as one that would not stop and `start` refused its device. A thread per runner waits on it (``reapOnExit(_:)``); a CLI `start` exits long before its runner, which `launchd` then reaps.
    ///
    /// **Its own process group** (`POSIX_SPAWN_SETPGROUP`), so a signal meant for the caller's shell or tool call never reaches the runner, and the end procedure's `killpg` reaches `xcodebuild`'s children and nothing else. **`POSIX_SPAWN_CLOEXEC_DEFAULT`**, so the only descriptors it inherits are the three set here — never an MCP client's pipe (SimWalk#27) — and the command's ``RunnerCommand/inheritedDescriptor``, the session's progress claim, when it names one.
    public func spawn(_ command: RunnerCommand, log: URL) throws -> Int32 {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Signals reset too: a child inherits its parent's mask and ignored signals, and a runner spawned from a
        // caller that blocks or ignores `SIGTERM` would never stop on the end procedure's signal.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attributes, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var everySignal = sigset_t()
        sigfillset(&everySignal)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        if let inherited = command.inheritedDescriptor {
            posix_spawn_file_actions_addinherit_np(&actions, inherited)
        }

        let environment = GitEnvironment.scrubbed().merging(command.environment) { _, new in new }
        let argv = ([command.executable] + command.arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, command.executable, &actions, &attributes, argv, envp)
        guard status == 0 else {
            throw RunnerError.walkFailed(reason: "could not start \(command.executable): \(String(cString: strerror(status)))")
        }
        Self.reapOnExit(pid)
        return pid
    }

    /// A zombie is not alive: it has exited and waits only for its parent to reap it, which may be another process — a runner `simwalk mcp` spawned, read from a CLI `end`.
    public func isAlive(_ pid: Int32) -> Bool {
        guard HolderProcess.isAlive(pid) else { return false }
        guard let process = Self.info(of: pid) else { return true }
        return Int32(process.kp_proc.p_stat) != SZOMB
    }

    public func processGroup(of pid: Int32) -> Int32? {
        let group = getpgid(pid)
        return group < 0 ? nil : group
    }

    public func name(of pid: Int32) -> String? {
        HolderProcess.name(of: pid)
    }

    public func startTime(of pid: Int32) -> Date? {
        guard let started = Self.info(of: pid)?.kp_proc.p_un.__p_starttime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }

    public func signalGroup(_ group: Int32, _ signal: Int32) -> Bool {
        killpg(group, signal) == 0
    }

    /// Waits for `pid` on a thread of its own and reaps it when it exits.
    ///
    /// A blocking `waitpid` rather than a dispatch process source, because a source registers asynchronously and a child that exits before the registration lands is never reported; `waitpid` on a child that has already exited returns at once.
    static func reapOnExit(_ pid: pid_t) {
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        }
    }

    /// `pid`'s `kinfo_proc`; `nil` once it is gone.
    private static func info(of pid: Int32) -> kinfo_proc? {
        guard pid > 0 else { return nil }
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&query, 4, &process, &size, nil, 0) == 0, size > 0 else { return nil }
        return process
    }
}
