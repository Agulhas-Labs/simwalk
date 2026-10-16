//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a subset could not be taken.
public enum WalkbookSubsetError: Error, Equatable, CustomStringConvertible {
    /// One or more requested ids are not in the walkbook — a typo, or a screen renamed since the command was last run.
    case unknownScreens(requested: [String], available: [String])

    public var description: String {
        switch self {
        case let .unknownScreens(requested, available):
            // The available list is spelled out rather than counted: the whole point of the failure is
            // that the caller's idea of the screen's name is wrong, so the answer has to carry the right
            // ones. A walkbook is a dozen screens, not a thousand.
            let names = requested.map { "'\($0)'" }.joined(separator: ", ")
            return "no screen named \(names) in this walkbook — it has: \(available.joined(separator: ", "))"
        }
    }
}

extension WalkbookSubsetError: UsageFailureClassifiable {
    /// `--screens`/`screenIDs` naming an id the walkbook does not have is a bad argument, the same as any other value a caller typed wrong.
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
