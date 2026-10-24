//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a walk could not be built or run.
public enum RunnerError: Error, Equatable, CustomStringConvertible {
    case buildFailed(reason: String)
    /// `status` is what `xcodebuild` exited with, where a simulator walk's runner ran and exited non-zero; `nil` where nothing exited.
    case walkFailed(reason: String, status: Int32? = nil)
    /// A device walk's measure run (`testMeasure`) did not complete; the walk goes on without its record.
    case measureFailed(reason: String)

    public var description: String {
        switch self {
        case let .buildFailed(reason):
            "the walk runner could not be built:\n  \(reason)"
        case let .walkFailed(reason, _):
            "the walk did not complete:\n  \(reason)"
        case let .measureFailed(reason):
            "the measure run did not complete: \(reason)"
        }
    }

    /// Whether the runner ran its test and `xcodebuild` reported it failed (exit 65) — never a stop, a timeout, a launch that never happened or a build.
    public var isTestFailure: Bool {
        guard case let .walkFailed(_, status) = self else { return false }
        return status == 65
    }
}

extension RunnerError: UsageFailureClassifiable {
    /// Every case is the runner itself — `xcodebuild` failing to build it, or the walk or measure run it ran failing to complete — never an argument a caller gave.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
