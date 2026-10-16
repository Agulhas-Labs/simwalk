//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Runs a command and returns what it said, so the orchestration layer has one place that spawns a process.
///
/// SimWalk orchestrates `simctl` and `xcodebuild` rather than reimplementing them (Brief §7.5) — which means the tool's honesty now depends on reading a child process correctly. Two things are load-bearing and easy to get wrong: **stdout and stderr are drained concurrently**, because a child that fills a 64KB pipe buffer while the parent waits for exit deadlocks — and `xcodebuild` is exactly the kind of child that produces megabytes; and a **non-zero exit is returned, not thrown**, so a caller decides whether it is a refusal or just information.
public struct Shell {
    /// Stands in for spawning when set — how a test runs the orchestration end to end without a simulator.
    ///
    /// Told each call's bound, which a script may ignore.
    private let script: ((String, [String], [String: String], TimeInterval?) throws -> Result)?

    public init() {
        script = nil
    }

    /// A shell whose children are answered by `script` rather than spawned.
    ///
    /// The seam that lets `walk`'s own orchestration be checked — that it reads the device before the runner and hands it back after — without a booted device, an installed app or a two-minute walk.
    package init(script: @escaping (_ executable: String, _ arguments: [String], _ environment: [String: String]) throws -> Result) {
        self.script = { executable, arguments, environment, _ in try script(executable, arguments, environment) }
    }

    /// A shell whose children are answered by `script`, which is told each call's bound as well.
    ///
    /// How a test checks that a call made to a device that may be wedged is bounded at all (SimWalk#26).
    package init(timedScript script: @escaping (_ executable: String, _ arguments: [String], _ environment: [String: String], _ timeout: TimeInterval?) throws -> Result) {
        self.script = script
    }

