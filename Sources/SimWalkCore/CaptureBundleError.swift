//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a capture bundle could not be read or written.
///
/// Reading is where the honesty matters: a bundle with no manifest, or a manifest torn off mid-write by a crashed runner, is refused by name. It is never filled in with defaults, because a default-filled manifest is a walk that claims to have happened.
public enum CaptureBundleError: Error, Equatable, CustomStringConvertible {
    /// The path is not named as a bundle, whatever it holds — the extension is the marker that makes a walk's output recognisable without opening it.
    case misnamedBundle(path: String, expectedExtension: String)
    /// Nothing is at the bundle path, or it is a file where a bundle directory was expected.
    case notABundle(path: String)
    /// The bundle directory exists but holds no manifest — an interrupted run, or a directory that was never a bundle.
    case manifestMissing(bundlePath: String, expectedPath: String)
    /// The manifest exists but could not be read from disk.
    case manifestUnreadable(path: String, reason: String)
    /// The manifest was read but is not a manifest: truncated JSON, or JSON of the wrong shape.
    case manifestMalformed(path: String, reason: String)
    /// The manifest states a bundle format this build does not know how to read.
    case unsupportedFormatVersion(path: String, found: Int, supported: [Int])
    /// An artefact the manifest names is present and could not be read as what it claims to be — named, because a decoding failure that names no file is a refusal a reader cannot act on.
    case artefactUnreadable(path: String, reason: String)
    /// An artefact is the untyped dump of a bundle format older than the one that replaced it — the same refusal as `artefactUnreadable` in words, but the cause is the bundle's age, which only a caller's own old bundle has.
    case artefactFromOlderFormat(path: String, reason: String)
    /// The manifest parses but contradicts itself, or claims artefacts the bundle does not hold; every problem found is listed, not just the first.
    case manifestInvalid(path: String, problems: [CaptureManifestProblem])
    /// The bundle could not be written.
    case notWritable(path: String, reason: String)
    /// A bundle was to be written where one already is; a re-run must not validate on the previous run's artefacts.
    case bundleDirectoryNotEmpty(path: String, entries: Int)
    /// A walk read back a bundle that is not this walk's own: started before the walk launched its runner, followed against another build, or carrying another walk's nonce or none at all — the way `RouteProbeReport.read` refuses a report from another run (SimWalk#36, SimWalk#41).
    case bundleFromAnotherWalk(path: String, problems: [String])

    public var description: String {
        switch self {
        case let .misnamedBundle(path, expectedExtension):
            "\(path) is not named as a capture bundle — a bundle directory ends in .\(expectedExtension), which is what makes a walk's output recognisable without opening it"
        case let .notABundle(path):
            "no capture bundle at \(path) — expected a directory"
        case let .manifestMissing(bundlePath, expectedPath):
            "capture bundle at \(bundlePath) has no manifest — expected \(expectedPath); the run that wrote it did not finish"
        case let .manifestUnreadable(path, reason):
            "cannot read manifest at \(path): \(reason)"
        case let .manifestMalformed(path, reason):
            "manifest at \(path) is torn or not a manifest: \(reason)"
        case let .unsupportedFormatVersion(path, found, supported):
            "manifest at \(path) states bundle format \(found); this build reads \(supported.count == 1 ? "format" : "formats") \(supported.sorted().map(String.init).joined(separator: ", "))"
        case let .artefactUnreadable(path, reason), let .artefactFromOlderFormat(path, reason):
            "cannot read \(path): \(reason)"
        case let .manifestInvalid(path, problems):
            ([
                "manifest at \(path) does not describe a walk that could have happened — \(problems.count) problem\(problems.count == 1 ? "" : "s"):",
            ] + problems.map { "  - \($0)" }).joined(separator: "\n")
        case let .notWritable(path, reason):
            "cannot write capture bundle at \(path): \(reason)"
        case let .bundleDirectoryNotEmpty(path, entries):
            "\(path) already holds \(entries) item\(entries == 1 ? "" : "s") — a walk writes a fresh bundle, or it would validate on the previous run's artefacts; remove it or choose another path"
        case let .bundleFromAnotherWalk(path, problems):
            ([
                "the bundle at \(path) is another walk's, and is not reported as this one's:",
            ] + problems.map { "  - \($0)" }).joined(separator: "\n")
        }
    }
}

public extension CaptureBundleError {
    /// Every way `manifest` fails to be the bundle a walk that launched its runner at `walkLaunchedAt`, against `buildHash`, and carrying `nonce` actually wrote — all of them, not the first, the way `RouteProbeReport.problems(against:)` collects a report's.
    ///
    /// `WalkCommand.bundleWrittenBy` is the one caller: the bundle's own module states the check so the date and hash formatting stay inside it, and the CLI only assembles the refusal.
    static func problems(_ manifest: CaptureManifest, walkLaunchedAt: Date, buildHash: String, nonce: String) -> [String] {
        var problems: [String] = []
        if manifest.startedAt < walkLaunchedAt.addingTimeInterval(-1) {
            problems.append("it started at \(Timestamp.string(from: manifest.startedAt)), before this walk launched its runner at \(Timestamp.string(from: walkLaunchedAt))")
        }
        if manifest.appBuildHash != buildHash {
            problems.append("it was walked against build \(ShortHash.of(manifest.appBuildHash)), not \(ShortHash.of(buildHash)), the one this walk installed")
        }
        if manifest.nonce != nonce {
            problems.append(manifest.nonce == nil
                ? "it carries no nonce — it predates this walk's own"
                : "it carries another walk's nonce — an overlapping walk of this build wrote it")
        }
        return problems
    }
}

extension CaptureBundleError: UsageFailureClassifiable {
    /// The manifest-level cases default to `.inputRefused`: `bundle inspect` and `bundle audit` throw every one of them while reading the one bundle path a caller named as their argument, and `walk` throws `bundleDirectoryNotEmpty`/`misnamedBundle` from the same pre-flight check on `--output` before it boots anything — a bad argument in both.
    ///
    /// `artefactUnreadable` is the one case given a different default: `bundle audit` is the only thing that decodes an accessibility tree, and a walk's own read-back checks only that the tree files exist, not that they decode — so a mismatch between how the runner writes a tree and how the host reads it surfaces first here, on a bundle this tool just wrote, which is the runner's problem to answer for rather than a bad argument.
    ///
    /// One exception to the default applies regardless of case: `walk` reading back the bundle its own runner just wrote (`WalkCommand.bundleWrittenBy`) means the runner's output does not hold up, not that a caller pointed the tool at something bad. That site does not rely on this default — it always escapes wrapped in `WalkCommand.Refusal`, which conforms to `.runnerFailed` directly.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .artefactUnreadable:
            .runnerFailed
        case .misnamedBundle, .notABundle, .manifestMissing, .manifestUnreadable, .manifestMalformed,
             .unsupportedFormatVersion, .artefactFromOlderFormat, .manifestInvalid, .notWritable, .bundleDirectoryNotEmpty, .bundleFromAnotherWalk:
            .inputRefused
        }
    }
}
