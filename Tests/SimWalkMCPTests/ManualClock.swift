//
// Copyright © Agulhas Labs
//

import Foundation

/// A clock a test moves by hand: ``sleep(for:)`` suspends until ``advance(by:)`` passes its deadline, its task is cancelled, or ``release()`` ends every sleep.
///
/// Nothing here spins or sleeps on the wall clock: a test waits for a sleeper with ``untilSleeping(_:)``, which is bounded by ``Watched/limit``, and then moves time itself.
final class ManualClock: @unchecked Sendable {
    private let state = Watched(State())

    var now: TimeInterval {
        state.value.seconds
    }

    /// Suspends until the clock has moved `interval` past now, or the task is cancelled.
    ///
    /// A cancel ends the sleep, as it ends `Task.sleep`: one that came before the sleep registered finds the task's cancelled flag set.
    func sleep(for interval: TimeInterval) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeNow = state.update { state in
                    guard !state.released, !Task.isCancelled else { return true }
                    state.sleepers[id] = Sleeper(deadline: state.seconds + interval, continuation: continuation)
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        } onCancel: {
            state.update { $0.sleepers.removeValue(forKey: id) }?.continuation.resume()
        }
    }

    /// Waits until at least `count` sleeps are pending.
    func untilSleeping(_ count: Int = 1) async throws {
        _ = try await state.wait("\(count) sleep(s) on the manual clock") { $0.sleepers.count >= count ? true : nil }
    }

    /// Moves the clock on by `interval`, waking every sleeper whose deadline has passed.
    func advance(by interval: TimeInterval) {
        let woken = state.update { state in
            state.seconds += interval
            let due = state.sleepers.filter { $0.value.deadline <= state.seconds }
            due.keys.forEach { state.sleepers.removeValue(forKey: $0) }
            return due.values.map(\.continuation)
        }
        woken.forEach { $0.resume() }
    }

    /// Waits for a sleeper, then moves the clock on by `interval`.
    func advanceOnceSleeping(by interval: TimeInterval) async throws {
        try await untilSleeping()
        advance(by: interval)
    }

    /// Wakes every sleeper and makes every later sleep return at once: a test's teardown, so its server can end whatever the test did.
    func release() {
        let woken = state.update { state in
            state.released = true
            defer { state.sleepers = [:] }
            return state.sleepers.values.map(\.continuation)
        }
        woken.forEach { $0.resume() }
    }
}

extension ManualClock {
    struct State {
        var seconds: TimeInterval = 0
        var sleepers: [UUID: Sleeper] = [:]
        var released = false
    }

    struct Sleeper {
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Never>
    }
}