    /// Runs `executable` with `arguments`, optionally adding to its environment, and waits for it — for at most `timeout` seconds when one is given.
    ///
    /// **A bound is for a child that can wedge in the middle of a walk**, where waiting forever turns a failure the walk could have reported into a session that never answers (SimWalk#26: `simctl bootstatus` on a device whose boot hung). Past it the child's process group is sent `SIGTERM`, then `SIGKILL` if any of it is still there a moment later — whatever the child started goes with it, unless it left the group — and the call throws `ShellError.timedOut` naming the command. A scripted shell answers from its script, which decides for itself what a timeout looks like.
    ///
    /// `input`, when given, is the child's stdin — read from a file this call writes and removes, so a child that exits without reading it cannot raise `SIGPIPE` here, and one that writes before it reads cannot deadlock against a writer. `workingDirectory` is the child's own. A scripted shell sees neither.
    public func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil,
        input: Data? = nil,
        workingDirectory: URL? = nil
    ) throws -> Result {
        if let script {
            return try script(executable, arguments, environment, timeout)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let out = Pipe()
        let error = Pipe()
        process.standardOutput = out
        process.standardError = error
        // **A child is given end-of-file, never the parent's stdin** (SimWalk#27). In the MCP face the
        // parent's stdin is the client's JSON-RPC request stream: a child that reads a byte of an inherited
        // descriptor — an interactive prompt, a tool probing for piped input — takes it out of a request, and
        // the request is corrupted or lost with nothing reporting it. Even unread, the inherited descriptor
        // keeps the client's pipe referenced for as long as any grandchild lives. Nothing SimWalk spawns has
        // anything to say on stdin.
        process.standardInput = FileHandle.nullDevice
        let inputFile = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-stdin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: inputFile) }
        if let input {
            do {
                try input.write(to: inputFile)
                process.standardInput = try FileHandle(forReadingFrom: inputFile)
            } catch {
                throw ShellError.couldNotRun(executable: executable, reason: "its input could not be staged: \(error.localizedDescription)")
            }
        }
        // **Insurance, and measured inert on this platform — not what fixed SimWalk#21.** A write end held
        // open anywhere keeps the reader here from ever seeing end-of-file, and a sibling spawn inheriting
        // one was the standing suspect: un-serialized, twelve tests once parked in these drains with no
        // child of theirs alive, and `lsof` found a pipe with both ends open in the test process itself.
        // A child of these calls cannot keep one past its exec. Foundation spawns with
        // `POSIX_SPAWN_CLOEXEC_DEFAULT`, so the program a child execs gets the spawn's own file actions and
        // nothing else — probed on Darwin 27, an unrelated descriptor whose close-on-exec is explicitly
        // *clear* is still absent after the exec. Before its exec a child being spawned does hold a copy
        // of every descriptor, close-on-exec or not (SimWalk#71), so neither the flag nor this loop keeps a
        // write end out of a sibling spawn; that copy is gone at the exec, so it can delay an end-of-file
        // but never withhold one. So this loop costs four syscalls and changes nothing any child here sees. It is kept because holding the
        // property is right and a Foundation without that flag would need it, not because it closed a hole.
        // What ended the hang was almost certainly the `DispatchSource` drain that replaced the blocking
        // `readDataToEndOfFile` on 2026-09-14; the 2026-09-19 record in the Brief has the measurements.
        for descriptor in [out.fileHandleForReading, out.fileHandleForWriting, error.fileHandleForReading, error.fileHandleForWriting].map(\.fileDescriptor) {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }
        // Set before the launch, so an exit that comes first is not missed.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw ShellError.couldNotRun(executable: executable, reason: error.localizedDescription)
        }
        // Read now, while the pid is still this child's: `stop` signals this group and no other (SimWalk#64).
        let group = Self.ownGroup(of: process.processIdentifier)
        // The parent's own copies of the write ends go as soon as the child has its own: the child is the
        // only writer these pipes should have, and a write end left open here is one the drains would wait
        // on forever (SimWalk#21). **Already shut, on this platform** — Foundation closes them inside
        // `process.run()` and invalidates the `FileHandle` with them, so this is a measured no-op that
        // returns rather than throwing. The property is that the end is closed by the time a drain reads,
        // not who closed it, so it stays for the Foundation that leaves the job to its caller.
        try? out.fileHandleForWriting.close()
        try? error.fileHandleForWriting.close()

        // Drained as they arrive, *before* waiting. A child writing more than a pipe's buffer blocks in
        // `write` until someone reads, and a parent sitting in `waitUntilExit` never will — the classic
        // deadlock, and `xcodebuild` emits far more than the buffer holds.
        let collector = OutputCollector()
        let drains = [Drain(out, into: collector, isStandardError: false), Drain(error, into: collector, isStandardError: true)]
        if let timeout, exited.wait(timeout: .now() + timeout) == .timedOut {
            Self.stop(process, group: group, exited: exited)
            // A grandchild still holding a pipe would keep a drain open for as long as it lives; the answer
            // here is already known, so the drains get a moment and are then stopped — each closes its end of
            // the pipe, and nothing is left waiting on it.
            Self.settle(drains)
            throw ShellError.timedOut(command: ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " "), seconds: timeout)
        }
        process.waitUntilExit()
        var truncated = false
        if timeout == nil {
            // **A call with no bound waits for the output for as long as it takes, deliberately.** An
            // `xcodebuild` emits megabytes, and cutting its streams off after a couple of seconds would
            // silently lose the compiler diagnostic the walk is there to report. Truncation is a cost only a
            // caller that asked to be bounded has agreed to pay.
            for drain in drains {
                drain.wait()
            }
        } else {
            // **A bound covers the drains after a timely exit too** (SimWalk#27). The child exited inside its
            // bound and has an honest status — so this returns rather than throwing — but a grandchild can
            // still hold its stdout or stderr, and an unbounded wait here would park the call, and with it
            // the MCP server, for as long as that grandchild lives. What was read by then is kept — and marked
            // (SimWalk#30): the status is honest, the text may not be whole, and a caller judging the call by what
            // it printed has to be able to tell.
            truncated = Self.settle(drains)
        }

        return Result(
            status: process.terminationStatus,
            standardOutput: collector.standardOutput(),
            standardError: collector.standardError(),
            truncated: truncated
        )
    }

    /// Asks a child that outlived its bound to stop, then makes it — `SIGTERM`, a moment for it to go, then `SIGKILL`.
    ///
    /// **Both signals reach the process group the child leads** (SimWalk#64), so what the child started goes with it. `terminate()` already sends `SIGTERM` to the group; the `SIGKILL` used to go to the child alone, and only when the child itself had not gone — so a grandchild that ignores `SIGTERM`, under a child that does not, outlived the bound. The escalation is therefore decided by the *group*: it is probed until it has no members, and killed if it still has any when the moment is up. **A group is only signalled while it has members, and while it has members its id cannot be reused** — the one window left is between the probe that finds a member and the kill, the width of one system call. `group` is nil when the child was not found leading a group of its own, and then only the child is signalled, as before: a descendant that leaves the group (`setsid`, a shell's job control) is not reached either way.
    static func stop(_ process: Process, group: pid_t?, exited: DispatchSemaphore) {
        process.terminate()
        guard let group else {
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
            return
        }
        let deadline = Date().addingTimeInterval(2)
        while Self.hasMembers(group), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if Self.hasMembers(group) {
            killpg(group, SIGKILL)
        }
        if exited.wait(timeout: .now() + 2) == .timedOut {
            // A child that moved itself out of the group (`setpgid`) is missed by both group signals; it has not exited, so its pid is still its own.
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 2)
        }
    }

    /// The process group `pid` leads, when it leads one of its own — the only group `stop` will signal.
    ///
    /// Read as soon as the child is launched, while its pid cannot yet have been reused. Refused for a pid of 0 or 1 — `killpg(0, …)` would signal SimWalk's own group — and for SimWalk's own group, so a child that was left in its parent's group is never a reason to signal that group.
    private static func ownGroup(of pid: pid_t) -> pid_t? {
        guard pid > 1, getpgid(pid) == pid, pid != getpgrp() else {
            return nil
        }
        return pid
    }

    /// Whether any process is still in `group` — a zombie still counts until it is reaped (on Darwin `killpg(_, 0)` answers `EPERM` for it, which is why `EPERM` counts), and a `SIGKILL` to it is harmless.
    private static func hasMembers(_ group: pid_t) -> Bool {
        killpg(group, 0) == 0 || errno == EPERM
    }

    /// Gives the drains the limit to finish on their own, stops the ones that do not, and waits once more for a stopped drain to hand over what it had read.
    ///
    /// The second wait is what keeps a cancelled drain's output: `cancel()` only asks, and the text reaches the collector on the drain's own queue a moment later — the caller reads the collector as soon as this returns. **Both deadlines are shared across the drains rather than taken per drain**, so the whole settle is bounded at twice the limit however many there are; a deadline per drain would make a two-stream call cost three times it, and the caller's bound is already spent by the time this runs.
    ///
    /// **Best-effort at the edge.** A grandchild writing without pause can keep a drain's event handler looping past the second deadline, and its text then reaches the collector after the `Result` was built. The collector is lock-guarded, so that output is dropped rather than interleaved — a truncation, not a corruption.
    ///
    /// Answers whether any drain had to be stopped — whether a writer still held a pipe when the limit ran out, so that what the collector holds is what was read by then, not what the streams would have said (SimWalk#30).
    @discardableResult
    private static func settle(_ drains: [Drain]) -> Bool {
        let ownEnd = DispatchTime.now() + Self.drainLimit
        var stopped = false
        for drain in drains where !drain.wait(until: ownEnd) {
            drain.cancel()
            stopped = true
        }
        let handover = DispatchTime.now() + Self.drainLimit
        for drain in drains {
            drain.wait(until: handover)
        }
        return stopped
    }

    /// How long a bounded call's output drains may run before they are stopped too — whether the child was stopped at its bound or exited inside it.
    static var drainLimit: TimeInterval {
        2
    }
}

