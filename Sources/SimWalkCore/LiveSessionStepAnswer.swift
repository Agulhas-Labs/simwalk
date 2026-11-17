//
// Copyright © Agulhas Labs
//

import Foundation

/// What a `step` request came to, in its response beside the screen the step left the app on.
///
/// **Three outcomes, and only one of them acted without landing.** `landed` carries the step as a walk records it in `routeTaken` (a `systemTap` with the owner the runner found) and the delta. `blocked` is a step taken that did not land — its reason, and the delta, since a tap that did not navigate may still have changed the screen. `snapshotChanged` is a step **not taken**: the screen's hash was no longer the guard's, so nothing was done and both hashes are named.
public struct LiveSessionStepAnswer: Codable, Equatable, Sendable {
    public let outcome: Outcome
    /// The step as a walkbook records it, for `landed`.
    public let landed: Walkbook.RouteStep?
    /// Why a `blocked` step did not land, where the runner can say.
    public let reason: String?
    /// The guard a `snapshotChanged` step was sent with, or the one a guard that held was sent with (SimWalk#226).
    public let expectedHash: String?
    /// The hash the screen had instead.
    public let foundHash: String?
    /// What the step changed, for a step that was taken.
    public let delta: ScreenDelta?
    /// The element a landed `tap`, `scrollTo`, `type` or `longPress` step bound, as the snapshot read it; `nil` for any other step (SimWalk#93).
    public let bound: AXNode?
    /// The fraction of a text-less screen's picture that moved since the guard's hash was printed (SimWalk#226).
    ///
    /// On a step taken, the guard held across it; on `snapshotChanged`, it is what refused the guard. `nil` when no picture was compared.
    public let pixelsMoved: Double?
    /// How far the largest element of a text screen moved or resized, in points, since the guard's hash was printed, when the guard held across it (SimWalk#252); `nil` otherwise.
    public let pointsMoved: Double?

    private init(outcome: Outcome, landed: Walkbook.RouteStep? = nil, bound: AXNode? = nil, reason: String? = nil, expectedHash: String? = nil, foundHash: String? = nil, delta: ScreenDelta? = nil, pixelsMoved: Double? = nil, pointsMoved: Double? = nil) {
        self.outcome = outcome
        self.landed = landed
        self.reason = reason
        self.expectedHash = expectedHash
        self.foundHash = foundHash
        self.delta = delta
        self.bound = bound
        self.pixelsMoved = pixelsMoved
        self.pointsMoved = pointsMoved
    }

    /// The step landed, and a walk would record it as `recorded`.
    ///
    /// `held` is what the guard held across, when its hash was not the screen's exactly (SimWalk#226, SimWalk#252).
    public static func landed(_ recorded: Walkbook.RouteStep, bound: AXNode? = nil, delta: ScreenDelta, held: Held? = nil) -> LiveSessionStepAnswer {
        LiveSessionStepAnswer(outcome: .landed, landed: recorded, bound: bound, expectedHash: held?.expected, delta: delta, pixelsMoved: held?.pixels, pointsMoved: held?.points)
    }

    /// The step was taken and did not land.
    public static func blocked(reason: String?, delta: ScreenDelta, held: Held? = nil) -> LiveSessionStepAnswer {
        LiveSessionStepAnswer(outcome: .blocked, reason: reason, expectedHash: held?.expected, delta: delta, pixelsMoved: held?.pixels, pointsMoved: held?.points)
    }

    /// The step was not taken: the screen was no longer the one the guard names.
    ///
    /// `moved` is the fraction of the picture that changed since the guard's hash was printed, when it was measured (SimWalk#226).
    public static func snapshotChanged(expected: String, found: String, moved: Double? = nil) -> LiveSessionStepAnswer {
        LiveSessionStepAnswer(outcome: .snapshotChanged, expectedHash: expected, foundHash: found, pixelsMoved: moved)
    }
}

public extension LiveSessionStepAnswer {
    /// A guard that held although the screen's hash was not its own.
    ///
    /// Either a text-less screen's picture moved a little (SimWalk#226) or a text screen's elements did (SimWalk#252); exactly one of ``pixels`` and ``points`` is set.
    struct Held: Equatable, Sendable {
        public let expected: String
        public let pixels: Double?
        public let points: Double?

        /// The fraction of a text-less screen's picture that moved.
        public static func picture(expected: String, moved: Double) -> Held {
            Held(expected: expected, pixels: moved, points: nil)
        }

        /// The largest move, in points, of any element of a text screen.
        public static func frames(expected: String, points: Double) -> Held {
            Held(expected: expected, pixels: nil, points: points)
        }
    }

    /// What a step request came to.
    enum Outcome: String, Codable, Equatable, Sendable {
        case landed
        case blocked
        case snapshotChanged
    }
}
