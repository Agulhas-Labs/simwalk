//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation
import SimWalkCore

/// The walk runner's sources, snapshotted at install time into a directory no checkout owns, and paired with the binary that was installed beside them (SimWalk#16).
///
/// **The runner and the CLI are two halves of one versioned contract, so they have to come from the same commit.** An installed `simwalk` used to build its runner from whatever the checkout it was compiled in held at the moment of the walk: a half-made edit there failed every walk on the machine, and a finished one produced a format-4 runner that the installed format-3 CLI refused to read. Both halves now come from one place — `install-hook` copies the checkout's files into `snapshots/<commit>` and records, under the installed binary's own SHA-256, which snapshot it goes with. A walk builds that snapshot and nothing else, whatever the checkout is doing.
///
/// **Keyed by the binary, not by "the current install".** A Claude Code session starts `simwalk mcp` once and keeps it running, so a deploy replaces the file under a process that goes on running the old code. That process looks up the snapshot for the binary it was launched from, and finds its own — still on disk, because a prune keeps the most recent installs and anything walked in the last day (`RunnerPrune`) — rather than the new install's, which is exactly the skew the pairing exists to prevent.
///
/// Still built from source, as Brief §7.4 decided: the snapshot is the checkout's own files, and `xcodebuild` compiles them on the first walk that needs them.
public struct RunnerStore {
    /// `~/.simwalk/runner`, or a scratch directory in a test.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The machine's own store.
    public static func standard() -> RunnerStore {
        RunnerStore(directory: HomeDirectories.simwalk()
            .appendingPathComponent("runner", isDirectory: true))
    }

    /// The runner paired with the binary whose SHA-256 is `binaryHash`, or `nil` when none was installed for it.
    public func binding(forBinary binaryHash: String) -> Binding? {
        guard let data = try? Data(contentsOf: bindingURL(forBinary: binaryHash)) else { return nil }
        return try? JSONDecoder().decode(Binding.self, from: data)
    }

    /// The binding written most recently, for a refusal that has to say what *is* installed when this binary has nothing.
    public func latestBinding() -> Binding? {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: bindingsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files
            .filter { $0.pathExtension == "json" }
            .max { modified($0) < modified($1) }
        return newest.flatMap { try? JSONDecoder().decode(Binding.self, from: Data(contentsOf: $0)) }
    }

    /// Snapshots `checkout` and pairs the snapshot with `binaryHash`, answering what it did.
    ///
    /// The snapshot is the checkout's files as they are on disk — tracked and untracked alike, ignored ones left out — because the binary being installed was built from the working tree, not from `HEAD`. A tree `GitWorkingTree` calls clean is named by its commit; any other by its commit and a hash of what is on disk, so two different dirty trees never share a snapshot and the manifest never claims a commit that does not describe the runner.
    ///
    /// **A binding is written once per binary** (the SimWalk#16 review). A binary's runner is the one it was installed with, and re-running the install from a checkout that has moved on since — another branch, uncommitted edits — would otherwise re-pair a binary built from one commit with a runner from another, the skew this store exists to prevent. So a binary already paired with a different runner keeps it, and the answer says so; `repoint` replaces it, for the one case where that is really wanted.
    ///
    /// **A snapshot is reused only if its bytes are still what its name says.** The binding stores the content hash, and a snapshot already on disk is hashed again before it is paired — one that does not match (written by a build that misjudged the tree as clean, or edited since) is replaced rather than made permanent.
    ///
    /// Written to a scratch directory and moved into place, so a walk never finds half a snapshot.
    public func install(
        checkout: URL,
        binaryHash: String,
        repoint: Bool = false,
        run: (String, [String]) throws -> Shell.Result
    ) throws -> Installation {
        let head = try GitWorkingTree.head(of: checkout, run: run)
        let files = try GitWorkingTree.files(of: checkout, run: run)
        let dirty = try GitWorkingTree.isDirty(checkout, run: run)
        let content = Self.contentHash(of: files, in: checkout)
        let commit = dirty ? "\(head)-dirty.\(ShortHash.of(content))" : head

        return try pair(commit: commit, content: content, files: files, from: checkout, binaryHash: binaryHash, repoint: repoint)
    }

