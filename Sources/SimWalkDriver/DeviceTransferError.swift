//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a capture bundle could not be brought back from a device, each naming the stage that failed.
///
/// Nothing is left at the output path in either case.
public enum DeviceTransferError: Error, Equatable, CustomStringConvertible, UsageFailureClassifiable {
    /// The copy itself failed or was interrupted.
    case copyFailed(reason: String)
    /// The copy finished but what arrived is not a complete bundle.
    case torn(reason: String)

    public var description: String {
        switch self {
        case let .copyFailed(reason):
            "the bundle could not be copied from the device, and nothing was kept:\n  \(reason)"
        case let .torn(reason):
            "what was copied from the device is not a complete bundle, and nothing was kept:\n  \(reason)"
        }
    }

    /// Both are the device or its transport failing, never an argument a caller gave.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
