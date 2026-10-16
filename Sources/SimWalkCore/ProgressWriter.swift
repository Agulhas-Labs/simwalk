//
// Copyright © Agulhas Labs
//

import Foundation

/// The one writer of a run's progress file (`Docs/SIMWALK-PROGRESS.md` §3): holds the run's ``WalkProgress`` in memory and writes it atomically, throttled.
///
/// **Two ways to change the state, and the difference is the throttle.** ``update(_:)`` keeps every change in memory but writes at most once per `minInterval` (500 ms), so a reader is not made to re-parse a file faster than it polls; a change it does not write rides in the next write. ``commit(_:)`` always writes — a screen finishing, a phase change, completion — and an `update` that changes the phase is written as if committed, since every phase change is written by definition.
///
/// **One writer at a time, handed over, never shared.** The host writes `booting … launching`; the runner, a process of its own, takes over with ``adopting(url:clock:minInterval:)`` and writes `running` and each screen; the host then ``reload()``s what the runner wrote before writing `matching` and the end. Nothing here locks the file across processes: the hand-over is the protocol. The one write that crosses it is a cancel — the host's, while the runner holds the file. So the host's ``cancel()`` starts from what the runner last wrote rather than its own copy from before the hand-over, and leaves a marker beside the file before writing it; the runner's writer looks for the marker before each write and again once its rename has landed, and keeps the cancel. The file alone could not carry it: a host cancel landing between the runner's look and its rename is renamed over, and the second look is what writes it back.
///
/// **A failure to write is silent.** Progress is a view of a walk, and must never fail one: a full disk or an unwritable directory leaves the file stale, and the walk's answer is unchanged. Thread-safe — every method takes one lock, the write included, so two threads' writes cannot land out of order.
public final class ProgressWriter: @unchecked Sendable {
    /// The progress file.
    public let url: URL
    private let clock: @Sendable () -> Date
    private let minInterval: TimeInterval
    private let lock = NSLock()
    private var progress: WalkProgress
    private var lastWrite: Date?
    /// Whether ``begin(tool:phase:)`` has started a run here — a writer that never began has no run to end, and the file still holds the last run's end.
    private var began = false
    /// Whether the run was cancelled — by ``cancel()``, or in a file this writer read: from then on every write, and every state ``reload()`` reads back, stays `failed` / `cancelled` — a cancelled MCP walk carries on, and its later writes must not make the run look alive again.
    private var cancelled = false
    /// Whether this writer took the file over from another with ``adopting(url:clock:minInterval:)`` — the runner, whose host can cancel the run while the runner holds the file.
    ///
    /// Such a writer looks for the host's cancel marker before each write (``keepHostsCancel()``).
    private var follows = false
    /// The file's bytes as this writer last read or wrote them, a write that failed not counted: a file that still holds them has had no other writer since.
    private var lastSeen: Data?
    /// A test's way into a write between its look for the host's marker and its rename (SimWalk#89), called with the lock held once the state is encoded.
    ///
    /// `nil` outside tests. A `let` set through the initializer, so it cannot change once the writer is shared across threads.
    let beforeRename: (() -> Void)?
    /// The host's cancel marker, beside the file (`<progress>.cancel`): created by ``cancel()`` before it writes, and removed by the next run's ``begin(tool:phase:)``.
    ///
    /// A file the runner never writes, so its rename cannot overwrite it the way it can overwrite a cancel in the progress file. Its lifetime is the slot's run while the host lives: the host's claim keeps a second run out until this one ends (a runner orphaned by a host killed alone can still outlive the claim, `Docs/SIMWALK-PROGRESS.md` §3), and the next run removes the marker before its runner exists, so a marker a killed host left behind never cancels the run after it.
    private var cancelMarker: URL {
        url.appendingPathExtension("cancel")
    }

    /// A writer for `url` that has written nothing yet; ``begin(tool:phase:)`` starts the run.
    public convenience init(url: URL, clock: @escaping @Sendable () -> Date, pid: Int32, minInterval: TimeInterval = 0.5) {
        self.init(url: url, clock: clock, pid: pid, minInterval: minInterval, beforeRename: nil)
    }

    /// The same writer with a test's ``beforeRename`` hook.
    init(url: URL, clock: @escaping @Sendable () -> Date, pid: Int32, minInterval: TimeInterval, beforeRename: (() -> Void)?) {
        self.beforeRename = beforeRename
        self.url = url
        self.clock = clock
        self.minInterval = minInterval
        progress = WalkProgress(tool: "walk", phase: .idle, pid: pid, startedAt: clock())
    }

