//
// Copyright © Agulhas Labs
//

import Foundation

/// Decides, read by read after an `openURL` step hands its URL over, whether the step has landed.
///
/// **Arrival is two things, not one.** Like a navigating `tap`, the hierarchy has to leave the screen the step was taken on (`ScreenIdentity`) — but a URL can also leave *the app*. An `https` URL that is not a universal link opens Safari: the walked app goes to the background, its tree changes because it is no longer drawn in front, and identity alone read that as arrival, so the capture that followed was filed under the target screen's id and was not of it. So the app must also still be in front; a step that leaves it behind another app does not land, and the answer says so, which makes the screen UNREACHABLE naming the step.
///
/// **In the core, not the runner, because nothing in `Runner/` is exercised by `swift test`.** The runner keeps the clock and the reads — whether the app is in front, and only then whether its tree has left the screen — and asks here what to do next, the shape `TapPointLanding` and `SettleTracker` set.
public struct OpenURLLanding {
    /// What the UNREACHABLE says beyond the route when the app was behind another at the end of the wait.
    public static var notInFrontReason: String {
        "the app was not in front after opening the URL"
    }

    /// What the runner should do after one read.
    ///
    /// - Parameters:
    ///   - appInFront: Whether the walked app was running in the foreground at this read.
    ///   - leftScreen: Whether the app's tree had left the screen the step was taken on; not consulted when the app was not in front.
    ///   - pastDeadline: Whether the destination's settle budget has run out.
    public static func next(appInFront: Bool, leftScreen: Bool, pastDeadline: Bool) -> Decision {
        if appInFront, leftScreen {
            return .landed
        }
        if !pastDeadline {
            return .watch
        }
        return .notLanded(reason: appInFront ? nil : notInFrontReason)
    }
}

public extension OpenURLLanding {
    /// The runner's next move.
    enum Decision: Equatable, Sendable {
        /// Wait one interval and read again.
        case watch
        /// The app is in front and its tree has left the screen the step was taken on.
        case landed
        /// The budget ran out without arriving; `reason` is what the UNREACHABLE says beyond the route, `nil` where there is nothing more to say.
        case notLanded(reason: String?)
    }
}
