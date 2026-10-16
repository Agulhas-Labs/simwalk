//
// Copyright © Agulhas Labs
//

import Dispatch
import Foundation
import SimWalkCore

/// SIGTERM and SIGINT, heard by a run before they end the process: each cancels the run, then ends the process by the same signal, so the exit status a caller sees is the one it would have seen without this (SimWalk#83).
///
/// **The C handler does nothing, and that is the point.** Nothing a run's cancel does — a lock, a JSON encode, a file write — is async-signal-safe, so none of it may run inside a signal handler. The handler only stops the signal's default action from ending the process; a `DispatchSource` hears the same signal through kqueue and does the work on its own queue, where anything is allowed. Its queue is private rather than main: `walk` is a synchronous command, so the main queue is never drained while it runs.
///
/// **A no-op handler, never `SIG_IGN`.** An ignored signal stays ignored across `exec`, so every `xcodebuild` the walk starts would inherit a SIGINT it can no longer be stopped by; a caught one is reset to its default in the child.
///
/// **A signal the caller already ignores is left alone** — `trap '' INT`, or a background job of a non-interactive shell, which starts with SIGINT ignored. Taking it over would make fatal a signal the caller chose to survive, and take the ignore away from the `xcodebuild` children; and it gets no source either, since kqueue records a signal even while it is ignored.
///
/// **The source is resumed before the handler is installed**, so a signal in between is either fatal as before or heard — never swallowed with nothing listening. The signal is sent again with `kill(2)` to the process, not `raise(3)` to the calling thread: a dispatch worker may block signals, which would leave it pending forever.
///
/// **Going away puts back what it found**: each signal's previous action first, then the sources cancelled, so a signal after the walk ends the process as it would have without this object rather than being swallowed by a handler nothing is listening behind.
final class TerminationSignals {
    private let sources: [DispatchSourceSignal]
    /// The action each taken-over signal had before, put back by `deinit`.
    private let previous: [Int32: sigaction]

    /// Starts hearing `signals` (SIGTERM and SIGINT) for `cancellation`, for as long as this object lives; `end` sends the signal again once the default action is back — to this process, outside a test.
    init(cancelling cancellation: Cancellation, signals: [Int32] = [SIGTERM, SIGINT], end: @escaping @Sendable (Int32) -> Void = { kill(getpid(), $0) }) {
        let queue = DispatchQueue(label: "simwalk.termination-signals")
        var sources: [DispatchSourceSignal] = []
        var previous: [Int32: sigaction] = [:]
        for number in signals where !Self.isIgnored(number) {
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                cancellation.cancel()
                signal(number, SIG_DFL)
                end(number)
            }
            source.resume()
            var handler = sigaction()
            handler.__sigaction_u.__sa_handler = { _ in }
            handler.sa_flags = SA_RESTART
            sigemptyset(&handler.sa_mask)
            var found = sigaction()
            sigaction(number, &handler, &found)
            sources.append(source)
            previous[number] = found
        }
        self.sources = sources
        self.previous = previous
    }

    deinit {
        for (number, found) in previous {
            var found = found
            sigaction(number, &found, nil)
        }
        for source in sources {
            source.cancel()
        }
    }

    /// Whether `number` is at `SIG_IGN` — read with `sigaction(2)`, which changes nothing.
    static func isIgnored(_ number: Int32) -> Bool {
        disposition(of: number) == disposition(SIG_IGN)
    }

    /// The handler `number` has now, as an address: `SIG_DFL` is 0 and `SIG_IGN` is 1.
    static func disposition(of number: Int32) -> Int {
        var found = sigaction()
        sigaction(number, nil, &found)
        return disposition(found.__sigaction_u.__sa_handler)
    }

    /// `handler` as an address, so the two constants and a function can be compared.
    static func disposition(_ handler: (@convention(c) (Int32) -> Void)?) -> Int {
        unsafeBitCast(handler, to: Int.self)
    }
}
