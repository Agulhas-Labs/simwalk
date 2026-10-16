//
// Copyright © Agulhas Labs
//

import Foundation

/// The focus guard's decision, over the frontmost process names the driver polls: no event, and no capture, unless iPhone Mirroring is frontmost (Brief §8 "The guard").
///
/// **The rule exists because events and keystrokes once landed in a live Safari page** when focus was not where a hand-built driver assumed. So before each action the driver activates Mirroring and feeds this one name at a time from System Events, every ``pollInterval``, until it clears or ``maxPolls`` run out; activation was measured taking up to about a second, and a fixed 350 ms wait refused. The decision is a value that takes each read and returns the next move (the `SettleTracker` shape), so it is tested against a scripted sequence of names rather than a live Mac.
public struct MirrorFocus: Sendable {
    /// The app's name as System Events reports it frontmost, and as `tell application` activates it.
    public static var appName: String {
        "iPhone Mirroring"
    }

    /// The wait before each poll.
    public static let pollInterval: TimeInterval = 0.2
    /// Polls before the guard gives up: two seconds, twice the slowest activation measured.
    public static let maxPolls = 10

    /// The names taken so far.
    public private(set) var polls = 0

    public init() {}

    /// The next move after one poll named `frontmost`: cleared when it is Mirroring, refused once ``maxPolls`` have passed without it, otherwise poll again.
    ///
    /// A poll past the last refuses too, so a loop that ignores a refusal can never clear late.
    public mutating func take(_ frontmost: String) -> Decision {
        polls += 1
        guard polls <= Self.maxPolls else {
            return .refused(frontmost: frontmost)
        }
        if frontmost == Self.appName {
            return .cleared(Clearance())
        }
        return polls == Self.maxPolls ? .refused(frontmost: frontmost) : .pollAgain
    }

    /// The single-read check, with no polling: just before the event, after a gesture's last event, and before each frame of a burst.
    ///
    /// A new clearance when `frontmost` is Mirroring, so what follows the check runs on the check's own token.
    public static func recheck(_ frontmost: String, at moment: MirrorFocusRefusal.Moment) throws(MirrorFocusRefusal) -> Clearance {
        guard frontmost == appName else {
            throw MirrorFocusRefusal(frontmost: frontmost, moment: moment)
        }
        return Clearance()
    }
}

public extension MirrorFocus {
    /// What one poll decided.
    enum Decision: Sendable {
        /// Mirroring is frontmost: the action may go ahead on this token.
        case cleared(Clearance)
        /// Not yet, and polls remain: wait ``MirrorFocus/pollInterval`` and read again.
        case pollAgain
        /// The polls ran out on `frontmost`: refuse the call before anything is posted.
        case refused(frontmost: String)
    }

    /// Proof that the guard's decision passed, minted only by ``MirrorFocus/take(_:)`` clearing or ``MirrorFocus/recheck(_:at:)`` passing (`init` is `fileprivate`).
    ///
    /// **Every event and every capture takes one**, so a path that skips the guard does not compile (the `LiveSessionHeartbeat.Running` idiom); the activation and the System Events read are the driver's own calls, which no unit test can see, and this is what keeps them from being deleted quietly.
    ///
    /// **What it does not pin:** that focus is still there a second later — it pins that the guard ran, not that its answer still holds, which is what the read just before the event, the after-gesture check and the per-frame check are for. Nor where a mouse event lands: that is the window under the pointer, which ``MirrorWindowStack/clear(_:into:focus:)`` checks on top of a clearance, minting the pass an event is posted on. Nor that the name the decision was fed was read honestly: a caller handing the decision a literal "iPhone Mirroring" gets a token, as a required `Bool` pins a call and not its honesty.
    final class Clearance: Sendable {
        fileprivate init() {}
    }
}
