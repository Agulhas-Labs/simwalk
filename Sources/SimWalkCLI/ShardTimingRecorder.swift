//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The marks of a `--parallel` walk's shards, taken on the walk's own clock (``WalkTelemetry/elapsedMilliseconds()``) from the shard workers at once, and read as one ``ParallelTimings``.
///
/// Unchecked because every write goes through `lock`; the telemetry it reads the clock through is only read after `begin`.
final class ShardTimingRecorder: @unchecked Sendable {
    private let telemetry: WalkTelemetry
    private let lock = NSLock()
    private var shards: [ShardTiming]
    private var mergeStarted: Int?
    private var mergeMs: Int?
    private var endMs: Int?
    private var lineWritten = false
    private let interruption: InterruptionMark?

    /// `nil` when the walk is not watched: with no telemetry there is no clock to measure from, and nothing is recorded.
    ///
    /// `interruption` is where the clock stood as the walk's interruption was heard: once it has a reading, every writer ends the line there (SimWalk#189).
    init?(telemetry: WalkTelemetry?, shards: [ShardTiming], interruption: InterruptionMark? = nil) {
        guard let telemetry else { return nil }
        self.telemetry = telemetry
        self.shards = shards
        self.interruption = interruption
    }

    /// The walk's offset now, or `nil` before it began.
    func elapsed() -> Int? {
        telemetry.elapsedMilliseconds()
    }

    /// Shard `index`'s device is booted, holds the app and passed the build check.
    func ready(_ index: Int) {
        let now = elapsed()
        lock.withLock { shards[index].readyMs = now }
    }

    /// Shard `index`'s runner walk, or its appearance retry's second pass, began or ended.
    func runner(_ index: Int, _ mark: RunnerMark) {
        let now = elapsed()
        lock.withLock {
            switch mark {
            case .started: shards[index].runnerStartMs = now
            case .ended: shards[index].runnerEndMs = now
            case .retryStarted: shards[index].retryStartMs = now
            case .retryEnded: shards[index].retryEndMs = now
            }
        }
    }

    func mergeBegan() {
        let now = elapsed()
        lock.withLock { mergeStarted = now }
    }

    /// The merge ended, with the bundle merged or not.
    func mergeEnded() {
        let now = elapsed()
        lock.withLock {
            mergeMs = mergeStarted.flatMap { start in now.map { $0 - start } }
            endMs = endMs ?? now
        }
    }

    /// The offset the walk's usage line ends at; `nil` before the walk began.
    ///
    /// The first call fixes it, so the merge's end, a failure or a cancel, whichever came first, is the line's `ms` and nothing later (the release of the devices) moves it. The interruption's reading, once taken, is the end when it came first, whichever writer asks: the walk's own end can run after the devices are given back too (SimWalk#189).
    @discardableResult
    func end() -> Int? {
        let now = elapsed()
        let cancel = interruption?.milliseconds
        return lock.withLock {
            endMs = [endMs ?? now, cancel].compactMap(\.self).min()
            return endMs
        }
    }

    /// Writes the walk's `walk.parallel` line, once however many callers ask.
    ///
    /// The cancel's handler and the walk's own end both do, and the first to ask writes it. Nothing is written before the walk began.
    ///
    /// The first holds the lock until the line is on disk, so the other waits for it rather than returning: an interruption kills the process as soon as its handler returns, and a handler that returned while the walk's own end was still writing would lose the line.
    ///
    /// The line holds the marks through its `ms` only (``ParallelTimings/through(_:)``): a runner the interruption stopped after the cancel has no end in it, and a merge that ended after the cancel has no `mergeMs`, judged by where it ended, since `mergeMs` is a duration.
    func writeLine(to log: UsageLog, target: String?, succeeded: Bool, error: String? = nil, kind: UsageFailureKind? = nil) {
        guard let milliseconds = end() else { return }
        lock.withLock {
            guard !lineWritten else { return }
            lineWritten = true
            let merge = mergeStarted.flatMap { start in mergeMs.flatMap { start + $0 <= milliseconds ? $0 : nil } }
            log.record(tool: UsageLog.parallelTool, target: target, milliseconds: milliseconds, succeeded: succeeded, err: error, kind: kind, parallel: ParallelTimings(shards: shards, mergeMs: merge).through(milliseconds))
        }
    }

    /// Everything marked so far.
    func timings() -> ParallelTimings {
        lock.withLock { ParallelTimings(shards: shards, mergeMs: mergeMs) }
    }
}

extension ShardTimingRecorder {
    /// What a shard's runner did at a mark.
    enum RunnerMark {
        case started
        case ended
        /// The appearance retry's second pass: its marks are the first pass's own, apart (SimWalk#189).
        case retryStarted
        case retryEnded
    }
}
