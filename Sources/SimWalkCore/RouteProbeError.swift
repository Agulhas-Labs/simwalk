//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a dry run's route-probe file could not be written or read back.
public enum RouteProbeError: Error, Equatable, CustomStringConvertible {
    /// The output path is not named as a probe file.
    case misnamed(path: String, expectedExtension: String)
    /// Something is already at the output path.
    case alreadyExists(path: String)
    /// No readable file at the path — the runner did not write one.
    case missing(path: String, reason: String)
    /// The file is not a probe report.
    case malformed(path: String, reason: String)
    /// The file states a format this build does not read.
    case unsupportedFormatVersion(path: String, found: Int, supported: Int)
    /// The report does not describe a dry run of the walkbook it was held to.
    case invalid(path: String, problems: [String])
    /// The report could not be written.
    case notWritable(path: String, reason: String)
    /// The report describes the walkbook but not this run: another build, or a runner started before this run launched its own.
    case fromAnotherRun(path: String, problems: [String])

    public var description: String {
        switch self {
        case let .misnamed(path, expectedExtension):
            "\(path) is not named as a route-probe file — a dry run writes a .\(expectedExtension) file, never a capture bundle, because it captures nothing"
        case let .alreadyExists(path):
            "\(path) already exists — a dry run writes a fresh file, or a report left there could be read back as this run's; remove it or choose another path"
        case let .missing(path, reason):
            "no route-probe report at \(path) — the runner did not write one: \(reason)"
        case let .malformed(path, reason):
            "route-probe report at \(path) is torn or not a report: \(reason)"
        case let .unsupportedFormatVersion(path, found, supported):
            "route-probe report at \(path) states format \(found); this build reads format \(supported)"
        case let .invalid(path, problems):
            ([
                "route-probe report at \(path) does not describe a dry run of this walkbook — \(problems.count) problem\(problems.count == 1 ? "" : "s"):",
            ] + problems.map { "  - \($0)" }).joined(separator: "\n")
        case let .notWritable(path, reason):
            "cannot write route-probe report at \(path): \(reason)"
        case let .fromAnotherRun(path, problems):
            ([
                "route-probe report at \(path) is another run's, and is not reported as this one's:",
            ] + problems.map { "  - \($0)" }).joined(separator: "\n")
        }
    }
}

extension RouteProbeError: UsageFailureClassifiable {
    /// An output path refused before anything boots is a caller's argument; everything else is the host reading back what its own runner just wrote — or failed to — which is the runner's to answer for.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        // Another run's report at the path is what a walk's `bundleFromAnotherWalk` is, and classed with it.
        case .misnamed, .alreadyExists, .fromAnotherRun:
            .inputRefused
        case .missing, .malformed, .unsupportedFormatVersion, .invalid, .notWritable:
            .runnerFailed
        }
    }
}
