//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// A walk's failure after it took a slim or stock decision, carrying that decision and the memory its device held, for the usage log.
///
/// It says what the failure it wraps says and is classified as it is, so the walk's printed error and exit are unchanged; only the usage line gains `slim`.
struct SlimmedWalkFailure: Error, CustomStringConvertible, UsageFailureClassifiable, SlimUsageCarrying {
    let underlying: Error
    let slimUsage: SlimUsage?

    var usageFailureKind: UsageFailureKind {
        UsageFailureKind.of(underlying) ?? .runnerFailed
    }

    var description: String {
        String(describing: underlying)
    }

    /// `error` as it is when the walk took no decision, else wrapped with the decision.
    static func carrying(_ slim: SlimUsage?, _ error: Error) -> Error {
        slim.map { SlimmedWalkFailure(underlying: error, slimUsage: $0) } ?? error
    }
}