    /// The runner's writer: the state the host left at `url`, its `pid` included — the host is the process that writes the end, so its liveness is what a reader should check — or, when there is no readable file, a fresh state owned by this process.
    public static func adopting(url: URL, clock: @escaping @Sendable () -> Date = { Date() }, minInterval: TimeInterval = 0.5) -> ProgressWriter {
        adopting(url: url, clock: clock, minInterval: minInterval, beforeRename: nil)
    }

    /// The runner's writer with a test's ``beforeRename`` hook: internal, so no module but the tests can install one on a production writer.
    static func adopting(url: URL, clock: @escaping @Sendable () -> Date, minInterval: TimeInterval = 0.5, beforeRename: (() -> Void)?) -> ProgressWriter {
        let writer = ProgressWriter(url: url, clock: clock, pid: ProcessInfo.processInfo.processIdentifier, minInterval: minInterval, beforeRename: beforeRename)
        writer.follows = true
        writer.reload()
        return writer
    }

    /// The state as this writer holds it, written or not.
    public var current: WalkProgress {
        lock.withLock { progress }
    }

    /// Starts a run: a fresh state in `phase`, naming the usage log (`logPath`) from this first write when the host knows it, replacing whatever the file held — a new run overwrites, nothing accumulates (§3).
    public func begin(tool: String, phase: WalkProgress.Phase = .booting, logPath: String? = nil) {
        lock.withLock {
            began = true
            try? FileManager.default.removeItem(at: cancelMarker)
            progress = WalkProgress(tool: tool, phase: phase, pid: progress.pid, startedAt: clock())
            progress.logPath = logPath
            write(at: clock())
        }
    }

    /// Changes the state, writing it only when `minInterval` has passed since the last write or the phase changed.
    public func update(_ change: (inout WalkProgress) -> Void) {
        lock.withLock {
            let phase = progress.phase
            change(&progress)
            keepCancelled()
            writeIfDue(at: clock(), phaseChanged: progress.phase != phase)
        }
    }

    /// Changes the state and writes it, whatever the throttle says.
    public func commit(_ change: (inout WalkProgress) -> Void) {
        lock.withLock {
            change(&progress)
            write(at: clock())
        }
    }

    /// Ends the run, always written.
    ///
    /// A run with a result ends through ``finish(writing:to:as:error:)``, which writes the result file first, so `resultPath` names a file that exists in the same write that makes the phase terminal (§3).
    public func finish(_ ending: Ending, error: String? = nil, resultPath: String? = nil) {
        commit { progress in
            progress.phase = ending.phase
            progress.error = error
            progress.resultPath = resultPath
        }
    }

    /// Ends the run with its result: `result` written atomically to `url` first, then the terminal state naming it.
    ///
    /// A result that cannot be written still ends the run, with no `resultPath` — a reader is never pointed at a file that is not there.
    public func finish(writing result: WalkResult, to url: URL, as ending: Ending, error: String? = nil) {
        finish(ending, error: error, resultPath: Self.write(result, to: url))
    }

    /// Writes `result` to `url`, returning the path written, or `nil` when it could not be.
    private static func write(_ result: WalkResult, to url: URL) -> String? {
        do {
            try AtomicFileWrite.write(WalkResult.encoder().encode(result), to: url)
            return url.path
        } catch {
            return nil
        }
    }

    /// Ends a run that has not ended as `failed`, with error `cancelled`, for a cancellation the process gets to handle — and keeps it so: every later write is `failed` / `cancelled` whatever it changes, a ``reload()`` included.
    ///
    /// What is written is the run as the file holds it when another writer — the runner — has replaced it since this one last read or wrote it, with only `phase` and `error` changed, so the runner's screen counts survive the cancel even when it never writes again; otherwise, an unreadable file included, it is this writer's own copy. The cancel marker goes down first (``cancelMarker``). A run already ended is left as it ended, and a writer that never began writes nothing: the file is the previous run's.
    public func cancel() {
        lock.withLock {
            guard began, !progress.phase.isTerminal else { return }
            takeAnotherWritersState()
            progress.phase = .failed
            progress.error = Self.cancelledError
            cancelled = true
            try? Data().write(to: cancelMarker)
            write(at: clock())
        }
    }

