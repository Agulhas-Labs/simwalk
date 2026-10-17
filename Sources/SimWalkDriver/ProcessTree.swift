//
// Copyright © Agulhas Labs
//

import Foundation

/// The command lines of a process and of everything under it, read in-process from the kernel's process table — what a stalled child was waiting on, read before it is stopped (SimWalk#136).
///
/// Nothing is spawned to read it: a `ps` started at the moment a call has already outlived its bound would be one more child to wait on. Best-effort by design — a process that exits between the two reads, or whose arguments cannot be read, is simply absent, so the answer can only ever lack evidence, never invent it.
struct ProcessTree {
    /// The arguments of `root`, every member of `group`, and every descendant of either, by parent — so a descendant that left the group is still read.
    static func commandLines(of root: pid_t, group: pid_t?) -> [[String]] {
        let table = processTable()
        var members: Set<pid_t> = [root]
        if let group {
            members.formUnion(table.filter { $0.group == group }.map(\.pid))
        }
        var frontier = Array(members)
        while let parent = frontier.popLast() {
            for entry in table where entry.parent == parent && !members.contains(entry.pid) {
                members.insert(entry.pid)
                frontier.append(entry.pid)
            }
        }
        return members.sorted().compactMap(arguments(of:))
    }

    /// Every process's pid, parent and group, from `KERN_PROC_ALL`; empty when the table cannot be read.
    private static func processTable() -> [Entry] {
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&query, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Room for processes started between the size query and the read.
        size += size / 4
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        // The bytes actually allocated, which is the array's whole number of entries, not the padded size asked for.
        size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&query, 4, &processes, &size, nil, 0) == 0 else { return [] }
        return processes.prefix(size / MemoryLayout<kinfo_proc>.stride).map { Entry(pid: $0.kp_proc.p_pid, parent: $0.kp_eproc.e_ppid, group: $0.kp_eproc.e_pgid) }
    }

    /// `pid`'s argument vector, from `KERN_PROCARGS2`.
    ///
    /// The layout is `argc`, the executable's path, padding, then the arguments, each NUL-terminated. An empty argument is dropped with the padding, which costs a match nothing.
    private static func arguments(of pid: pid_t) -> [String]? {
        var maximumQuery: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var maximum: Int32 = 0
        var maximumSize = MemoryLayout<Int32>.size
        guard sysctl(&maximumQuery, 2, &maximum, &maximumSize, nil, 0) == 0, maximum > 0 else { return nil }
        var query: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var buffer = [UInt8](repeating: 0, count: Int(maximum))
        var size = buffer.count
        let countSize = MemoryLayout<Int32>.size
        guard sysctl(&query, 3, &buffer, &size, nil, 0) == 0, size > countSize else { return nil }
        let count = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        let fields = buffer[countSize ..< size].split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        return Array(fields.dropFirst().prefix(Int(count)))
    }
}

extension ProcessTree {
    /// One row of the process table: a process, its parent and its group.
    struct Entry {
        let pid: pid_t
        let parent: pid_t
        let group: pid_t
    }
}
