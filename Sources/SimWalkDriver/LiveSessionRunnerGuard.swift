//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkCore

/// The guarded stop of a session's runner process, shared by the simulator's ``LiveSessionStop`` and the device's ``LiveSessionDeviceStop``: identify the recorded pid, ask the runner to end, wait, and signal its group only when every guard passes.
///
/// **A signal reaches the recorded pid's group and nothing else, and only when that pid leads its own group, is `xcodebuild`, and started no later than the session's record** — the rules and their reasons are ``LiveSessionStop``'s. Both targets spawn their runner the same way, so the guards are one code path.
struct LiveSessionRunnerGuard {
    let record: LiveSessionRecord
    let processes: any LiveSessionProcesses
    /// How long the runner is given to exit after it is asked to end, and again after `SIGTERM`.
    let grace: TimeInterval
    /// What the runner was waited on after, as a signal's step names it: `end`, or the stop's start when `end` could not be sent.
    let waitedAfter: String

    /// Stops the runner: a pid that is not this session's runner is left alone; this session's runner is asked to end by `askToEnd` (whose line, when it returns one, is a step), waited on for `grace`, and signalled when it is still running.
    func stop(steps: inout [String], askToEnd: () -> String?, pause: (TimeInterval) -> Void, now: () -> Date) -> Outcome {
        let pid = record.pid
        switch processes.isAlive(pid) ? identify() : .gone {
        case let .stranger(reason):
            steps.append("pid \(pid) is running and was left alone: \(reason), so it is not the runner this session started — that runner has exited")
            return Outcome(sawRunner: false, stillRunning: false)
        case .runner:
            let deadline = now().addingTimeInterval(grace)
            if let line = askToEnd() {
                steps.append(line)
            }
            waitForExit(until: deadline, pause: pause, now: now)
            guard processes.isRunning(record) else {
                steps.append("the runner (pid \(pid)) exited")
                return Outcome(sawRunner: true, stillRunning: false)
            }
            return Outcome(sawRunner: true, stillRunning: signal(steps: &steps, pause: pause, now: now))
        case .gone:
            steps.append("the runner (pid \(pid)) had already exited")
            return Outcome(sawRunner: false, stillRunning: false)
        }
    }

    /// Waits while this session's runner is running — not merely while its pid is alive, since a pid reused meanwhile is the runner gone (SimWalk#77).
    func waitForExit(until deadline: Date, pause: (TimeInterval) -> Void, now: () -> Date) {
        while processes.isRunning(record), now() < deadline {
            pause(LiveSessionChannel.pollInterval)
        }
    }

    /// Signals the runner's group when the guards allow it; whether it is still running afterwards.
    private func signal(steps: inout [String], pause: (TimeInterval) -> Void, now: () -> Date) -> Bool {
        let pid = record.pid
        let wait = "still running \(Int(grace)) s after \(waitedAfter)"
        switch identify() {
        case let .stranger(reason):
            steps.append("pid \(pid) is \(wait) and was not signalled: \(reason), so it is not the runner this session started — that runner has exited")
            return false
        case .gone:
            steps.append("the runner (pid \(pid)) exited as it was being checked, before it could be signalled")
            return false
        case .runner:
            break
        }
        guard processes.signalGroup(pid, SIGTERM) else {
            guard processes.isRunning(record) else {
                steps.append("the runner (pid \(pid)) exited before SIGTERM reached its process group")
                return false
            }
            steps.append("pid \(pid) is \(wait), and SIGTERM to its process group was not delivered")
            return true
        }
        waitForExit(until: now().addingTimeInterval(grace), pause: pause, now: now)
        // A pid reused during the grace is the runner gone: telling the user to `kill -TERM -<pid>` would stop a stranger.
        let alive = processes.isRunning(record)
        steps.append("pid \(pid) was \(wait): sent SIGTERM to its process group; \(alive ? "it is still running — kill -TERM -\(pid)" : "it exited")")
        return alive
    }

    /// Whether the process at the record's pid is the runner this session started, a stranger holding its number, or gone.
    ///
    /// The start-time rule is ``LiveSessionProcesses/reuse(of:)``. A read that comes back empty — or ``LiveSessionProcesses/reuse(of:)`` passing a pid only because it is no longer alive — is told apart by a liveness check after the reads: a pid gone by then has exited, whatever the reads said (SimWalk#75).
    private func identify() -> Identity {
        let pid = record.pid
        let reason: String?
        if processes.processGroup(of: pid) != pid {
            reason = "it does not lead its own process group"
        } else {
            let name = processes.name(of: pid)
            reason = name == Self.runnerName ? processes.reuse(of: record) : "it is \(name ?? "unnamed"), not \(Self.runnerName)"
        }
        guard processes.isAlive(pid) else { return .gone }
        return reason.map(Identity.stranger) ?? .runner
    }

    static var runnerName: String {
        "xcodebuild"
    }
}

extension LiveSessionRunnerGuard {
    /// What ``stop(steps:askToEnd:pause:now:)`` found and left.
    struct Outcome: Equatable {
        /// Whether the pid was this session's runner, running when the stop began — so it was asked to end, and its exit seen now rather than earlier.
        let sawRunner: Bool
        /// Whether it is still running after the stop, so its session must be kept.
        let stillRunning: Bool
    }

    /// What ``identify()`` found at the session's pid.
    enum Identity {
        case runner
        case gone
        case stranger(String)
    }
}
