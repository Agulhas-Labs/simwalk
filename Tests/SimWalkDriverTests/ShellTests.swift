//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// SimWalk orchestrates `simctl` and `xcodebuild` rather than reimplementing them, so the tool's honesty now depends on reading a child process correctly — including the ways that go wrong only under load.
struct ShellTests {
    @Test
    func aCommandReportsItsOutputAndStatus() throws {
        let result = try Shell().run("/bin/sh", ["-c", "echo out; echo err >&2; exit 0"])

        #expect(result.succeeded)
        #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "out")
        #expect(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines) == "err")
    }

    /// Every child leads a process group of its own — `Process` on Darwin starts it so, and `terminate()` signals the group — which is how a timeout's `SIGTERM` reaches what the child started without `exec`, and why a terminal's Ctrl-C does not reach a child through this process's group.
    @Test
    func aChildLeadsAProcessGroupOfItsOwn() throws {
        let result = try Shell().run("/bin/sh", ["-c", "echo $$; ps -o pgid= -p $$"])
        let lines = result.standardOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        #expect(lines.count == 2)
        #expect(lines.first == lines.last)
        #expect(lines.first != String(getpgrp()))
    }

    @Test
    func aFailedCommandReturnsRatherThanThrowing() throws {
        let result = try Shell().run("/bin/sh", ["-c", "echo nope >&2; exit 3"])

        #expect(!result.succeeded)
        #expect(result.status == 3)
        #expect(result.failureLine == "nope")
    }

    /// The failure that only shows up on a real build: a child filling the pipe buffer blocks in `write` until someone reads, and a parent sitting in `waitUntilExit` never will.
    ///
    /// 64KB is the usual buffer, and `xcodebuild` emits megabytes — so draining after waiting would hang every real walk while passing every small test. This writes well past the buffer on both streams at once.
    @Test
    func aCommandProducingMoreThanAPipeBufferDoesNotDeadlock() throws {
        let result = try Shell().run("/bin/sh", ["-c", "yes abcdefghijklmnopqrstuvwxyz | head -c 2000000; yes ERR | head -c 2000000 >&2"])

        #expect(result.succeeded)
        #expect(result.standardOutput.count == 2_000_000)
        #expect(result.standardError.count == 2_000_000)
    }