extension Shell {
    /// One of a child's two streams, read as it arrives from a dispatch source rather than by a thread blocked in `read` — so a caller that stops waiting can stop it (the round-2 review of SimWalk#26).
    ///
    /// **The blocking read it replaces could not be stopped.** It stayed in `read` for as long as anything held the pipe's other end, and a grandchild of a bounded child can: the child was killed, the caller gave up after `drainLimit`, and the thread and the descriptor stayed stranded until the grandchild exited — in the long-lived MCP server, one of each for every wedged command. Here nothing is blocked: `cancel()` stops the source, and its cancel handler hands over what was read, closes the descriptor and says the stream is done.
    final class Drain: @unchecked Sendable {
        private let source: any DispatchSourceRead
        private let finished = DispatchGroup()
        /// What has been read so far — touched only on the source's own serial queue.
        private var received = Data()

        init(_ pipe: Pipe, into collector: OutputCollector, isStandardError: Bool) {
            let handle = pipe.fileHandleForReading
            let descriptor = handle.fileDescriptor
            // Non-blocking, so each event reads what the pipe holds and returns rather than waiting for more.
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "simwalk.shell.drain"))
            finished.enter()
            source.setEventHandler { [self] in
                if !readAvailable(from: descriptor) {
                    source.cancel()
                }
            }
            source.setCancelHandler { [self] in
                collector.append(Self.text(received), isStandardError: isStandardError)
                try? handle.close()
                finished.leave()
            }
            source.resume()
        }

        /// Waits until the stream has ended or been stopped — or until `deadline` — answering whether it had.
        @discardableResult
        func wait(until deadline: DispatchTime = .distantFuture) -> Bool {
            finished.wait(timeout: deadline) == .success
        }

        /// Stops reading, whatever still holds the pipe's other end: the descriptor is closed and `wait` returns.
        func cancel() {
            source.cancel()
        }

        /// Reads everything the pipe holds now, answering whether more may come — `false` once every writer has closed its end, or the read failed.
        private func readAvailable(from descriptor: Int32) -> Bool {
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = read(descriptor, &chunk, chunk.count)
                if count > 0 {
                    received.append(contentsOf: chunk[..<count])
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return count < 0 && errno == EAGAIN
                }
            }
        }

        /// UTF-8 first, Latin-1 as the fallback — which cannot fail, because every byte is a valid Latin-1 scalar.
        ///
        /// This is a child's console output, not data: `xcodebuild` can emit a stray non-UTF8 byte inside a compiler diagnostic, and giving up there would discard the whole stream, losing the very error message being reported. Latin-1 keeps every byte recoverable and mangles only the few that were not UTF-8 to begin with.
        private static func text(_ data: Data) -> String {
            String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
        }
    }
}

