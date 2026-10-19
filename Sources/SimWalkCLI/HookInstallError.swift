//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// Why a registration with Claude Code could not be made or unmade.
enum HookInstallError: Error, Equatable, CustomStringConvertible {
    /// The shared install reported what it set out to do and could not, one line each, quoted rather than paraphrased — and carries whatever the install had already written by then.
    case claudeRefused(failures: [String], written: [String] = [])

    var description: String {
        switch self {
        case let .claudeRefused(failures, written):
            Self.refusal(failures: failures, written: written)
        }
    }

    /// A refusal that declares its own gap: the registration is the last step, so anything it leaves behind was written before it and the caller has to be told what and how to undo it.
    ///
    /// The answer contract's rule that every answer states its own arithmetic applies to a refusal too — one that says only "`claude` failed" leaves somebody with a status line and a user rule pointing at tools that are not registered, and nothing on screen saying either exists.
    private static func refusal(failures: [String], written: [String]) -> String {
        let opening = failures.joined(separator: "\n")
        guard !written.isEmpty else { return opening }
        return ([opening + "\n— the steps below had already been taken, and `simwalk uninstall-hook` takes them back:"]
            + written.map { "  \($0)" }).joined(separator: "\n")
    }
}

extension HookInstallError: UsageFailureClassifiable {
    /// A refusal is not about a walkbook, a route, the walk runner or a device — it is Claude Code's own CLI refusing a registration, which is what `setup-failed` names.
    var usageFailureKind: UsageFailureKind {
        .setupFailed
    }
}
