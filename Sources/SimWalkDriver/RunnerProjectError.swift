//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why the walk runner's project could not be located.
public enum RunnerProjectError: Error, Equatable, CustomStringConvertible {
    case overrideMissing(variable: String, path: String)
    /// No snapshot was paired with this binary; the payload names its hash and what the latest install did pair, if anything.
    case notInstalled(binaryHash: String, latest: RunnerStore.Binding?, variable: String)
    /// The binding names a snapshot that is no longer on disk.
    case snapshotMissing(path: String, commit: String)
    /// The running binary could not be read to hash, so which snapshot it goes with cannot be told.
    case binaryUnreadable(variable: String)

    public var description: String {
        switch self {
        case let .overrideMissing(variable, path):
            "\(variable) points at \(path), which is not there — a walk builds the runner from source, so that path must be a SimWalkRunner.xcodeproj"
        case let .notInstalled(binaryHash, latest, variable):
            ([
                "no walk runner is installed for this simwalk binary (sha256 \(ShortHash.of(binaryHash))) — the runner and the binary are two halves of one contract, so a walk builds only the runner snapshotted beside it, never whatever a checkout holds.",
                latest.map { "The latest install paired runner \(ShortHash.of($0.commit)) with a different binary; this one was copied in without it, or predates it." },
                "Run `simwalk install-hook` from the checkout this binary was built from, or set \(variable) to a SimWalkRunner.xcodeproj to walk with that one.",
            ].compactMap(\.self)).joined(separator: " ")
        case let .snapshotMissing(path, commit):
            "the walk runner snapshot for commit \(ShortHash.of(commit)) is not at \(path) any more — run `simwalk install-hook` from the checkout this binary was built from: it takes the snapshot again while that checkout still holds \(ShortHash.of(commit)), and if the checkout has moved on, `simwalk install-hook --repoint-runner` pairs this binary with what it holds now"
        case let .binaryUnreadable(variable):
            "cannot read this simwalk binary to tell which runner it was installed with — set \(variable) to a SimWalkRunner.xcodeproj to walk with that one"
        }
    }
}

extension RunnerProjectError: UsageFailureClassifiable {
    /// Every case is the runner's own install state — an override that does not point at a project, no snapshot paired with this binary, a paired snapshot gone from disk, or a binary this process cannot even hash — not a value the caller of `walk` supplied.
    public var usageFailureKind: UsageFailureKind {
        .runnerFailed
    }
}
