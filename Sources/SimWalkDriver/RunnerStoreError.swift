//
// Copyright © Agulhas Labs
//

import Foundation

/// Why the runner could not be snapshotted.
public enum RunnerStoreError: Error, Equatable, CustomStringConvertible {
    case notACheckout(path: String, reason: String)

    public var description: String {
        switch self {
        case let .notACheckout(path, reason):
            "\(path) is not a git checkout the runner can be snapshotted from (\(reason))"
        }
    }
}
