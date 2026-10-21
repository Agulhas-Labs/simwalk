//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A packaged binary — no checkout anywhere — installs and walks the runner source shipped beside it (`ShippedRunner`).
///
/// The packaged case is exercised by passing `nil` for the checkout, which is all `-DSIMWALK_PACKAGED` changes; the flag itself is held by building with it and looking for the build machine's path in the binary.
struct RunnerProjectShippedTests {
    /// A stamped tree installs under its commit, paired with the binary's hash, holding the tree's files and not its stamps.
    @Test
    func astampedTreeIsSnapshottedUnderItsCommitAndPairedWithTheBinary() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)

        let installed = try store.install(shipped: shipped, binaryHash: Self.binaryHash)

        #expect(installed.outcome == .snapshotted)
        #expect(installed.binding.commit == Self.commit)
        #expect(installed.binding.snapshot == store.snapshotsDirectory.appendingPathComponent(Self.commit).path)
        #expect(installed.binding.checkout == shipped.root.path)
        #expect(store.binding(forBinary: Self.binaryHash) == installed.binding)
        let snapshot = URL(fileURLWithPath: installed.binding.snapshot)
        #expect(FileManager.default.fileExists(atPath: installed.binding.projectPath))
        #expect(FileManager.default.fileExists(atPath: snapshot.appendingPathComponent("Package.swift").path))
        #expect(!FileManager.default.fileExists(atPath: snapshot.appendingPathComponent("RUNNER_COMMIT").path))
        #expect(!FileManager.default.fileExists(atPath: snapshot.appendingPathComponent("BINARY_SHA256").path))
    }

    /// Homebrew reaches the binary through a link in another directory; the tree is beside the real file.
    @Test
    func abinaryReachedThroughASymlinkFindsTheTreeBesideItsRealLocation() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let link = try fixture.link(in: directory)

        let shipped = try ShippedRunner.find(besideExecutable: link, binaryHash: Self.binaryHash)

        #expect(shipped.root.resolvingSymlinksInPath().path == fixture.tree.resolvingSymlinksInPath().path)
        #expect(shipped.commit == Self.commit)
    }

    /// The first walk after an upgrade has no binding; it installs the shipped tree and walks it, and the next walk reuses it.
    @Test
    func awalkWithNoBindingInstallsTheShippedTreeAndReusesItAfter() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))

        let first = try Self.resolve(fixture, store: store)
        let second = try Self.resolve(fixture, store: store)

        #expect(first.origin == .installed)
        #expect(first.commit == Self.commit)
        #expect(first.projectPath.hasPrefix(store.snapshotsDirectory.path))
        #expect(FileManager.default.fileExists(atPath: first.projectPath))
        #expect(second == first)
        #expect(store.binding(forBinary: Self.binaryHash)?.commit == Self.commit)
    }

    /// A tree shipped with another binary is not this binary's runner: the walk refuses, naming the path and both hashes.
    @Test
    func atreeStampedForAnotherBinaryIsRefusedByAWalk() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.otherHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))

        let thrown = try #require(#expect(throws: RunnerProjectError.self) {
            try Self.resolve(fixture, store: store)
        })

        let text = thrown.description

        #expect(text.contains(ShippedRunner.directory(besideExecutable: fixture.binary).path))
        #expect(text.contains("shipped with binary \(String(Self.otherHash.prefix(8)))"))
        #expect(text.contains("this binary is \(String(Self.binaryHash.prefix(8)))"))
        #expect(store.binding(forBinary: Self.binaryHash) == nil)
    }

    /// A stamp that is missing, or is not lowercase hex of the right length, says which.
    @Test
    func amissingOrMalformedStampIsNamed() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)

        try fixture.writeStamp("RUNNER_COMMIT", "ABC123\n")
        let malformed = #expect(throws: ShippedRunner.Absence.self) {
            try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        }
        try fixture.writeStamp("RUNNER_COMMIT", nil)
        let missing = #expect(throws: ShippedRunner.Absence.self) {
            try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        }

        #expect(malformed?.description.contains("RUNNER_COMMIT is not a lowercase hex digest") == true)
        #expect(missing?.description.contains("no readable RUNNER_COMMIT") == true)
    }

    /// Two first walks after an upgrade race to install the same tree: one that checked for a snapshot before the other moved its own into place must not replace it, since the other may already be building it.
    @Test
    func aSnapshotThatMatchesAppearingDuringACopyIsKeptNotReplaced() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        let winner = try store.install(shipped: shipped, binaryHash: Self.binaryHash)
        let snapshot = URL(fileURLWithPath: winner.binding.snapshot)
        let before = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.systemFileNumber] as? Int

        // The loser passed its reuse check before the winner's snapshot existed, and reaches the copy now.
        try store.copy(shipped.files(), from: shipped.root, to: snapshot, content: winner.binding.contentHash)

        let after = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.systemFileNumber] as? Int
        #expect(before != nil)
        #expect(after == before)
        #expect(FileManager.default.fileExists(atPath: winner.binding.projectPath))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.snapshotsDirectory.path)
        #expect(leftovers == [Self.commit])
    }

    /// A snapshot whose bytes do not match is still replaced — the keep is for a match only.
    @Test
    func aSnapshotThatDoesNotMatchIsStillReplaced() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        let installed = try store.install(shipped: shipped, binaryHash: Self.binaryHash)
        let snapshot = URL(fileURLWithPath: installed.binding.snapshot)
        let package = snapshot.appendingPathComponent("Package.swift")
        try Data("// tampered\n".utf8).write(to: package)

        try store.copy(shipped.files(), from: shipped.root, to: snapshot, content: installed.binding.contentHash)

        #expect(try String(contentsOf: package, encoding: .utf8) == "// package\n")
    }

    /// Two first walks both find a stale snapshot: the one that replaces it second waits for the first's replace to finish, then finds the fresh snapshot matching and keeps it rather than moving it away (SimWalk#139 item 2).
    ///
    /// This pins the property itself — the check and the replace hold one lock — since the race sits between two adjacent statements no stress run can be relied on to hit.
    @Test
    func aCopyThatFoundAStaleSnapshotWaitsOutAnotherReplaceAndKeepsItsSnapshot() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let runner = directory.url.appendingPathComponent("runner")
        let store = RunnerStore(directory: runner)
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        let content = try store.install(shipped: shipped, binaryHash: Self.binaryHash).binding.contentHash
        let snapshot = store.snapshotsDirectory.appendingPathComponent(Self.commit, isDirectory: true)
        try Data("// tampered\n".utf8).write(to: snapshot.appendingPathComponent("Package.swift"))
        let lock = open(store.snapshotsDirectory.path, O_RDONLY | O_DIRECTORY)
        #expect(lock >= 0)
        #expect(flock(lock, LOCK_EX) == 0)
        defer { close(lock) }

        let finished = DispatchSemaphore(value: 0)
        let failure = Failure()
        let (files, root) = (shipped.files(), shipped.root)
        DispatchQueue.global().async {
            do {
                try RunnerStore(directory: runner).copy(files, from: root, to: snapshot, content: content)
            } catch {
                failure.record(error)
            }
            finished.signal()
        }
        #expect(finished.wait(timeout: .now() + 0.4) == .timedOut, "the copy replaced the snapshot while another replace held the lock")
        // The other replacer, holding the lock, moves the stale snapshot away and its own fresh one into place.
        let fresh = directory.url.appendingPathComponent("fresh", isDirectory: true)
        try FileManager.default.copyItem(at: snapshot, to: fresh)
        try Data("// package\n".utf8).write(to: fresh.appendingPathComponent("Package.swift"))
        try FileManager.default.removeItem(at: snapshot)
        try FileManager.default.moveItem(at: fresh, to: snapshot)
        let placed = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.systemFileNumber] as? Int
        #expect(flock(lock, LOCK_UN) == 0)
        #expect(finished.wait(timeout: .now() + 10) == .success)

        let kept = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.systemFileNumber] as? Int
        #expect(failure.error == nil)
        #expect(placed != nil)
        #expect(kept == placed)
    }

    /// With neither a shipped tree nor a checkout, the refusal names the shipped place it looked.
    @Test
    func awalkWithNoTreeAndNoCheckoutNamesWhereItLooked() throws {
        let directory = try TemporaryDirectory()
        let binary = directory.url.appendingPathComponent("prefix/bin/simwalk")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: binary)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))

        let thrown = try #require(#expect(throws: RunnerProjectError.self) {
            try RunnerProject.resolve(environment: [:], executable: binary, binaryHash: { Self.binaryHash }, checkout: nil, store: store, run: Self.run)
        })

        #expect(thrown.description.contains("no \(ShippedRunner.directory(besideExecutable: binary).path) beside the binary"))
        #expect(thrown.description.contains("reinstall the package"))
        #expect(thrown.description.contains("<prefix>/share/simwalk"))
        #expect(!thrown.description.contains("from the checkout this binary was built from"))
    }

    private static func resolve(_ fixture: ShippedTreeFixture, store: RunnerStore) throws -> RunnerSource {
        try RunnerProject.resolve(environment: [:], executable: fixture.binary, binaryHash: { binaryHash }, checkout: nil, store: store, run: run)
    }

    private static var run: (String, [String]) throws -> Shell.Result {
        { _, _ in Shell.Result(status: 128, standardOutput: "", standardError: "no git here") }
    }

    private static var commit: String {
        String(repeating: "c0", count: 20)
    }

    private static var binaryHash: String {
        String(repeating: "1a", count: 32)
    }

    private static var otherHash: String {
        String(repeating: "5e", count: 32)
    }
}

private extension RunnerProjectShippedTests {
    /// The error a copy on another thread threw, if any.
    final class Failure: @unchecked Sendable {
        private let lock = NSLock()
        private var thrown: (any Error)?

        func record(_ error: any Error) {
            lock.lock()
            defer { lock.unlock() }
            thrown = error
        }

        var error: (any Error)? {
            lock.lock()
            defer { lock.unlock() }
            return thrown
        }
    }
}
