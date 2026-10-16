//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// Why a Claude Code settings file could not be merged into.
public enum StatuslineRegistrationError: Error, Equatable, CustomStringConvertible {
    /// The file exists and is not a JSON object, so there is nothing to merge a status line into.
    case settingsNotAnObject(path: String)

    public var description: String {
        switch self {
        case let .settingsNotAnObject(path):
            "cannot read \(path) as a JSON object — this is Claude Code's whole configuration and simwalk will not overwrite what it cannot parse; fix or move the file and run install-hook again"
        }
    }
}

extension StatuslineRegistrationError: UsageFailureClassifiable {
    /// The settings file is usually Claude Code's own default path, not something the caller typed — the same shape as `HookInstallError`, which this now matches: Claude Code's own configuration refusing a merge, not a bad argument.
    public var usageFailureKind: UsageFailureKind {
        .setupFailed
    }
}
