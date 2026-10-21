//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation

/// When a process started, behind a seam so a test can fake a live, dead or reused pid.
///
/// The dead-process rule (`Docs/SIMWALK-PROGRESS.md` §3) is that a process is the walk's only if its pid exists **and** it started no later than the progress file's `startedAt`: a pid the system reused for a later process started after the walk did.
public struct WalkProcessProbe: Sendable {
    /// The start time of the process `pid`, or `nil` when no such process exists or it is a zombie: one that has exited and waits only for its parent to reap it.
    public let startTime: @Sendable (Int32) -> Date?

    public init(startTime: @escaping @Sendable (Int32) -> Date?) {
        self.startTime = startTime
    }

    /// Whether `pid` is the process that wrote a file started at `startedAt`.
    func isAlive(pid: Int32, since startedAt: Date) -> Bool {
        guard let started = startTime(pid) else {
            return false
        }
        return started <= startedAt
    }

    /// The system's answer, from `sysctl(KERN_PROC_PID)`; a zombie (`SZOMB`) is no process, so a walk whose server was killed and not yet reaped reads as exited.
    public static let system = WalkProcessProbe { pid in
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid,
              Int32(info.kp_proc.p_stat) != SZOMB
        else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
