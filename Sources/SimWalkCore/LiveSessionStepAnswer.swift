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
    /// The guard a `snapshotChanged` step was sent with.
    public let expectedHash: String?
    /// The hash the screen had instead.
    public let foundHash: String?
    /// What the step changed, for a step that was taken.
    public let delta: ScreenDelta?
    /// The element a landed `tap`, `scrollTo` or `type` step bound, as the snapshot read it; `nil` for any other step (SimWalk#93).
    public let bound: AXNode?

    private init(outcome: Outcome, landed: Walkbook.RouteStep? = nil, bound: AXNode? = nil, reason: String? = nil, expectedHash: String? = nil, foundHash: String? = nil, delta: ScreenDelta? = nil) {
        self.outcome = outcome
        self.landed = landed
        self.reason = reason
        self.expectedHash = expectedHash
        self.foundHash = foundHash
        self.delta = delta
        self.bound = bound
    }

    /// The step landed, and a walk would record it as `recorded`.
    public static func landed(_ recorded: Walkbook.RouteStep, bound: AXNode? = nil, delta: ScreenDelta) -> LiveSessionStepAnswer {
        LiveSessionStepAnswer(outcome: .landed, landed: recorded, bound: bound, delta: delta)
    }

    /// The step was taken and did not land.
    public static func blocked(reason: String?, delta: ScreenDelta) -> LiveSessionStepAnswer {
        LiveSessionStepAnswer(outcome: .blocked, reason: reason, delta: delta)
    }

    /// The step was not taken: the screen was no longer the one the guard names.
    public static func snapshotChanged(expected: String, found: String) -> LiveSessionStepAnswer {
        LiveSessionStepAnswer(outcome: .snapshotChanged, expectedHash: expected, foundHash: found)
    }
}

public extension LiveSessionStepAnswer {
    /// What a step request came to.
    enum Outcome: String, Codable, Equatable, Sendable {
        case landed
        case blocked
        case snapshotChanged
    }
}
