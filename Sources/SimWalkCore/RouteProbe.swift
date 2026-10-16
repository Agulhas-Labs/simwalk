//
// Copyright © Agulhas Labs
//

import Foundation

/// One screen's route, followed against a running app without capturing anything — what `walk --dry-run` records per screen (SimWalk#1 item 4).
///
/// **The steps are followed, not merely looked up.** A label on the second step exists only on the screen the first step reaches, so a probe that only searched the launch screen for every label would call a perfectly good route drifted. The runner performs each step exactly as a walk does — `WalkRunner.perform`, the same resolvers and the same arrival check — which is what makes a dry run and a walk unable to disagree about what a label matches: there is one implementation of "this step landed", and both modes call it.
///
/// **The whole route is carried, and the outcome indexes into it**, rather than the probe restating which steps resolved. Completed-then-failed-then-not-reached is the only shape a followed route can have, so a record that could state the three lists independently could state an impossible one.
public struct RouteProbe: Codable, Equatable, Sendable {
    /// The walkbook screen this route leads to.
    public let screenID: String
    /// The route, every step attempted or not: each step that landed as the runner recorded it — a `systemTap` with the tree it found the control in, as a walk's `routeTaken` carries it — and the rest as the walkbook states them.
    public let route: [Walkbook.RouteStep]
    /// What following it came to.
    public let outcome: Outcome

    public init(screenID: String, route: [Walkbook.RouteStep], outcome: Outcome) {
        self.screenID = screenID
        self.route = route
        self.outcome = outcome
    }
}

public extension RouteProbe {
    /// What following a route came to.
    enum Outcome: Codable, Equatable, Sendable {
        /// Every step landed, as it would have in a walk.
        case resolved
        /// The step at `step` (0-based) did not land: its label matched nothing, or matched something that did not move the screen.
        ///
        /// Every step before it landed; none after it was attempted.
        ///
        /// `reason` is what the runner could say about it — what the label matched, and what the tap did — `nil` where it could say nothing more.
        ///
        /// `cause` is the reason's name where the walk's verdict counts it on its own (`ScreenOutcome.UnreachableCause`).
        case drifted(step: Int, reason: String?, cause: ScreenOutcome.UnreachableCause? = nil)
        /// Reading the hierarchy failed at the step at `step` (0-based), so whether it landed is unknown.
        ///
        /// A fact about the device, never about the app — the same split a walk makes between `unreachable` and `captureFailed`.
        case unreadable(step: Int, reason: String)

        /// **Forward-compatible on `cause` (SimWalk#58 item 3).**
        ///
        /// A cause is decoded by its raw string and matched with `UnreachableCause`'s failable initializer, so a value a future binary added and this one does not know — never named a case here — decodes as `nil` rather than failing the whole probe. The rest of the enum is decoded by hand only because `cause` needed this one exception, and like the synthesized decoding it replaced it refuses a payload naming any number of cases but one (SimWalk#61 item 3): two case keys are a corrupt payload, not a choice for the first one to settle.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.allKeys.count == 1, let key = container.allKeys.first else {
                let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "RouteProbe.Outcome payload names \(container.allKeys.count) cases, not one")
                throw DecodingError.dataCorrupted(context)
            }
            switch key {
            case .resolved:
                self = .resolved
            case .drifted:
                let nested = try container.nestedContainer(keyedBy: DriftedKeys.self, forKey: .drifted)
                let cause = try nested.decodeIfPresent(String.self, forKey: .cause).flatMap { ScreenOutcome.UnreachableCause(rawValue: $0) }
                self = try .drifted(step: nested.decode(Int.self, forKey: .step), reason: nested.decodeIfPresent(String.self, forKey: .reason), cause: cause)
            case .unreadable:
                let nested = try container.nestedContainer(keyedBy: UnreadableKeys.self, forKey: .unreadable)
                self = try .unreadable(step: nested.decode(Int.self, forKey: .step), reason: nested.decode(String.self, forKey: .reason))
            }
        }
    }

    /// The steps that landed, in order.
    var resolvedSteps: [Walkbook.RouteStep] {
        guard let index = failedStepIndex else { return route }
        return Array(route.prefix(index))
    }

    /// The step the probe stopped at, when it stopped short.
    var failedStep: Walkbook.RouteStep? {
        failedStepIndex.flatMap { route.indices.contains($0) ? route[$0] : nil }
    }

    /// The steps after the one it stopped at, which were never attempted.
    var unreachedSteps: [Walkbook.RouteStep] {
        guard let index = failedStepIndex, index < route.count else { return [] }
        return Array(route.suffix(from: index + 1))
    }

    /// Whether every step landed.
    var isResolved: Bool {
        failedStepIndex == nil
    }

    /// The 0-based index of the step the probe stopped at, or `nil` when it resolved.
    var failedStepIndex: Int? {
        switch outcome {
        case .resolved: nil
        case let .drifted(step, _, _): step
        case let .unreadable(step, _): step
        }
    }
}

private extension RouteProbe.Outcome {
    enum CodingKeys: String, CodingKey {
        case resolved, drifted, unreadable
    }

    enum DriftedKeys: String, CodingKey {
        case step, reason, cause
    }

    enum UnreadableKeys: String, CodingKey {
        case step, reason
    }
}
