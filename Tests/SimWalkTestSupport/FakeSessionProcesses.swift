//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkDriver

/// A runner process a test states: which pids are alive, each one's group and name, and what a spawn does.
///
/// A signal to a group stops every live pid in it when `diesOnSignal`, as `SIGTERM` stops `xcodebuild`.
public final class FakeSessionProcesses: LiveSessionProcesses, @unchecked Sendable {
    public var alive: Set<Int32> = []
    public var groups: [Int32: Int32] = [:]
    public var names: [Int32: String] = [:]
    /// Each pid's start time; a pid with none started long before any session, as a spawned runner did before its record was written.
    public var startTimes: [Int32: Date] = [:]
    /// Live pids whose start time cannot be read.
    public var startTimeUnreadable: Set<Int32> = []
    /// What a spawn throws instead of starting anything, when set.
    public var spawnError: (any Error)?
    public var diesOnSignal = true
    /// Whether a signal to a group with a live member is refused rather than delivered, as `killpg` answers `EPERM`.
    public var refusesSignal = false
    public private(set) var signalled: [(group: Int32, signal: Int32)] = []
    public private(set) var spawned: [RunnerCommand] = []
    /// What the spawned runner does as it starts — writing `ready.json`, say.
    public var onSpawn: (Int32) -> Void = { _ in }
    public var nextPID: Int32 = 4242
    /// What happens once a pid's name has been read — the process exiting between that read and the next, say.
    public var afterNameRead: (Int32) -> Void = { _ in }
    /// What happens as a group is about to be signalled — its process exiting just before, say.
    public var beforeSignal: (Int32) -> Void = { _ in }

    public init() {}

    /// A running `xcodebuild` that leads its own group, as a spawn leaves one.
    public func runner(_ pid: Int32, group: Int32? = nil, name: String = "xcodebuild") {
        alive.insert(pid)
        groups[pid] = group ?? pid
        names[pid] = name
    }

    public func spawn(_ command: RunnerCommand, log _: URL) throws -> Int32 {
        if let spawnError {
            throw spawnError
        }
        spawned.append(command)
        let pid = nextPID
        runner(pid)
        onSpawn(pid)
        return pid
    }

    public func isAlive(_ pid: Int32) -> Bool {
        alive.contains(pid)
    }

    public func processGroup(of pid: Int32) -> Int32? {
        alive.contains(pid) ? groups[pid] : nil
    }

    public func name(of pid: Int32) -> String? {
        let name = alive.contains(pid) ? names[pid] : nil
        afterNameRead(pid)
        return name
    }

    public func startTime(of pid: Int32) -> Date? {
        alive.contains(pid) && !startTimeUnreadable.contains(pid) ? startTimes[pid] ?? .distantPast : nil
    }

    /// A signal to a group with no live member is not delivered, as `killpg` answers `ESRCH`; nor is one ``refusesSignal`` refuses.
    public func signalGroup(_ group: Int32, _ signal: Int32) -> Bool {
        beforeSignal(group)
        signalled.append((group, signal))
        guard alive.contains(where: { groups[$0] == group }), !refusesSignal else { return false }
        if diesOnSignal {
            alive = alive.filter { groups[$0] != group }
        }
        return true
    }
}
