//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation
import SimWalkCore

/// The walk runner's source tree as a packaged release ships it, beside the binary — so a `simwalk` installed by Homebrew or a release tarball, with no git checkout anywhere, still has a runner to build.
///
/// **The layout is `<prefix>/bin/simwalk` and `<prefix>/share/simwalk/`**, the tree being the public source at the release commit plus three stamps: `RUNNER_COMMIT`, the commit it is, `RUNNER_FILES`, the `shasum -a 256` of every other file in the tree, and `BINARY_SHA256`, the hash of the binary it was shipped with. This file is the one place that spells those names; everything else asks it.
///
/// **Symlinks in the executable's path are resolved first.** Homebrew links `/opt/homebrew/bin/simwalk` to `../Cellar/simwalk/<version>/bin/simwalk`, and the tree sits beside the real file, not beside the link.
///
/// **A tree is used only if it is stamped for this very binary.** The runner and the CLI are two halves of one contract (SimWalk#16), so a tree left behind by another release — a package manager that kept the old `share` directory, a binary copied in by hand — is refused rather than paired. A stamp that is missing or is not lowercase hex is refused too: there is no telling what the tree is.
///
/// **The tree's files are the ones `RUNNER_FILES` lists, and each is checked against its hash as it is copied.** A tarball unpacked over an older release leaves the old release's removed files behind, and a file manager leaves `.DS_Store`; neither is listed, so neither is ever snapshotted. A listed file that is missing or whose bytes differ refuses, since a runner that is not the one that was released must not be paired with this binary.
public struct ShippedRunner: Equatable, Sendable {
    /// The tree's root, which holds `Runner/` and the rest of the source.
    public let root: URL
    /// The 40-hex commit the tree is.
    public let commit: String
    /// The SHA-256 of the binary the tree was shipped with.
    public let binaryHash: String
    /// The files the release listed, in the order it listed them, each with the SHA-256 of its bytes.
    public let manifest: [Entry]

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
        // Last, so an old tree beside a new binary is refused as the other binary's, not as lacking a manifest.
        let manifest = try Self.manifest(in: root)
        return ShippedRunner(root: root, commit: commit, binaryHash: shipped, manifest: manifest)
    }

    /// The tree's files as sorted relative paths: exactly those `RUNNER_FILES` lists, so the stamps, which differ per binary and would give one commit two content hashes, and anything left in the directory by something else, are not among them.
    public func files() -> [String] {
        manifest.map(\.path).sorted()
    }

    /// The listed hash for each file, by path.
    var hashes: [String: String] {
        Dictionary(manifest.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
    }

    /// The SHA-256 of `data` as lowercase hex.
    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Reads and checks `RUNNER_FILES`: one `<64 hex>  <path>` line per file, the paths relative to the root.
    private static func manifest(in root: URL) throws -> [Entry] {
        guard let text = try? String(contentsOf: root.appendingPathComponent(filesStamp), encoding: .utf8) else {
            throw Absence.stampMissing(root: root.path, stamp: filesStamp)
        }
        var entries: [Entry] = []
        var listed: Set<String> = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard let entry = Entry(line: String(line)) else {
                throw Absence.manifestMalformed(root: root.path, line: index + 1)
            }
            guard listed.insert(entry.path).inserted else {
                throw Absence.manifestDuplicate(root: root.path, path: entry.path, line: index + 1)
            }
            entries.append(entry)
        }
        guard !entries.isEmpty else {
            throw Absence.manifestMalformed(root: root.path, line: 1)
        }
        return entries
    }

    private static var filesStamp: String {
        "RUNNER_FILES"
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
        /// A `RUNNER_FILES` line is not `<64 hex>  <relative path>`.
        case manifestMalformed(root: String, line: Int)
        /// `RUNNER_FILES` lists a path a second time, at `line` — one path, one hash, or the listing is not the release's.
        case manifestDuplicate(root: String, path: String, line: Int)
        /// A file `RUNNER_FILES` lists is not in the tree.
        case fileMissing(root: String, path: String)
        /// A file's bytes are not the ones `RUNNER_FILES` lists.
        case fileChanged(root: String, path: String, listed: String, found: String)

        public var description: String {
            switch self {
            case let .noDirectory(path):
                "no \(path) beside the binary"
            case let .stampMissing(root, stamp):
                "\(root) has no readable \(stamp); reinstall the package"
            case let .stampMalformed(root, stamp):
                "\(root)/\(stamp) is not a lowercase hex digest"
            case let .stampedForOtherBinary(root, shipped, this):
                "\(root) was shipped with binary \(ShortHash.of(shipped)), this binary is \(ShortHash.of(this))"
            case let .manifestMalformed(root, line):
                "\(root)/RUNNER_FILES line \(line) is not '<sha256>  <relative path>'; reinstall the package"
            case let .manifestDuplicate(root, path, line):
                "\(root)/RUNNER_FILES lists \(path) twice (line \(line)); reinstall the package"
            case let .fileMissing(root, path):
                "\(root) lists \(path) in RUNNER_FILES and it is not there; reinstall the package"
            case let .fileChanged(root, path, listed, found):
                "\(root)/\(path) is \(found) but RUNNER_FILES lists \(listed); reinstall the package"
            }
        }
    }
}

public extension ShippedRunner {
    /// One line of `RUNNER_FILES`.
    struct Entry: Equatable, Sendable {
        /// The path relative to the tree's root.
        public let path: String
        /// The SHA-256 of the file's bytes, lowercase hex.
        public let sha256: String

        /// Parses `<64 hex>  <path>`, refusing a path that is absolute, starts with a backslash (`shasum`'s escape for an odd name) or has a `..`, `.` or empty component — a `.` would list the file under a name its snapshot never reports, so reuse would never match.
        init?(line: String) {
            guard line.count > 66, line.dropFirst(64).hasPrefix("  ") else {
                return nil
            }
            let hash = String(line.prefix(64))
            let path = String(line.dropFirst(66))
            guard hash.allSatisfy({ $0.isASCII && ($0.isNumber || ("a" ... "f").contains($0)) }),
                  !path.hasPrefix("/"), !path.hasPrefix("\\"),
                  !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
            else {
                return nil
            }
            self.path = path
            sha256 = hash
        }
    }
}
