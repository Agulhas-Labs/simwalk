//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a walk could not be built or run.
public enum RunnerError: Error, Equatable, CustomStringConvertible {
    case buildFailed(reason: String)
    case walkFailed(reason: String)
    /// A device walk's measure run (`testMeasure`) did not complete; the walk goes on without its record.
    case measureFailed(reason: String)

    public var description: String {
        switch self {
        case let .buildFailed(reason):
            "the walk runner could not be built:\n  \(reason)"
        case let .walkFailed(reason):
            "the walk did not complete:\n  \(reason)"
        case let .measureFailed(reason):
            "the measure run did not complete: \(reason)"
        }
    }
}

extension RunnerError: UsageFailureClassifiable {
    /// Every case is the runner itself — `xcodebuild` failing to build it, or the walk or measure run it ran failing to complete — never an argument a caller gave.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
