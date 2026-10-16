//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation
import SimWalkCore

/// The runner a walk is about to build: where its project is, which commit it is, and how it was found.
public struct RunnerSource: Equatable, Sendable {
    public let projectPath: String
    /// The commit it was built from, as recorded in a bundle's manifest; `nil` when that cannot be told.
    public let commit: String?
    public let origin: Origin

    public init(projectPath: String, commit: String?, origin: Origin) {
        self.projectPath = projectPath
        self.commit = commit
        self.origin = origin
    }

    /// The build directory's name, so two sources never share build products: a snapshot's commit and path, and a working tree's path alone.
    ///
    /// The one shared `~/.simwalk/runner-build` let a `SIMWALK_RUNNER_PROJECT` walk and a default one, or two checkouts, overwrite each other's products mid-walk (SimWalk#16). **The path is what separates sources**, and it is enough on its own for a working tree: keying one by its commit too made every commit walked from a development or override build a cold build and another ~250 MB, where `xcodebuild`'s own incremental build is exactly what a tree that moves wants (the SimWalk#16 review). A snapshot never moves, and carries its commit in the name so a reader of `runner-builds/` can tell which is which.
    public var buildKey: String {
        let path = SHA256.hash(data: Data(URL(fileURLWithPath: projectPath).standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let prefix = switch origin {
        case .installed: commit.map(ShortHash.of) ?? "snapshot"
        case .override, .checkout: "tree"
        }
        return "\(prefix)-\(ShortHash.of(path))"
    }
}

public extension RunnerSource {
    /// How a runner was found.
    enum Origin: Equatable, Sendable {
        /// Named by `SIMWALK_RUNNER_PROJECT`.
        case override
        /// The working tree of a development build that lives inside it.
        case checkout
        /// The snapshot `install-hook` paired with this binary.
        case installed
    }
}
