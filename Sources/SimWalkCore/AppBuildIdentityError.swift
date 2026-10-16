//
// Copyright © Agulhas Labs
//

import Foundation

/// Why an installed app could not be identified.
public enum AppBuildIdentityError: Error, Equatable, CustomStringConvertible {
    case notAnApp(path: String)
    case unreadableExecutable(path: String, reason: String)

    public var description: String {
        switch self {
        case let .notAnApp(path):
            "\(path) is not an app bundle — no readable Info.plist naming a CFBundleExecutable"
        case let .unreadableExecutable(path, reason):
            "cannot read \(path) to identify the build being walked: \(reason)"
        }
    }
}

extension AppBuildIdentityError: UsageFailureClassifiable {
    /// Both cases fire against the path the simulator itself reports for an already-installed bundle ID — by the time either can happen, the bundle ID a caller named has already resolved, so this is the installed app or the machine reading it, never the argument.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
