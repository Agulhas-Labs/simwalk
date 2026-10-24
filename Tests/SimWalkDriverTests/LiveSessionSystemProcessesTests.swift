//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// The real launcher, against `/bin/sh` rather than `xcodebuild`: its own process group, its output in the log, and a child that has exited never reported alive.
struct LiveSessionSystemProcessesTests {
    /// The spawned child leads a group of its own, and a signal to that group stops it.
    @Test
    func aspawnedRunnerLeadsItsOwnGroupAndStopsOnASignalToIt() throws {
        let directory = try TemporaryDirectory()
        let processes = LiveSessionSystemProcesses()
        let pid = try processes.spawn(RunnerCommand(executable: "/bin/sleep", arguments: ["30"], environment: [:]), log: directory.url.appendingPathComponent("runner.log"))

        #expect(processes.processGroup(of: pid) == pid)
        #expect(processes.name(of: pid) == "sleep")
        #expect(processes.isAlive(pid))
        #expect(processes.signalGroup(pid, SIGTERM))
        #expect(Self.waitForExit(pid, processes))
    }

    /// stdout and stderr both land in the log, the environment arrives, and the exited child is reaped rather than read as a live zombie.
    @Test
    func outputGoesToTheLogAndAnExitedChildIsNotAlive() throws {
        let directory = try TemporaryDirectory()
        let log = directory.url.appendingPathComponent("runner.log")
        let processes = LiveSessionSystemProcesses()
        let command = RunnerCommand(executable: "/bin/sh", arguments: ["-c", "echo out $SIMWALK_FAKE; echo err >&2; read line || echo stdin-closed"], environment: ["SIMWALK_FAKE": "given"])

        let pid = try processes.spawn(command, log: log)

        #expect(Self.waitForExit(pid, processes))
        #expect(try String(contentsOf: log, encoding: .utf8) == "out given\nerr\nstdin-closed\n")
    }

    /// A process that has exited but that its parent has not reaped is not alive — the runner an MCP server spawned, read from another process — though it still answers `kill(pid, 0)`.
    @Test
    func anExitedChildItsParentHasNotReapedIsNotAlive() throws {
        let directory = try TemporaryDirectory()
        let log = directory.url.appendingPathComponent("runner.log")
        let processes = LiveSessionSystemProcesses()
        // The shell starts a short sleep, prints its pid and becomes a long one, which never reaps the short one.
        let parent = try processes.spawn(RunnerCommand(executable: "/bin/sh", arguments: ["-c", "/bin/sleep 0.5 & echo $!; exec /bin/sleep 30"], environment: [:]), log: log)
        defer {
            _ = processes.signalGroup(parent, SIGTERM)
            _ = Self.waitForExit(parent, processes)
        }
        let child = try #require(Self.firstLine(of: log).flatMap { Int32($0) })

        let exited = Self.waitForExit(child, processes)

        #expect(exited)
        #expect(kill(child, 0) == 0, "the premise: it is still there, unreaped")
    }

    /// A spawned runner is reaped by the process that spawned it once it exits, so it never lingers as a zombie another process would have to read.
    @Test
    func aspawnedRunnerIsReapedWhenItExits() throws {
        let directory = try TemporaryDirectory()
        let processes = LiveSessionSystemProcesses()

        let pid = try processes.spawn(RunnerCommand(executable: "/usr/bin/true", arguments: [], environment: [:]), log: directory.url.appendingPathComponent("runner.log"))

        // Two minutes, as `waitForExit` allows: a loaded machine can take seconds to run the reaper (SimWalk#209).
        let deadline = Date().addingTimeInterval(120)
        while kill(pid, 0) == 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }

    /// The log's first line once one is written, waited for up to two minutes: a loaded machine can take seconds to schedule the child (SimWalk#209), and a line already written returns at once.
    private static func firstLine(of log: URL) -> String? {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if let text = try? String(contentsOf: log, encoding: .utf8), let line = text.split(separator: "\n").first {
                return String(line)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    /// Whether `pid` has exited, waited for up to two minutes: a loaded machine can take seconds to deliver a signal and reap (SimWalk#209), and a process already gone returns at once.
    fileprivate static func waitForExit(_ pid: Int32, _ processes: LiveSessionSystemProcesses) -> Bool {
        let deadline = Date().addingTimeInterval(120)
        while processes.isAlive(pid), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return !processes.isAlive(pid)
    }
}

extension LiveSessionSystemProcessesTests {
    /// A progress claim handed to a spawned runner stays held after the host lets go, for exactly as long as the runner lives (SimWalk#83): a run starting meanwhile takes the next slot, and the first is free again once the runner exits.
    @Test
    func aClaimSharedWithTheRunnerIsHeldUntilTheRunnerExits() throws {
        let directory = try TemporaryDirectory()
        let processes = LiveSessionSystemProcesses()
        var claim: ProgressClaim? = ProgressClaim.take(session: "s", in: directory.url, sharedWithChild: true)
        let first = try #require(claim?.progressURL)
        let pid = try processes.spawn(
            RunnerCommand(executable: "/bin/sleep", arguments: ["30"], environment: [:], inheritedDescriptor: claim?.descriptorForChild),
            log: directory.url.appendingPathComponent("runner.log")
        )
        defer {
            _ = processes.signalGroup(pid, SIGKILL)
            _ = Self.waitForExit(pid, processes)
        }
        claim?.markHandedOver()
        claim = nil

        let whileRunning = ProgressClaim.take(session: "s", in: directory.url).progressURL
        _ = processes.signalGroup(pid, SIGTERM)
        let exited = Self.waitForExit(pid, processes)
        let afterExit = Self.take(first, session: "s", in: directory.url)

        #expect(whileRunning != first)
        #expect(exited)
        #expect(afterExit == first)
    }

    /// The claim at `wanted` once it is free, waited for rather than tried once; the slot taken instead if it is still held after two minutes.
    ///
    /// The runner's own hold ends before it is seen to exit: the kernel closes an exiting process's descriptors before it marks it a zombie. But a test beside this one spawning at the same moment holds a copy of the claim's descriptor from its fork until its exec, since a spawn copies a close-on-exec descriptor and closes it only at exec, and the lock outlives the runner until that spawn's exec, which a loaded machine can delay (SimWalk#204). A hold that never ends still fails.
    private static func take(_ wanted: URL, session: String, in directory: URL) -> URL {
        let deadline = Date().addingTimeInterval(120)
        var taken = ProgressClaim.take(session: session, in: directory).progressURL
        while taken != wanted, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
            taken = ProgressClaim.take(session: session, in: directory).progressURL
        }
        return taken
    }
}
