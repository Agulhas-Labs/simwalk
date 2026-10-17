//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a walk, an inspect or a session start was refused before touching a device: this Xcode's `simctl` would first run `xcodebuild -runFirstLaunch` (SimWalk#136).
public enum XcodeFirstLaunchError: Error, Equatable, CustomStringConvertible {
    /// The installed CoreSimulator is `installed` (`nil`: no version could be read) and this Xcode's `simctl` expects `expected`.
    case pending(installed: String?, expected: String)

    public var description: String {
        switch self {
        case let .pending(installed, expected):
            "this Xcode's simctl expects CoreSimulator \(expected) and \(installed.map { "\($0) is installed" } ?? "no installed version could be read"), so \(XcodeFirstLaunch.cause) — \(XcodeFirstLaunch.fix)"
        }
    }
}

extension XcodeFirstLaunchError: UsageFailureClassifiable {
    /// The machine's Xcode not being ready to run `simctl` at all — the walk's machinery, as `simctl` failing is (`SimulatorError.simctlFailed`), not anything a caller typed.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