    /// Ends a run that has not ended as `failed`, with error `interrupted`: what ``ProgressRun`` writes when it goes away before the run was finished.
    ///
    /// Nothing when this writer never began: a run refused before it started leaves the previous run's end in place rather than overwriting it.
    func interrupt() {
        end(error: "interrupted")
    }

    /// Replaces the state in memory with what the file holds: how the host takes the run back from the runner, and how the runner takes it over.
    ///
    /// A file that says the run was cancelled latches this writer as ``cancel()`` would: the runner adopting a run its host cancelled first must not write it `running` again. A missing or unreadable file changes nothing.
    @discardableResult
    public func reload() -> Bool {
        guard let data = try? Data(contentsOf: url), let read = try? WalkProgress.decoder().decode(WalkProgress.self, from: data) else {
            return false
        }
        lock.withLock {
            lastSeen = data
            progress = read
            cancelled = cancelled || Self.isCancelled(read)
            keepCancelled()
        }
        return true
    }

    private func end(error: String) {
        lock.withLock {
            guard began, !progress.phase.isTerminal else { return }
            progress.phase = .failed
            progress.error = error
            write(at: clock())
        }
    }

    /// Writes a throttled change when the phase changed or the interval has passed; called with the lock held.
    private func writeIfDue(at now: Date, phaseChanged: Bool) {
        guard phaseChanged || isDue(at: now) else { return }
        write(at: now)
    }

    /// Whether a throttled change may be written at `now`; a clock that went backwards counts as due rather than holding writes until it catches up.
    private func isDue(at now: Date) -> Bool {
        guard let lastWrite else { return true }
        return !(0 ..< minInterval).contains(now.timeIntervalSince(lastWrite))
    }

    /// A follower's look for its host's cancel marker before it writes: a marker there latches the cancel rather than writing over it; called with the lock held.
    ///
    /// The runner holds a copy of the state from before its host's ``cancel()``, so without this its next screen would write `running` back over the host's end — and a cancel the runner's own rename overwrote would never be seen in the file again. A host never follows: its first write is over the previous run's file, and its ``begin(tool:phase:)`` removes that run's marker.
    private func keepHostsCancel() {
        guard follows, FileManager.default.fileExists(atPath: cancelMarker.path) else { return }
        cancelled = true
    }

    /// Takes the state the file holds when another writer has replaced it since this one last read or wrote it — the runner's, written after the hand-over; called with the lock held.
    ///
    /// A file that still holds this writer's last bytes, or that cannot be read, leaves the state in memory alone: before the hand-over that copy is the newer one, throttled changes included. So does a writer that has never seen the file hold its run — every write it made failed, and nothing was reloaded — since what the file holds then is the previous run's, not another writer's (SimWalk#89).
    private func takeAnotherWritersState() {
        guard let lastSeen, let data = try? Data(contentsOf: url), data != lastSeen,
              let read = try? WalkProgress.decoder().decode(WalkProgress.self, from: data) else { return }
        progress = read
    }

    /// Whether `state` is a run ended by a cancel.
    private static func isCancelled(_ state: WalkProgress) -> Bool {
        state.phase == .failed && state.error == cancelledError
    }

    /// Puts a cancelled run's end back over whatever a change made of it; called with the lock held.
    private func keepCancelled() {
        guard cancelled else { return }
        progress.phase = .failed
        progress.error = Self.cancelledError
    }

    /// The error a cancelled run ends with.
    private static var cancelledError: String {
        "cancelled"
    }

    /// Stamps and writes the state; called with the lock held.
    ///
    /// A follower looks for the host's marker again once its rename has landed, and writes the cancel when one appeared during the write: the host puts the marker down before it writes the file, so a cancel it wrote before this rename has its marker seen here, and one it writes after the rename is not overwritten — a cancel landing in the runner's last write holds without waiting for another write (SimWalk#89).
    private func write(at now: Date) {
        keepHostsCancel()
        keepCancelled()
        progress.touch(at: now)
        lastWrite = now
        guard let data = try? WalkProgress.encoder().encode(progress) else { return }
        beforeRename?()
        guard (try? AtomicFileWrite.write(data, to: url)) != nil else { return }
        lastSeen = data
        guard !cancelled else { return }
        keepHostsCancel()
        if cancelled {
            write(at: now)
        }
    }
}

public extension ProgressWriter {
    /// How a run ends — the two terminal phases, and only those.
    enum Ending: Equatable, Sendable {
        case done
        case failed

        var phase: WalkProgress.Phase {
            switch self {
            case .done: .done
            case .failed: .failed
            }
        }
    }
}
