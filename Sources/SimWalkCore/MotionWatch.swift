//
// Copyright © Agulhas Labs
//

import Foundation

/// What the route told a capture's motion watch (SimWalk#67, M2): how long its last step took to land, and whether that step asked for a scroll.
///
/// `SettledCapture.take` is handed one where the walk records motion and `nil` where it does not, so the reads are kept only when asked for.
public struct MotionWatch: Equatable, Sendable {
    /// How long the route's last step took from its action returning to the read that showed it had arrived; `nil` for a screen with no route or a step that does not wait for arrival (`CaptureManifest.Motion.landingMilliseconds`).
    public let landing: TimeInterval?
    /// Whether the route's last step asked for a scroll — a `scrollTo`, a `swipe`, which leaves a list mid-fling, or a `systemTap`, which drags a sheet's list when its control is below the fold — so that `LayoutShiftRule` reads the scroll still decelerating in the watch as the walk's motion, not the app's.
    ///
    /// Every `systemTap` counts, dragged or not: the runner does not report whether it dragged, and treating an undragged one as a scroll only drops shifts inside a scroll container that move with the container's content.
    public let afterScroll: Bool

    /// - Parameters:
    ///   - lastStep: The route's last step, as walked; `nil` for a screen with no route.
    ///   - landing: How long that step took to land, where it waits for arrival.
    public init(lastStep: Walkbook.RouteStep?, landing: TimeInterval?) {
        self.landing = landing
        switch lastStep {
        case .scrollTo, .systemTap, .swipe, .drag:
            afterScroll = true
        case .tab, .tap, .type, .longPress, .tapPoint, .openURL, .back, nil:
            afterScroll = false
        }
    }
}
