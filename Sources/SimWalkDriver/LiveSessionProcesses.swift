//
// Copyright © Agulhas Labs
//

import Foundation

/// The process calls a live session makes on its runner — spawning it, and every check made before it is signalled.
///
/// A protocol so a test drives the start and the end procedure against a fake process whose group, name and lifetime it states; ``LiveSessionSystemProcesses`` is the real one.
public protocol LiveSessionProcesses: Sendable {
    /// Starts `command` in a process group of its own, stdin `/dev/null`, stdout and stderr appended to `log`; returns its pid.
    func spawn(_ command: RunnerCommand, log: URL) throws -> Int32
    /// Whether `pid` is still running — a zombie is not, though it still answers `kill(pid, 0)`: it has exited and is only waiting for a parent to reap it.
    func isAlive(_ pid: Int32) -> Bool
    /// `getpgid(pid)`; `nil` once it is gone.
    func processGroup(of pid: Int32) -> Int32?
    /// The process's short name; `nil` once it is gone.
    func name(of pid: Int32) -> String?
    /// When the process started (`kp_proc.p_starttime`); `nil` once it is gone.
    func startTime(of pid: Int32) -> Date?
    /// `killpg(group, signal)`; whether it was delivered.
    func signalGroup(_ group: Int32, _ signal: Int32) -> Bool
}

public extension LiveSessionProcesses {
    /// Why the process now at `record.pid` is not the runner that record was written for — it started after the record, so the pid was reused; `nil` when it is that runner, or is gone.
    ///
    /// The start time is allowed a second past the record's, which is written to the second (ISO 8601) just after the spawn. A start time that cannot be read is not a pass: the answer says so.
    func reuse(of record: LiveSessionRecord) -> String? {
        guard isAlive(record.pid) else { return nil }
        guard let started = startTime(of: record.pid) else {
            return "its start time could not be read"
        }
        let late = started.timeIntervalSince(record.startedAt)
        return late > 1 ? "it started \(Int(late)) s after this session's record was written" : nil
    }

    /// Whether the runner this record was written for is running: its pid is alive and was not started after the record, so it is not a stranger holding a reused number.
    func isRunning(_ record: LiveSessionRecord) -> Bool {
        isAlive(record.pid) && reuse(of: record) == nil
    }
}
