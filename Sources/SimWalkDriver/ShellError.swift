//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a command could not be run at all — distinct from a command that ran and failed, which is a `Result`.
public enum ShellError: Error, Equatable, CustomStringConvertible {
    case couldNotRun(executable: String, reason: String)
    /// The command was still running when the bound its caller set ran out, and was stopped — a wedged child ends as an answer rather than a hang.
    case timedOut(command: String, seconds: TimeInterval)
    /// A command timed out as `timedOut` did, and something it started was `xcodebuild -runFirstLaunch` when the bound ran out.
    ///
    /// An Xcode's `simctl` script runs it first, and it waits on an administrator password nobody is shown (SimWalk#136). Thrown only on that evidence, read from the stalled tree before it was stopped.
    case stalledOnFirstLaunch(command: String, seconds: TimeInterval)

    public var description: String {
        switch self {
        case let .couldNotRun(executable, reason):
            "cannot run \(executable): \(reason)"
        case let .timedOut(command, seconds):
            "`\(command)` did not finish within \(Int(seconds.rounded()))s and was stopped"
        case let .stalledOnFirstLaunch(command, seconds):
            "`\(command)` did not finish within \(Int(seconds.rounded()))s and was stopped: it was waiting on `xcodebuild -runFirstLaunch` — \(XcodeFirstLaunch.cause); \(XcodeFirstLaunch.fix)"
        }
    }
}

extension ShellError: UsageFailureClassifiable {
    /// Most callers of `Shell.run` in this package are spawning something a walk needs to run at all — `simctl`, `xcodebuild`, `git` while snapshotting the runner — so a process this tool could not even launch is that machinery failing, not an argument a caller of `walk` gave it.
    ///
    /// `runner-failed` is the default for that reason, and every caller of `Shell.run` is that machinery: `claude` is run by the shared library, not through this.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
