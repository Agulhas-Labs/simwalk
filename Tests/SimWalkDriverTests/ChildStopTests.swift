//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// A parallel walk stops the other shards' children when one shard fails, so a stopped child has to end, take what it started in its group with it, and make its `run` say it was stopped — and a shell nobody gave the stop to must not notice.
struct ChildStopTests {
    /// A child stopped while it runs is gone, and its `run` throws `stopped` promptly rather than waiting out the child or its bound.
    @Test
    func aRunningChildStoppedMidRunMakesItsRunThrowStoppedAndIsGone() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let pidFile = scratch.file("child.pid")
        let childStop = ChildStop()
        let outcome = Outcome()

        DispatchQueue.global().async {
            outcome.record { try Shell().stopped(by: childStop).run("/bin/sh", ["-c", "echo $$ > '\(pidFile.path)'; exec /bin/sleep 30"], timeout: 20) }
        }
        let child = try #require(scratch.pid(in: pidFile))
        defer { scratch.killIfAlive(child) }
        let stopped = Date()
        childStop.stop()

        #expect(outcome.wait(seconds: 5))
        #expect(Date().timeIntervalSince(stopped) < 5)
        #expect(outcome.error as? ShellError == .stopped)
        #expect(scratch.isGone(child))
    }

    /// What the child started in its own group goes with it: the stop signals the group the child leads, not only the child.
    @Test
    func aGrandchildInTheChildsGroupIsGoneToo() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let pidFile = scratch.file("child.pid")
        let grandchildFile = scratch.file("grandchild.pid")
        let childStop = ChildStop()
        let outcome = Outcome()

        DispatchQueue.global().async {
            outcome.record {
                try Shell().stopped(by: childStop).run("/bin/sh", ["-c", "/bin/sleep 30 & echo $! > '\(grandchildFile.path)'; echo $$ > '\(pidFile.path)'; wait"], timeout: 20)
            }
        }
        let child = try #require(scratch.pid(in: pidFile))
        let grandchild = try #require(scratch.pid(in: grandchildFile))
        defer {
            scratch.killIfAlive(grandchild)
            scratch.killIfAlive(child)
        }
        childStop.stop()

        #expect(outcome.wait(seconds: 5))
        #expect(outcome.error as? ShellError == .stopped)
        #expect(scratch.isGone(child))
        #expect(scratch.isGone(grandchild))
    }

    /// Once stopped, a shell spawns nothing: a real one throws before its child exists, and a scripted one before its script is asked.
    @Test
    func aRunAfterTheStopThrowsWithoutSpawning() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let marker = scratch.file("ran")
        let childStop = ChildStop()
        childStop.stop()
        var scriptCalled = false
        let scripted = Shell(script: { _, _, _ in
            scriptCalled = true
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })

        #expect(throws: ShellError.stopped) {
            try Shell().stopped(by: childStop).run("/bin/sh", ["-c", "touch '\(marker.path)'"])
        }
        #expect(throws: ShellError.stopped) {
            try scripted.stopped(by: childStop).run("/usr/bin/true", [])
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!scriptCalled)
    }

    /// A second stop finds nothing to do: it returns at once and the stop stays in force.
    @Test
    func stoppingTwiceIsANoOp() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let pidFile = scratch.file("child.pid")
        let childStop = ChildStop()
        let outcome = Outcome()
        DispatchQueue.global().async {
            outcome.record { try Shell().stopped(by: childStop).run("/bin/sh", ["-c", "echo $$ > '\(pidFile.path)'; exec /bin/sleep 30"], timeout: 20) }
        }
        let child = try #require(scratch.pid(in: pidFile))
        defer { scratch.killIfAlive(child) }
        childStop.stop()
        let again = Date()

        childStop.stop()

        #expect(Date().timeIntervalSince(again) < 0.5)
        #expect(childStop.isStopped)
        #expect(outcome.wait(seconds: 5))
        #expect(outcome.error as? ShellError == .stopped)
    }

    /// A second stop made while the first is still escalating — the child ignores `SIGTERM`, so the first waits two seconds and sends `SIGKILL` — returns only once the child is gone, as the first does: a Ctrl-C after a shard's failure cannot give the devices back and end the process before the `SIGKILL`.
    @Test
    func aSecondStopDuringTheFirstsEscalationReturnsOnlyOnceTheChildIsGone() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let pidFile = scratch.file("child.pid")
        let childStop = ChildStop()
        let outcome = Outcome()
        DispatchQueue.global().async {
            outcome.record { try Shell().stopped(by: childStop).run("/bin/sh", ["-c", "trap '' TERM; echo $$ > '\(pidFile.path)'; exec /bin/sleep 30"], timeout: 20) }
        }
        let child = try #require(scratch.pid(in: pidFile))
        defer { scratch.killIfAlive(child) }
        let first = Outcome()
        DispatchQueue.global().async {
            first.record {
                childStop.stop()
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while !childStop.isStopped, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        childStop.stop()
        let goneAtSecondReturn = kill(child, 0) == -1 && errno == ESRCH

        #expect(goneAtSecondReturn)
        #expect(first.wait(seconds: 10))
        #expect(outcome.wait(seconds: 10))
        #expect(outcome.error as? ShellError == .stopped)
    }

    /// A shell that was never given the stop runs to its normal end beside one that was stopped.
    @Test
    func aPlainShellRunningAlongsideIsUntouched() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let pidFile = scratch.file("child.pid")
        let plainStarted = scratch.file("plain.started")
        let childStop = ChildStop()
        let stoppable = Outcome()
        let plain = Outcome()

        DispatchQueue.global().async {
            stoppable.record { try Shell().stopped(by: childStop).run("/bin/sh", ["-c", "echo $$ > '\(pidFile.path)'; exec /bin/sleep 30"], timeout: 20) }
        }
        DispatchQueue.global().async {
            plain.record { try Shell().run("/bin/sh", ["-c", "echo $$ > '\(plainStarted.path)'; /bin/sleep 1; echo done"], timeout: 20) }
        }
        let child = try #require(scratch.pid(in: pidFile))
        let plainChild = try #require(scratch.pid(in: plainStarted))
        defer {
            scratch.killIfAlive(child)
            scratch.killIfAlive(plainChild)
        }
        childStop.stop()

        #expect(stoppable.wait(seconds: 5))
        #expect(plain.wait(seconds: 10))
        #expect(stoppable.error as? ShellError == .stopped)
        let result = try #require(plain.result)
        #expect(result.succeeded)
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "done")
    }
}

