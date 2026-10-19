//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// One walk a bounded server started: `running`, then `ended` with its answer, behind one lock (`Docs/Reference.md`, "Bounded walks").
///
/// The walk's own thread reports the handle and the end; the server's calls read the state and suspend on its changes. The file's phase is never consulted for this walk: the file goes final before the walk returns, and a poll in between must get the answer the walk returns, not the file's.
final class BoundedWalk: @unchecked Sendable {
    private let lock = NSLock()
    private var reported: (handle: WalkHandle, progress: WalkProgress)?
    private var ending: Ended?
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// The handle, once the walk has claimed its progress file and begun it.
    var handle: WalkHandle? {
        lock.withLock { reported?.handle }
    }

    /// The handle and the progress the walk began with — the latter for a `running` line when its file cannot be read.
    var start: (handle: WalkHandle, progress: WalkProgress)? {
        lock.withLock { reported }
    }

    /// The answer, once the walk has returned.
    var ended: Ended? {
        lock.withLock { ending }
    }

    /// Called on the walk's thread with the claimed stem and the progress as begun.
    func started(stem: String, progress: WalkProgress) {
        settle { reported = (WalkHandle(stem: stem, progress: progress), progress) }
    }

    /// Called on the walk's thread once the answering path has returned or thrown.
    func end(_ answer: Ended) {
        settle { ending = answer }
    }

    /// Suspends until the walk has a handle or has ended, or the waiting task is cancelled.
    func untilHandleOrEnd() async {
        await wait { hasHandle, hasEnded in hasHandle || hasEnded }
    }

    /// Suspends until the walk ends, or the waiting task is cancelled.
    func untilEnded() async {
        await wait { _, hasEnded in hasEnded }
    }

    /// Suspends until the walk ends or `seconds` pass on `sleep`, whichever is first; the loser is cancelled, so nothing outlives the call.
    ///
    /// `sleep` must return when its task is cancelled, as `Task.sleep` does.
    func untilEnded(orAfter seconds: TimeInterval, sleep: @escaping @Sendable (TimeInterval) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await sleep(seconds) }
            group.addTask { await self.untilEnded() }
            await group.next()
            group.cancelAll()
        }
    }

    /// Suspends until `done` holds, or the waiting task is cancelled.
    ///
    /// The check and the registration share one lock section, so a change between them is never missed; a cancel removes the registration, or finds the task's cancelled flag already set when it registers.
    private func wait(until done: (_ hasHandle: Bool, _ hasEnded: Bool) -> Bool) async {
        while !Task.isCancelled, !lock.withLock({ done(reported != nil, ending != nil) }) {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let resumeNow = lock.withLock {
                        guard !Task.isCancelled, !done(reported != nil, ending != nil) else { return true }
                        waiters[id] = continuation
                        return false
                    }
                    if resumeNow {
                        continuation.resume()
                    }
                }
            } onCancel: {
                lock.withLock { waiters.removeValue(forKey: id) }?.resume()
            }
        }
    }

    private func settle(_ change: () -> Void) {
        let woken = lock.withLock {
            change()
            defer { waiters = [:] }
            return Array(waiters.values)
        }
        woken.forEach { $0.resume() }
    }
}

extension BoundedWalk {
    /// The answer a walk ended with, returned verbatim on every poll.
    struct Ended: Sendable {
        let text: String
        let isError: Bool
    }
}
