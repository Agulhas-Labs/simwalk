//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why `session step` refused its step before sending anything: the JSON is not a route step, or a step `validate` would refuse.
///
/// Both are the caller's own argument, so they log as `input-refused` rather than as the runner failing (SimWalk#293). A bare `ValidationError` carries no kind, and `session step`'s fallback is `runner-failed`.
struct SessionStepRefusal: Error, CustomStringConvertible, UsageFailureClassifiable {
    let description: String

    /// The step text did not decode as a route step; `error`'s own debug description is the problem, without the `DecodingError` wrapper around it.
    init(undecodable step: String, because error: any Error) {
        let problem = (error as? DecodingError).map(Self.problem(of:)) ?? String(describing: error)
        description = "'\(step)' is not a walkbook route step: \(problem); write one as a walkbook does, e.g. {\"tap\":{\"label\":\"Next\"}}"
    }

    /// The step decoded but the loader's checks refuse it.
    init(refused step: String, because problem: String) {
        description = "'\(step)' would be refused by validate, so nothing was sent: \(problem)"
    }

    var usageFailureKind: UsageFailureKind {
        .inputRefused
    }

    private static func problem(of error: DecodingError) -> String {
        switch error {
        case let .dataCorrupted(context), let .keyNotFound(_, context), let .typeMismatch(_, context), let .valueNotFound(_, context):
            context.debugDescription
        @unknown default:
            String(describing: error)
        }
    }
}