public extension Shell {
    /// What a finished command left behind.
    struct Result: Equatable, Sendable {
        public let status: Int32
        public let standardOutput: String
        public let standardError: String
        /// Whether the output was cut off at the drain limit: the child exited inside its bound, but something it left behind still held a pipe when the limit ran out, so the streams hold what was read by then (SimWalk#30).
        ///
        /// **The status is still the child's, and honest; the text may not be whole** — possibly all of it, possibly not, and nothing here can say which. So a caller that judges a call by what it printed treats a truncated result as no answer rather than a wrong one. Only ever set on a bounded call: an unbounded one waits for its output for as long as it takes.
        public let truncated: Bool

        public init(status: Int32, standardOutput: String, standardError: String, truncated: Bool = false) {
            self.status = status
            self.standardOutput = standardOutput
            self.standardError = standardError
            self.truncated = truncated
        }

        /// Whether the command reported success — its exit status, whether or not its output was `truncated`.
        public var succeeded: Bool {
            status == 0
        }

        /// The best single line to show a human when this failed — stderr if it said anything, else stdout's tail.
        public var failureLine: String {
            let stderrLine = standardError.trimmed
            guard stderrLine.isEmpty else { return Self.lastLine(of: stderrLine) }
            return Self.lastLine(of: standardOutput.trimmed)
        }

        private static func lastLine(of text: String) -> String {
            text.split(separator: "\n").last.map(String.init) ?? "exited \(0)"
        }
    }
}