    /// Pairs `binaryHash` with the runner source a packaged release shipped beside the binary (`ShippedRunner`), answering what it did.
    ///
    /// The same pairing as a checkout's, minus git: the files are the ones the release listed, each checked against its listed hash as it is copied, the commit is the one the release stamped, and the tree is never dirty — it is a release, as built. The binding's `checkout` records the shipped root, so a reader tracing a runner back finds where it came from.
    public func install(shipped: ShippedRunner, binaryHash: String, repoint: Bool = false) throws -> Installation {
        let files = shipped.files()
        let content = Self.contentHash(of: files, in: shipped.root)
        return try pair(commit: shipped.commit, content: content, files: files, from: shipped.root, binaryHash: binaryHash, repoint: repoint, listed: shipped.hashes)
    }

    /// What both installs share once they know the tree's commit, files and content hash: keep an existing pairing unless asked, reuse a snapshot whose bytes still match, else copy, then write the binding.
    private func pair(commit: String, content: String, files: [String], from source: URL, binaryHash: String, repoint: Bool, listed: [String: String] = [:]) throws -> Installation {
        let existing = binding(forBinary: binaryHash)
        if let existing, existing.commit != commit || existing.contentHash != content, !repoint {
            return Installation(binding: existing, outcome: .kept(checkoutCommit: commit))
        }

        let snapshot = snapshotsDirectory.appendingPathComponent(commit, isDirectory: true)
        let reused = FileManager.default.fileExists(atPath: snapshot.path) && Self.contentHash(ofSnapshotAt: snapshot) == content
        if !reused {
            try copy(files, from: source, to: snapshot, content: content, listed: listed)
        }
        let binding = Binding(commit: commit, contentHash: content, snapshot: snapshot.path, checkout: source.path)
        // A binding that already names this runner, whose snapshot had gone, has just been snapshotted again —
        // which is how a missing snapshot is repaired: re-run the install from the checkout that still holds it.
        let outcome: Installation.Outcome = if let existing, existing != binding {
            .repointed(from: existing)
        } else if existing != nil {
            reused ? .unchanged : .snapshotted
        } else {
            reused ? .reusedSnapshot : .snapshotted
        }
        try FileManager.default.createDirectory(at: bindingsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(binding).write(to: bindingURL(forBinary: binaryHash), options: .atomic)
        return Installation(binding: binding, outcome: outcome)
    }

    /// Where snapshots live, one directory per commit.
    public var snapshotsDirectory: URL {
        directory.appendingPathComponent("snapshots", isDirectory: true)
    }

    /// Where bindings live, one file per binary's SHA-256.
    var bindingsDirectory: URL {
        directory.appendingPathComponent("binaries", isDirectory: true)
    }

    private func bindingURL(forBinary binaryHash: String) -> URL {
        bindingsDirectory.appendingPathComponent(binaryHash).appendingPathExtension("json")
    }

    /// Copies `files` into `snapshot`, replacing whatever is there — a snapshot whose bytes did not match its name — by a move rather than an edit in place.
    ///
    /// **A snapshot already there whose bytes hash to `content` is kept, and the copy just made is discarded.** The reuse check in `pair` happens before the copy, and the copy takes time: a second walk (or install) of the same tree can have moved its own snapshot into place in between, and may already be building it. Replacing that one would delete a directory out from under its `xcodebuild`.
    ///
    /// **A file with a hash in `listed` is checked as it is copied**: the bytes read are the bytes hashed and the bytes written, so a tree swapped after it was found cannot reach the snapshot, and a refusal removes the partial copy before anything is paired.
    func copy(_ files: [String], from checkout: URL, to snapshot: URL, content: String, listed: [String: String] = [:]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        let partial = snapshotsDirectory.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: partial) }
        for file in files {
            let destination = partial.appendingPathComponent(file)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let expected = listed[file] else {
                try manager.copyItem(at: checkout.appendingPathComponent(file), to: destination)
                continue
            }
            guard let data = try? Data(contentsOf: checkout.appendingPathComponent(file)) else {
                throw ShippedRunner.Absence.fileMissing(root: checkout.path, path: file)
            }
            let found = ShippedRunner.sha256(of: data)
            guard found == expected else {
                throw ShippedRunner.Absence.fileChanged(root: checkout.path, path: file, listed: expected, found: found)
            }
            try data.write(to: destination)
            if let permissions = try? manager.attributesOfItem(atPath: checkout.appendingPathComponent(file).path)[.posixPermissions] {
                try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
            }
        }
        if manager.fileExists(atPath: snapshot.path) {
            if Self.contentHash(ofSnapshotAt: snapshot) == content {
                return
            }
            let stale = snapshotsDirectory.appendingPathComponent(".stale-\(UUID().uuidString)", isDirectory: true)
            try manager.moveItem(at: snapshot, to: stale)
            try? manager.removeItem(at: stale)
        }
        do {
            try manager.moveItem(at: partial, to: snapshot)
        } catch where manager.fileExists(atPath: snapshot.path) {
            // Another install of the same content got there first; its snapshot is this one.
        }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// One hash over every file's path and bytes, in path order — what names a dirty tree's snapshot, and what a snapshot is checked against before it is reused.
    private static func contentHash(of files: [String], in root: URL) -> String {
        var digest = SHA256()
        for file in files {
            digest.update(data: Data(file.utf8) + Data([0]))
            digest.update(data: (try? Data(contentsOf: root.appendingPathComponent(file))) ?? Data())
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The same hash over what a snapshot directory holds now.
    private static func contentHash(ofSnapshotAt snapshot: URL) -> String {
        let manager = FileManager.default
        var files: [String] = []
        for relative in manager.subpaths(atPath: snapshot.path) ?? [] {
            let url = snapshot.appendingPathComponent(relative)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory != true || values?.isSymbolicLink == true {
                files.append(relative)
            }
        }
        return contentHash(of: files.sorted(), in: snapshot)
    }
}

public extension RunnerStore {
    /// Which snapshot a binary goes with, the commit that names it, and the hash of what it holds.
    struct Binding: Codable, Equatable, Sendable {
        /// The commit the snapshot was taken at — `<sha>` for a clean tree, `<sha>-dirty.<content hash>` for one with changes on disk.
        public let commit: String
        /// The SHA-256 over the snapshot's paths and bytes — what a snapshot on disk is checked against before it is reused, and what a re-install is compared with.
        public let contentHash: String
        /// The snapshot's directory.
        public let snapshot: String
        /// The checkout it was taken from, for a reader tracing a runner back to its source.
        public let checkout: String

        public init(commit: String, contentHash: String, snapshot: String, checkout: String) {
            self.commit = commit
            self.contentHash = contentHash
            self.snapshot = snapshot
            self.checkout = checkout
        }

        /// The runner's Xcode project inside the snapshot.
        public var projectPath: String {
            RunnerProject.project(under: snapshot)
        }
    }

    /// What an install did, and the binding the binary is left with.
    struct Installation: Equatable, Sendable {
        public let binding: Binding
        public let outcome: Outcome
    }
}

public extension RunnerStore.Installation {
    /// The five things an install can have done about a binary's runner.
    enum Outcome: Equatable, Sendable {
        /// A new snapshot was copied and paired.
        case snapshotted
        /// A snapshot of this content was already on disk and was paired.
        case reusedSnapshot
        /// The binary was already paired with this very runner.
        case unchanged
        /// The binary was already paired with a different runner, which it keeps; the payload is what the checkout holds now.
        case kept(checkoutCommit: String)
        /// Asked to, the binary was re-paired; the payload is the runner it had.
        case repointed(from: RunnerStore.Binding)
    }
}
