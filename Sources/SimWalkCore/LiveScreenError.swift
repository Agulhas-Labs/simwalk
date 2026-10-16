//
// Copyright © Agulhas Labs
//

import Foundation

/// Why `simwalk inspect` could not answer: the app was not there to read, or the runner's file could not be written or read back.
public enum LiveScreenError: Error, Equatable, CustomStringConvertible {
    /// The app was not running on the device, so there was nothing to read — and inspect never launches it.
    case appNotRunning(bundleID: String, udid: String)
    /// No readable file where the runner was told to write — it did not write one.
    case missing(path: String, reason: String)
    /// The file is not a live read.
    case malformed(path: String, reason: String)
    /// The file states a format this build does not read.
    case unsupportedFormatVersion(path: String, found: Int, supported: Int)
    /// The file is of another app, or carries another run's nonce.
    case fromAnotherRun(path: String)
    /// The runner could not write the file.
    case notWritable(path: String, reason: String)

    public var description: String {
        switch self {
        case let .appNotRunning(bundleID, udid):
            "\(bundleID) is not running on \(udid) — inspect reads the app as it stands and never launches it; bring it to the screen you want (xcrun simctl launch \(udid) \(bundleID), or a walk), then inspect again"
        case let .missing(path, reason):
            "no live read at \(path) — the runner did not write one: \(reason)"
        case let .malformed(path, reason):
            "live read at \(path) is torn or not a live read: \(reason)"
        case let .unsupportedFormatVersion(path, found, supported):
            "live read at \(path) states format \(found); this build reads format \(supported)"
        case let .fromAnotherRun(path):
            "live read at \(path) is another run's — of another app, or carrying another inspect's nonce — and is not reported as this one's"
        case let .notWritable(path, reason):
            "cannot write live read at \(path): \(reason)"
        }
    }
}

extension LiveScreenError: UsageFailureClassifiable {
    /// An app not running is the device as the caller left it — a refusal of what was asked, not a failure of the tool; everything else is the host reading back what its own runner wrote, or failed to.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .appNotRunning:
            .inputRefused
        case .missing, .malformed, .unsupportedFormatVersion, .fromAnotherRun, .notWritable:
            .runnerFailed
        }
    }
}
