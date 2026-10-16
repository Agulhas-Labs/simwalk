//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a bundle's figures cannot be checked at all.
public enum OracleCheckError: Error, Equatable, CustomStringConvertible, UsageFailureClassifiable {
    /// A capture the walkbook names figures for records no capture time — a bundle written before `capturedAt` existed.
    case noCaptureTime(screenID: String, stateSlug: String)
    /// The walkbook names no `oracle` command, so there is nothing to ask.
    case noOracle

    public var description: String {
        switch self {
        case .noOracle:
            "the walkbook names no 'oracle' — add {\"oracle\": {\"command\": [\"path\", …]}} beside its screens' 'figures' to check figures against one"
        case let .noCaptureTime(screenID, stateSlug):
            "capture \(screenID)/\(stateSlug) records no capture time — a rolling window is meaningless without it, so the bundle's figures are not checked; walk it again with this build"
        }
    }

    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
