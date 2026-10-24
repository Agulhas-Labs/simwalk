//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a live session's channel could not carry a request or its answer.
public enum LiveSessionError: Error, Equatable, CustomStringConvertible {
    /// A response was asked for a request that was never sent.
    case noSuchRequest(number: Int, path: String)
    /// A channel file is not what its name says it is — torn, of another shape, or numbered other than its name.
    case malformed(path: String, reason: String)
    /// A channel file could not be written.
    case notWritable(path: String, reason: String)
    /// The runner stopped before answering.
    ///
    /// `cause` is what the host found the runner left behind when it wrote no exit record — its result bundle's failure, the last of `xcodebuild`'s output (SimWalk#240) — a line each; empty when nothing was kept.
    case runnerExited(number: Int, exit: LiveSessionExit?, cause: [String] = [])
    /// The runner is still running and has not answered within the wait.
    case noResponse(number: Int, waited: TimeInterval)
    /// A device exchange was filed under a number that already has a request: two answers under one number.
    case alreadyFiled(number: Int, path: String)
    /// A guarded step was not taken: the screen's hash was `found`, not the `expected` the step was guarded by.
    ///
    /// `moved` is the fraction of the picture that changed since the guard's hash was printed, when it was measured (SimWalk#226).
    case snapshotChanged(expected: String, found: String, moved: Double? = nil)

    public var description: String {
        switch self {
        case let .noSuchRequest(number, path):
            "no request \(number) was sent in this session (\(path) does not exist), so there is no response to wait for"
        case let .malformed(path, reason):
            "session file \(path) is torn or not what its name says: \(reason)"
        case let .notWritable(path, reason):
            "cannot write session file \(path): \(reason)"
        case let .runnerExited(number, exit, cause):
            "the session's runner stopped before answering request \(number)\(exit.map { " — \($0.summary)" } ?? ", leaving no exit record")"
                + cause.map { "\n\($0)" }.joined()
        case let .noResponse(number, waited):
            "the session's runner did not answer request \(number) within \(Int(waited.rounded())) s"
        case let .alreadyFiled(number, path):
            "request \(number) is already filed at \(path): the runner answered two requests under one number"
        case let .snapshotChanged(expected, found, moved):
            "snapshotChanged: the screen is \(found), not \(expected) as guarded\(moved.map { ", and \(ScreenDelta.percentOfScreen($0)) of the screen changed since it was read" } ?? ""), so the step was not taken — read it again (`simwalk session read`) and guard the step with the hash that read prints"
        }
    }
}

extension LiveSessionError: UsageFailureClassifiable {
    /// Asking after a request never sent is the caller's; everything else is the runner, or the files it and the host share.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .noSuchRequest, .snapshotChanged:
            .inputRefused
        case .malformed, .notWritable, .runnerExited, .noResponse, .alreadyFiled:
            .runnerFailed
        }
    }
}
