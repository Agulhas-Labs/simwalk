//
// Copyright © Agulhas Labs
//

import Foundation

/// iPhone Mirroring was not the frontmost app when the guard looked, or another window lay over a point a gesture touches: the call stops, naming what was in the way and when it was found (Brief §8 "The guard").
///
/// **A type of its own because its answer differs from every other refusal's.** The command line exits 3 for it, beside 1 for any other refusal, because a caller's right response to lost focus is to retry, which is not true of a bad argument; keeping it distinct lets the faces map it without parsing a message.
public struct MirrorFocusRefusal: LocalizedError, Equatable, Sendable {
    /// The frontmost process System Events named, empty when it named none; for ``Moment/pointCovered``, the owner of the window over the point, empty when no window was there.
    public let frontmost: String
    /// When the guard found it.
    public let moment: Moment

    public init(frontmost: String, moment: Moment) {
        self.frontmost = frontmost
        self.moment = moment
    }

    public var errorDescription: String? {
        let found = frontmost.isEmpty ? "System Events named no frontmost process" : "'\(frontmost)' was frontmost"
        return switch moment {
        case .beforeAction:
            "\(MirrorFocus.appName) was not frontmost before the action: \(found), so nothing was posted — retry once it can be"
        case .pointCovered:
            "a point the gesture touches lies under \(frontmost.isEmpty ? "no window" : "a window of '\(frontmost)'"), not \(MirrorFocus.appName)'s, so nothing was posted — retry once it is gone"
        case .windowMoved:
            "the \(MirrorFocus.appName) window moved or resized since it was measured, so a point computed from the old frame could land in its transparent border or on another control — nothing was posted, retry"
        case .duringGesture:
            "focus moved during the gesture: \(found) after it, not \(MirrorFocus.appName), so its events may have gone there"
        case let .beforeFrame(frame):
            "focus moved before frame \(frame): \(found), not \(MirrorFocus.appName), so the burst ended there"
        }
    }
}

extension MirrorFocusRefusal: CustomStringConvertible {
    /// The refusal's own sentence, which is what `TimedCall` prints: `String(describing:)` of a `LocalizedError` struct is its fields, not its message.
    public var description: String {
        errorDescription ?? "iPhone Mirroring was not frontmost"
    }
}

extension MirrorFocusRefusal: UsageFailureClassifiable {
    /// Its own kind, so `simwalk usage` can tell a lost focus (retry) from a failure of the tool.
    public var usageFailureKind: UsageFailureKind {
        .notFrontmost
    }
}

public extension MirrorFocusRefusal {
    /// When in a call the guard found Mirroring was not frontmost: what has and has not been posted follows from it.
    enum Moment: Equatable, Sendable {
        /// Before the action, at the guard or at the single read just before the event: nothing was posted.
        case beforeAction
        /// Before a gesture: the window server listed another window over a point it touches, so its events would have gone there; nothing was posted.
        case pointCovered
        /// Before a gesture: the Mirroring window's bounds in the window server's list differ from the frame the points were computed from (it moved or resized during a long read); nothing was posted.
        case windowMoved
        /// After a gesture's last event: the events were posted, and may have gone to whatever took focus.
        case duringGesture
        /// Before a burst's frame (counted from 1): the frames before it stand, this one and the rest were not taken.
        case beforeFrame(Int)
    }
}
