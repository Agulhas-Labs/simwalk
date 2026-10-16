//
// Copyright © Agulhas Labs
//

import Foundation

/// Why `simwalk session save` wrote nothing.
public enum LiveSessionSaveError: Error, Equatable, CustomStringConvertible {
    /// The session directory holds no `launch.json`, so there is no app or launch state to save a screen under.
    case noLaunchRecord(path: String)
    /// No step landed in the session — or none from request `since` on — and a walkbook screen needs a route.
    case nothingLanded(since: Int?)
    /// These requests, inside the range being saved, were served by a device's runner and never filed on this Mac, so the route may lack a step.
    case unfiledRequests([Int])
    /// The session launched with no state and the device's appearance could not be read when it started, so there is no state to capture the screen in.
    case noState
    /// The walkbook at `path` is for another app.
    case differentApp(path: String, walkbook: String, session: String)
    /// The walkbook at `path` already has a screen with this id.
    case screenExists(path: String, id: String)
    /// The walkbook could not be written.
    case notWritable(path: String, reason: String)

    public var description: String {
        switch self {
        case let .noLaunchRecord(path):
            "the session has no launch record (\(path)), so there is no app or state to save a screen under"
        case let .nothingLanded(since):
            "no step landed in this session\(since.map { " from request \($0) on" } ?? "") — a walkbook screen needs a route; take one with `simwalk session step`"
        case let .unfiledRequests(numbers):
            "\(numbers.count == 1 ? "request" : "requests") \(numbers.map(String.init).joined(separator: ", ")) \(numbers.count == 1 ? "was" : "were") answered by the runner but never filed on this Mac, so the route may lack a step — save from after \(numbers.count == 1 ? "it" : "them") with --since \((numbers.last ?? 0) + 1), or take the route again in a new session"
        case .noState:
            "the session launched with no state and the device's appearance could not be read when it started, so there is no state to capture the screen in — start the session with --state '{\"theme\":\"light\"}'"
        case let .differentApp(path, walkbook, session):
            "\(path) is a walkbook for \(walkbook), and this session drives \(session) — save into a walkbook for \(session), or a new file"
        case let .screenExists(path, id):
            "\(path) already has a screen '\(id)' — save under another --screen id"
        case let .notWritable(path, reason):
            "cannot write \(path): \(reason)"
        }
    }
}

extension LiveSessionSaveError: UsageFailureClassifiable {
    /// A missing launch record or a failed write is this tool and its files; everything else is the caller's argument or what the session did.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .nothingLanded, .unfiledRequests, .noState, .differentApp, .screenExists:
            .inputRefused
        case .noLaunchRecord, .notWritable:
            .toolError
        }
    }
}
