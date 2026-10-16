//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a live session's runner stopped serving, written by the runner as it returns (`exit.json`).
///
/// **A session that ended on its own says so**: the host reading a dead session finds this record and reports the reason — the idle timeout, say — rather than only that the pid is gone.
public struct LiveSessionExit: Codable, Equatable, Sendable {
    public let reason: Reason
    /// The reason in words: the idle period, or the failure's own text.
    public let detail: String
    /// How many requests the runner served before stopping.
    public let served: Int
    /// When it stopped, by the runner's clock.
    public let stoppedAt: Date
    /// The session whose runner wrote this, echoed from the session id it was launched with; `nil` on a simulator, whose runner writes into the session's own directory, and on a record written before devices had sessions.
    ///
    /// **A physical device's container path is the same for every session**, so an `exit.json` there can be a previous session's: the host takes a copy only when this names its session (Brief, "Live sessions on a physical device", SimWalk#116).
    public let session: String?

    public init(reason: Reason, detail: String, served: Int, stoppedAt: Date, session: String? = nil) {
        self.reason = reason
        self.detail = detail
        self.served = served
        self.stoppedAt = stoppedAt
        self.session = session
    }

    /// This record as `session`'s runner writes it.
    public func stamped(session: String) -> LiveSessionExit {
        LiveSessionExit(reason: reason, detail: detail, served: served, stoppedAt: stoppedAt, session: session)
    }

    /// The record the runner writes when ``LiveSessionIdle`` says the session has gone unused for its whole timeout.
    public static func idle(after timeout: TimeInterval, served: Int, stoppedAt: Date) -> LiveSessionExit {
        LiveSessionExit(reason: .idle, detail: "no request for \(LiveSessionIdle.describe(timeout))", served: served, stoppedAt: stoppedAt)
    }

    /// The line a listing or a refusal states it as.
    public var summary: String {
        switch reason {
        case .ended:
            "ended on request after \(served) request\(served == 1 ? "" : "s")"
        case .idle:
            "exited on its own: \(detail) (\(served) served)"
        case .failed:
            "failed: \(detail)"
        }
    }
}

public extension LiveSessionExit {
    /// Why the runner stopped.
    enum Reason: String, Codable, Equatable, Sendable {
        /// It was sent `end`.
        case ended
        /// No request arrived within the idle timeout.
        case idle
        /// The runner could not launch the app or serve at all.
        case failed
    }
}
