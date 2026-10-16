//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The walk runner's source tree as a packaged release ships it, beside the binary — so a `simwalk` installed by Homebrew, npm or a release tarball, with no git checkout anywhere, still has a runner to build.
///
/// **The layout is `<prefix>/bin/simwalk` and `<prefix>/share/simwalk/`**, the tree being the public source at the release commit plus two stamps: `RUNNER_COMMIT`, the commit it is, and `BINARY_SHA256`, the hash of the binary it was shipped with. This file is the one place that spells those names; everything else asks it.
///
/// **Symlinks in the executable's path are resolved first.** Homebrew links `/opt/homebrew/bin/simwalk` to `../Cellar/simwalk/<version>/bin/simwalk`, and the tree sits beside the real file, not beside the link.
///
/// **A tree is used only if it is stamped for this very binary.** The runner and the CLI are two halves of one contract (SimWalk#16), so a tree left behind by another release — a package manager that kept the old `share` directory, a binary copied in by hand — is refused rather than paired. A stamp that is missing or is not lowercase hex is refused too: there is no telling what the tree is.
public struct ShippedRunner: Equatable, Sendable {
    /// The tree's root, which holds `Runner/` and the rest of the source.
    public let root: URL
    /// The 40-hex commit the tree is.
    public let commit: String
    /// The SHA-256 of the binary the tree was shipped with.
    public let binaryHash: String

    /// Where the tree for `executable` would be — `<prefix>/share/simwalk` for `<prefix>/bin/simwalk`, with symlinks in `executable` resolved.
    public static func directory(besideExecutable executable: URL) -> URL {
        executable.resolvingSymlinksInPath().standardizedFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("simwalk", isDirectory: true)
    }

    /// The tree shipped beside `executable`, if it is stamped for the binary whose SHA-256 is `binaryHash`.
    public static func find(besideExecutable executable: URL, binaryHash: String, fileManager: FileManager = .default) throws -> ShippedRunner {
        let root = directory(besideExecutable: executable)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Absence.noDirectory(path: root.path)
        }
        let commit = try stamp(commitStamp, length: 40, in: root)
        let shipped = try stamp(binaryStamp, length: 64, in: root)
        guard shipped == binaryHash else {
            throw Absence.stampedForOtherBinary(root: root.path, shipped: shipped, this: binaryHash)
        }
        return ShippedRunner(root: root, commit: commit, binaryHash: shipped)
    }

    /// The tree's files as sorted relative paths: every regular file under the root except the two stamps, which differ per binary and so would give one commit two content hashes.
    public func files(fileManager: FileManager = .default) -> [String] {
        let stamps: Set = [Self.commitStamp, Self.binaryStamp]
        let relatives = fileManager.subpaths(atPath: root.path) ?? []
        return relatives
            .filter { !stamps.contains($0) }
            .filter { (try? root.appendingPathComponent($0).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted()
    }

    private static var commitStamp: String {
        "RUNNER_COMMIT"
    }

    private static var binaryStamp: String {
        "BINARY_SHA256"
    }

    private static func stamp(_ name: String, length: Int, in root: URL) throws -> String {
        guard let text = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) else {
            throw Absence.stampMissing(root: root.path, stamp: name)
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == length, value.allSatisfy({ $0.isASCII && ($0.isNumber || ("a" ... "f").contains($0)) }) else {
            throw Absence.stampMalformed(root: root.path, stamp: name)
        }
        return value
    }
}

public extension ShippedRunner {
    /// Why there is no usable tree, naming the path that was looked at — never a guess.
    enum Absence: Error, Equatable, CustomStringConvertible, Sendable {
        /// Nothing at the place a tree would be.
        case noDirectory(path: String)
        /// The tree is there and a stamp is not (or cannot be read).
        case stampMissing(root: String, stamp: String)
        /// A stamp is there and is not lowercase hex of the right length.
        case stampMalformed(root: String, stamp: String)
        /// The tree was shipped with a different binary.
        case stampedForOtherBinary(root: String, shipped: String, this: String)

        public var description: String {
            switch self {
            case let .noDirectory(path):
                "no \(path) beside the binary"
            case let .stampMissing(root, stamp):
                "\(root) has no readable \(stamp)"
            case let .stampMalformed(root, stamp):
                "\(root)/\(stamp) is not a lowercase hex digest"
            case let .stampedForOtherBinary(root, shipped, this):
                "\(root) was shipped with binary \(ShortHash.of(shipped)), this binary is \(ShortHash.of(this))"
            }
        }
    }
}
