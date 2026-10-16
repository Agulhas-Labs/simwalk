//
// Copyright © Agulhas Labs
//

import Foundation

/// A request to stop a run, raised from outside it — an MCP client's `notifications/cancelled`, a SIGTERM or SIGINT to the CLI — and heard by whatever the run registered with ``onCancel(_:)``.
///
/// **Raised once, heard once, whichever comes first.** A handler registered after the cancel runs at once, on the registering thread: a cancel that lands before the run has anything to end is not lost, it waits for the run to register. ``cancel()`` runs the handlers on its caller's thread, outside the lock, so a handler that takes a lock of its own (the progress writer's) cannot deadlock against a registration.
public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [@Sendable () -> Void] = []

    public init() {}

    /// Whether ``cancel()`` has been called.
    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    /// Runs `handler` when the run is cancelled — at once, when it already has been.
    public func onCancel(_ handler: @escaping @Sendable () -> Void) {
        let runNow = lock.withLock {
            guard !cancelled else { return true }
            handlers.append(handler)
            return false
        }
        if runNow {
            handler()
        }
    }

    /// Cancels the run: every registered handler runs once; a second call does nothing.
    public func cancel() {
        let toRun = lock.withLock {
            guard !cancelled else { return [@Sendable () -> Void]() }
            cancelled = true
            defer { handlers = [] }
            return handlers
        }
        for handler in toRun {
            handler()
        }
    }
}
