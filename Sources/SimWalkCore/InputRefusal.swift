//
// Copyright © Agulhas Labs
//

import Foundation

/// An argument refused before anything is run, posted or captured: a `mirror` argument (SimWalk#113), or a `bundle audit --only motionBudget` with no budgets to check (SimWalk#67).
///
/// **Its own type so the refusal logs as `inputRefused`.** ArgumentParser's `ValidationError` carries no kind, so it would log as the command's default `toolError` and a bad argument would count as a failure of the tool; this one classifies itself, as ``MirrorFraction/OutOfRange`` does.
public struct InputRefusal: LocalizedError, Equatable, Sendable {
    /// The sentence naming the argument, what was given and what is accepted.
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

extension InputRefusal: CustomStringConvertible {
    /// The refusal's own sentence, for `TimedCall`, which prints `String(describing:)`.
    public var description: String {
        message
    }
}

extension InputRefusal: UsageFailureClassifiable {
    /// A bad argument: retrying it changes nothing.
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
