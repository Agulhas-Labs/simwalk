//
// Copyright © Agulhas Labs
//

import Foundation

/// Why `discover` stopped without a draft.
public enum DiscoverError: Error, Equatable, CustomStringConvertible {
    /// The app was not running when the crawl read it at launch.
    case appNotRunning
    /// The runner could not serve a step: its own words, and the step.
    case stepFailed(step: Walkbook.RouteStep, failure: String)
    /// An app with no tab bar whose launch screen carries no label a route could start by.
    case nothingToRouteBy
    /// The run was cancelled — a SIGINT or SIGTERM — before the crawl finished.
    case cancelled
    /// `--output` names a file that is already there: a draft is a whole walkbook, and merging it into one is the author's call.
    case outputExists(path: String)
    /// The draft could not be written.
    case notWritable(path: String, reason: String)
    /// The session has no capture state to draft its screens in: launched plain on a device whose appearance could not be read.
    case noState

    public var description: String {
        switch self {
        case .appNotRunning:
            "the app was not running at launch, so there is no screen to start from"
        case let .stepFailed(step, failure):
            "the runner could not serve \(step): \(failure)"
        case .nothingToRouteBy:
            "the launch screen has no tab bar and no labelled element a route could start by"
        case .cancelled:
            "the run was cancelled before the crawl finished; nothing was written"
        case let .outputExists(path):
            "\(path) already exists; a draft is a whole walkbook, so name a new file and merge it yourself"
        case let .notWritable(path, reason):
            "could not write the draft to \(path): \(reason)"
        case .noState:
            "the session was launched plain and the device's appearance could not be read, so there is no state to draft the screens in; pass --state"
        }
    }
}