    @Test
    func anExecutableThatIsNotThereRefusesNamingIt() {
        #expect(throws: ShellError.self) {
            try Shell().run("/nonexistent/simwalk-not-a-binary", [])
        }
    }

    /// A child that outlives its bound is stopped and named, rather than waited on for as long as it chooses to run (SimWalk#26: a boot that wedged mid-walk).
    @Test
    func acommandThatOutlivesItsBoundIsStoppedAndNamed() {
        let started = Date()

        #expect(throws: ShellError.timedOut(command: "sleep 30", seconds: 0.5)) {
            try Shell().run("/bin/sleep", ["30"], timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    /// A bound a command finishes inside changes nothing about its answer.
    @Test
    func acommandThatFinishesInsideItsBoundAnswersAsUsual() throws {
        let result = try Shell().run("/bin/sh", ["-c", "echo inside; exit 4"], timeout: 30)

        #expect(result.status == 4)
        #expect(result.standardOutput.contains("inside"))
    }

    /// A child that ignores `SIGTERM` is killed — `SIGKILL` — once the moment it was given has passed, rather than left running past its bound (SimWalk#26).
    ///
    /// The child records its own pid, so the test sees it gone rather than inferring it from the call returning.
    @Test
    func acommandThatIgnoresTheRequestToStopIsKilled() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-shell-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        #expect(throws: ShellError.self) {
            try Shell().run("/bin/sh", ["-c", "trap '' TERM; echo $$ > '\(pidFile.path)'; exec sleep 30"], timeout: 0.5)
        }
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        let alive = kill(pid, 0) == 0
        if alive {
            kill(pid, SIGKILL)
        }
        #expect(!alive)
    }

    /// A child that ignores `SIGTERM` and moves itself out of the group it led (`setpgid`) is missed by both group signals, and is still killed by its own pid once the moment is up (SimWalk#64, 3ac7153; #73 item 7).
    ///
    /// It joins the group of a helper this test starts — never the test runner's — and writes its pid only once the move has succeeded, so a child that stayed in its group, where the group's `SIGKILL` would reach it, cannot pass this vacuously.
    @Test
    func achildThatLeftItsGroupIsStillKilledByItsPid() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-shell-\(UUID().uuidString).pid")
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        helper.arguments = ["30"]
        try helper.run()
        var child: pid_t?
        defer {
            if let child, child > 1, kill(child, 0) == 0 {
                kill(child, SIGKILL)
            }
            kill(helper.processIdentifier, SIGKILL)
            try? FileManager.default.removeItem(at: pidFile)
        }
        let script = #"$SIG{TERM} = "IGNORE"; setpgrp(0, $ARGV[0]) or die "setpgid: $!"; open(my $f, ">", $ARGV[1]) or die; print $f "$$\n"; close $f; sleep 30"#

        #expect(throws: ShellError.self) {
            try Shell().run("/usr/bin/perl", ["-e", script, String(helper.processIdentifier), pidFile.path], timeout: 1)
        }
        let written = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        child = written
        #expect(kill(written, 0) != 0)
    }

    /// A child that was not found leading a group of its own is stopped by its pid alone — `SIGTERM`, then `SIGKILL` once the moment is up (SimWalk#64's `group == nil` path; #73 item 7).
    ///
    /// Driven through `stop` directly, since every child `run` launches leads its own group. The child writes its pid only after its trap is set, and `stop` waits for that, so the `SIGTERM` cannot land before the trap and end the child without the `SIGKILL`.
    @Test
    func achildLeadingNoGroupOfItsOwnIsKilledByItsPid() throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-shell-\(UUID().uuidString).pid")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; echo $$ > '\(pidFile.path)'; exec sleep 30"]
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            try? FileManager.default.removeItem(at: pidFile)
        }
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        try #require(FileManager.default.fileExists(atPath: pidFile.path))

        Shell.stop(process, group: nil, exited: exited)

        #expect(!process.isRunning)
    }

    /// A grandchild holding the child's pipe open outlives the child, and the call still ends at the drain limit — and closes its end of the pipe, rather than leaving a reader blocked on it (the round-2 review of SimWalk#26).
    ///
    /// The grandchild shows which: well after the call has returned it writes to the pipe, and a write to a pipe nobody can read fails (`EPIPE`, with `SIGPIPE` ignored), which it records. Before the fix a thread stayed in `read` on that pipe, stranded with its descriptor until the grandchild exited — the write went through, to nobody — and in the long-lived MCP server one thread and one descriptor piled up per wedged command.
    ///
    /// **The grandchild leaves the child's process group** (`set -m` gives a background job a group of its own): stopping the child signals its whole group (SimWalk#64), so a grandchild left in it would be killed and hold nothing open for the drain limit to be about. One that leaves is the case that still reaches the drains — and the edge of what a timeout stops.
    @Test
    func agrandchildHoldingThePipeCostsTheDrainLimitAndLeavesNoReaderBehind() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-shell-\(UUID().uuidString).closed")
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-shell-\(UUID().uuidString).pid")
        var finished = false
        var grandchild: pid_t?
        defer {
            if !finished, let grandchild, grandchild > 1 {
                // Only the group this test's grandchild leads, by the pid it wrote, and only if it never finished.
                killpg(grandchild, SIGKILL)
            }
            try? FileManager.default.removeItem(at: marker)
            try? FileManager.default.removeItem(at: pidFile)
        }
        let started = Date()

        // A 4 s bound, not 0.5 s: under a machine load of 270 the child was stopped before it had forked, so no pid was written and the case never arose. The grandchild's 16 s keeps its write well after the call's bound plus the drain limit.
        #expect(throws: ShellError.self) {
            try Shell().run("/bin/sh", ["-c", "set -m; ( trap '' PIPE TERM; sleep 16; echo late || echo closed > '\(marker.path)' ) & echo $! > '\(pidFile.path)'; exec sleep 30"], timeout: 4)
        }
        let returned = Date().timeIntervalSince(started)
        grandchild = try pid_t(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let deadline = Date().addingTimeInterval(28)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        finished = FileManager.default.fileExists(atPath: marker.path)
        // The grandchild lives 16 seconds; unbounded, the call waited all of them.
        #expect(returned < 11)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    /// A bound applies to the drains after a timely exit too: a grandchild holding the pipe cannot park a call whose child was punctual (SimWalk#27).
    ///
    /// The round-3 drain-limit fix covered the child that outlived its bound; this is the same pipe held by the same kind of grandchild, with a child that exits at once — where the call went on waiting with no limit at all, for as long as the grandchild lived. The grandchild shows the reader is gone the way the test above does, by writing to the pipe well after the call returned and recording the `EPIPE`. The child's own output, read before the limit ran out, is still in the answer.
    @Test
    func aboundedCallIsNotParkedByAGrandchildHoldingThePipeAfterAPunctualExit() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-shell-\(UUID().uuidString).closed")
        defer { try? FileManager.default.removeItem(at: marker) }
        let started = Date()

        let result = try Shell().run("/bin/sh", ["-c", "( trap '' PIPE TERM; sleep 8; echo late || echo closed > '\(marker.path)' ) & echo punctual; exit 0"], timeout: 30)

        let returned = Date().timeIntervalSince(started)
        let deadline = Date().addingTimeInterval(20)
        while !FileManager.default.fileExists(atPath: marker.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        #expect(result.succeeded)
        #expect(result.standardOutput.contains("punctual"))
        // The grandchild lives 8 seconds; unbounded, the call waited all of them.
        #expect(returned < 5)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    /// A bounded call cut off at the drain limit says so, where one whose streams ended on their own does not (SimWalk#30).
    ///
    /// The child exits at once, its status honest and its line already written; the grandchild only holds stdout open, past the limit. What the call read is kept, as before — and now marked, so a caller that judges a call by its text can tell "what was read by then" from "what it said".
    @Test
    func aboundedCallCutOffAtTheDrainLimitIsMarkedTruncated() throws {
        // The backgrounded `sleep 6` is what makes the read cut short, and it outlives this call by design —
        // reap it by the pid `$!` hands back before the test returns, rather than let it run out the clock
        // as a leftover process (SimWalk#32).
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-shell-\(UUID().uuidString).pid")
        defer {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: pidFile)
        }
        let cut = try Shell().run("/bin/sh", ["-c", "( trap '' PIPE TERM; sleep 6 ) & echo $! > '\(pidFile.path)'; echo punctual; exit 0"], timeout: 30)
        let whole = try Shell().run("/bin/sh", ["-c", "echo whole; exit 0"], timeout: 30)

        #expect(cut.succeeded)
        #expect(cut.truncated)
        #expect(whole.succeeded)
        #expect(!whole.truncated)
        #expect(whole.standardOutput.contains("whole"))
    }

    /// A child reads end-of-file, not the parent's stdin — which in the MCP face is the client's JSON-RPC request stream (SimWalk#27).
    ///
    /// **The child has to have something to take, or the test proves nothing.** A child that merely reports end-of-file passes with the fix and without it whenever the runner's own stdin is already at end-of-file (CI, a piped runner), and hangs rather than fails when it is a terminal. So fd 0 is a pipe holding a known token for the length of one call — a `dup` of the real one is put back by `defer`, whatever happens — the child is `cat`, which would print every byte it was given, and both halves are read: the child said nothing, and the token is still there for the parent afterwards. The write end is closed before the call, so neither side can block on it.
    @Test
    func achildIsGivenEndOfFileRatherThanTheParentsStandardInput() throws {
        let token = "simwalk-stdin-\(UUID().uuidString)\n"
        let feed = Pipe()
        try feed.fileHandleForWriting.write(contentsOf: Data(token.utf8))
        try feed.fileHandleForWriting.close()
        let realStandardInput = dup(STDIN_FILENO)
        // Without a real fd 0 to put back, the `defer` below would leave the token pipe installed as this
        // process's stdin for every test that follows it.
        try #require(realStandardInput >= 0)
        defer {
            _ = dup2(realStandardInput, STDIN_FILENO)
            _ = close(realStandardInput)
        }
        _ = dup2(feed.fileHandleForReading.fileDescriptor, STDIN_FILENO)

        let result = try Shell().run("/bin/cat", [])

        var buffer = [UInt8](repeating: 0, count: token.utf8.count)
        let count = read(STDIN_FILENO, &buffer, buffer.count)

        #expect(result.succeeded)
        #expect(result.standardOutput.isEmpty)
        #expect(String(decoding: buffer[..<max(count, 0)], as: UTF8.self) == token)
    }

    @Test
    func addedEnvironmentReachesTheChildWithoutReplacingTheRest() throws {
        let result = try Shell().run("/bin/sh", ["-c", "echo $SIMWALK_TEST_KEY; echo ${PATH:+path-present}"], environment: ["SIMWALK_TEST_KEY": "value"])

        #expect(result.standardOutput.contains("value"))
        #expect(result.standardOutput.contains("path-present"))
    }

    /// Calls made at once each get their own answer, and none of them is left waiting on a pipe another call spawned through (SimWalk#21).
    ///
    /// **This pins the property under load; it does not fail deterministically, before the fix or after it.** The hang it is about was timing-dependent — three un-serialized runs of three of `RunnerProjectTests` hung on one machine on 2026-09-10, a review's eighteen on another did not — so a green run here is evidence, not proof, and the shape of a failure is a run that never ends rather than one that fails: the calls are deliberately unbounded, since a bound would end a parked drain at the limit and hide exactly what is being tested. `concurrentPerform` runs about as many at once as there are cores rather than all of them, so the batch is wide enough to make a leak's window common, not to guarantee it.
    @Test
    func callsMadeAtOnceEachGetTheirOwnOutputAndNoneIsLeftWaiting() {
        let answers = Answers()
        let started = Date()

        DispatchQueue.concurrentPerform(iterations: Self.concurrentCalls) { index in
            let result = try? Shell().run("/bin/sh", ["-c", "echo \(index)"])
            answers.record(index, result?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        #expect(answers.all == Dictionary(uniqueKeysWithValues: (0 ..< Self.concurrentCalls).map { ($0, String($0)) }))
        #expect(Date().timeIntervalSince(started) < 30)
    }

    private static let concurrentCalls = 24
}

private extension ShellTests {
    /// What each of the concurrent calls said, by the number it was told to echo — so a call that picked up another's output is visible, not just one that failed.
    final class Answers: @unchecked Sendable {
        private let lock = NSLock()
        private var said: [Int: String] = [:]

        func record(_ index: Int, _ text: String?) {
            lock.lock()
            defer { lock.unlock() }
            said[index] = text
        }

        var all: [Int: String] {
            lock.lock()
            defer { lock.unlock() }
            return said
        }
    }
}
