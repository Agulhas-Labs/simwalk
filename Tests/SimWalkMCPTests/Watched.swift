//
// Copyright © Agulhas Labs
//

import Foundation

/// State a test waits on, behind a condition: every change wakes the waiters, and every wait has a wall-clock limit, so a test whose server never gets there fails in seconds instead of hanging.
///
/// A wait blocks a thread of its own rather than one of the cooperative pool's, and never spins.
final class Watched<State>: @unchecked Sendable {
    private let condition = NSCondition()
    private var state: State

    init(_ state: State) {
        self.state = state
    }

    /// The state now.
    var value: State {
        condition.lock()
        defer { condition.unlock() }
        return state
    }

    /// Changes the state and wakes every waiter.
    @discardableResult
    func update<T>(_ change: (inout State) -> T) -> T {
        condition.lock()
        defer {
            condition.broadcast()
            condition.unlock()
        }
        return change(&state)
    }

    /// Waits on the calling thread until `taking` returns a value, or `seconds` pass; `nil` on the latter.
    ///
    /// `taking` runs under the lock and may change the state.
    func block<T>(within seconds: TimeInterval, _ taking: (inout State) -> T?) -> T? {
        let deadline = Date().addingTimeInterval(seconds)
        condition.lock()
        defer {
            condition.broadcast()
            condition.unlock()
        }
        while true {
            if let taken = taking(&state) {
                return taken
            }
            guard condition.wait(until: deadline) else {
                return taking(&state)
            }
        }
    }

    /// ``block(within:_:)`` off the cooperative pool, throwing ``TimedOut`` naming `what` when the limit passes.
    func wait<T: Sendable>(_ what: String, within seconds: TimeInterval = Watched.limit, _ taking: @escaping @Sendable (inout State) -> T?) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Thread {
                guard let taken = self.block(within: seconds, taking) else {
                    return continuation.resume(throwing: TimedOut(what: what, seconds: seconds))
                }
                continuation.resume(returning: taken)
            }.start()
        }
    }
}

extension Watched {
    /// How long any one wait in these tests may take on the wall clock: far above what a passing step needs, far below a test's patience.
    static var limit: TimeInterval {
        3
    }

    /// A wait whose condition never came.
    struct TimedOut: Error, CustomStringConvertible {
        let what: String
        let seconds: TimeInterval

        var description: String {
            "timed out after \(seconds) s waiting for \(what)"
        }
    }
}