private extension ChildStopTests {
    /// A temporary directory of the test's own, and the pid bookkeeping on files in it.
    struct Scratch {
        let directory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-childstop-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func file(_ name: String) -> URL {
            directory.appendingPathComponent(name)
        }

        /// The pid a child wrote to `file`, waited for up to thirty seconds: the write is a precondition, and a loaded machine can take seconds to spawn the child (SimWalk#183).
        func pid(in file: URL) -> pid_t? {
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                if let text = try? String(contentsOf: file, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return pid
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return nil
        }

        /// Whether `pid` has gone (`ESRCH`) within two seconds — an orphaned grandchild is reaped by launchd a moment after it dies.
        func isGone(_ pid: pid_t) -> Bool {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if kill(pid, 0) == -1, errno == ESRCH {
                    return true
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            return false
        }

        /// Kills a pid this test's own child reported, only if it is still there — so a failing test leaves nothing running.
        func killIfAlive(_ pid: pid_t) {
            if pid > 1, kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// What a `run` on another thread answered, and a way to wait for it.
    final class Outcome: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var answer: Swift.Result<Shell.Result, any Error>?

        func record(_ body: () throws -> Shell.Result) {
            let answered = Swift.Result { try body() }
            lock.lock()
            answer = answered
            lock.unlock()
            done.signal()
        }

        /// Whether the run answered within `seconds`.
        func wait(seconds: TimeInterval) -> Bool {
            done.wait(timeout: .now() + seconds) == .success
        }

        var error: (any Error)? {
            lock.lock()
            defer { lock.unlock() }
            if case let .failure(error) = answer {
                return error
            }
            return nil
        }

        var result: Shell.Result? {
            lock.lock()
            defer { lock.unlock() }
            return try? answer?.get()
        }
    }
}
