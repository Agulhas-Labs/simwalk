//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A shipped tree is the files `RUNNER_FILES` lists, each with the bytes it lists (SimWalk#138).
struct ShippedRunnerManifestTests {
    /// A listed tree installs, and the snapshot holds exactly the listed files.
    @Test
    func alistedTreeInstallsWithExactlyItsListedFiles() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)

        let installed = try store.install(shipped: shipped, binaryHash: Self.binaryHash)

        let snapshot = URL(fileURLWithPath: installed.binding.snapshot)
        let held = try FileManager.default.subpathsOfDirectory(atPath: snapshot.path)
            .filter { (try? snapshot.appendingPathComponent($0).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted()

        #expect(shipped.files() == ["Package.swift", "Runner/SimWalkRunner.xcodeproj/project.pbxproj", "SimWalk.md"])
        #expect(held == shipped.files())
    }

    /// A `.DS_Store` and a file an older release shipped, neither listed, are never snapshotted.
    @Test
    func anUnlistedFileIsNeverSnapshotted() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let stale = fixture.tree.appendingPathComponent("Sources/Old/Stale.swift")
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("// removed in this release\n".utf8).write(to: stale)
        try Data("junk".utf8).write(to: fixture.tree.appendingPathComponent(".DS_Store"))
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)

        let installed = try store.install(shipped: shipped, binaryHash: Self.binaryHash)

        let snapshot = URL(fileURLWithPath: installed.binding.snapshot)

        #expect(!shipped.files().contains(".DS_Store"))
        #expect(!FileManager.default.fileExists(atPath: snapshot.appendingPathComponent(".DS_Store").path))
        #expect(!FileManager.default.fileExists(atPath: snapshot.appendingPathComponent("Sources/Old/Stale.swift").path))
    }

    /// A file changed after the stamp was written, even after the tree was found, refuses naming the file and both hashes — and pairs nothing.
    @Test
    func aChangedFileRefusesNamingTheFileAndBothHashes() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        let listed = try #require(shipped.manifest.first { $0.path == "Package.swift" }).sha256
        try Data("// swapped\n".utf8).write(to: fixture.tree.appendingPathComponent("Package.swift"))
        let found = ShippedRunner.sha256(of: Data("// swapped\n".utf8))

        let refusal = try #require(#expect(throws: ShippedRunner.Absence.self) {
            try store.install(shipped: shipped, binaryHash: Self.binaryHash)
        })

        #expect(refusal.description.contains("Package.swift"))
        #expect(refusal.description.contains(listed))
        #expect(refusal.description.contains(found))
        #expect(refusal.description.contains("reinstall the package"))
        #expect(store.binding(forBinary: Self.binaryHash) == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: store.snapshotsDirectory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    /// A listed file that is gone refuses naming it.
    @Test
    func aMissingListedFileRefusesNamingIt() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        try FileManager.default.removeItem(at: fixture.tree.appendingPathComponent("SimWalk.md"))

        let refusal = try #require(#expect(throws: ShippedRunner.Absence.self) {
            try store.install(shipped: shipped, binaryHash: Self.binaryHash)
        })

        #expect(refusal.description.contains("SimWalk.md"))
        #expect(store.binding(forBinary: Self.binaryHash) == nil)
    }

    /// A tree with no `RUNNER_FILES` is refused as unstamped.
    @Test
    func aMissingManifestRefuses() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        try fixture.writeStamp("RUNNER_FILES", nil)

        let refusal = #expect(throws: ShippedRunner.Absence.self) {
            try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        }

        #expect(refusal?.description.contains("no readable RUNNER_FILES") == true)
        #expect(refusal?.description.hasSuffix("reinstall the package") == true)
    }

    /// An old tree left beside a new binary — stamped for another binary, with no `RUNNER_FILES` — is refused for the real cause.
    @Test
    func aTreeForAnotherBinaryWithNoManifestRefusesAsThatBinarys() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: String(repeating: "b", count: 64))
        try fixture.writeStamp("RUNNER_FILES", nil)

        let refusal = #expect(throws: ShippedRunner.Absence.self) {
            try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        }

        guard case .stampedForOtherBinary = refusal else {
            Issue.record("expected stampedForOtherBinary, got \(String(describing: refusal))")
            return
        }
    }

    /// A line that is not `<64 hex>  <relative path>` — a short hash, an escaped name, an absolute path, a `..` or `.` component — refuses.
    @Test(arguments: [
        "abc  Package.swift\n",
        "\\\(String(repeating: "a", count: 64))  odd\\nname\n",
        "\(String(repeating: "a", count: 64))  /etc/passwd\n",
        "\(String(repeating: "a", count: 64))  ../outside.swift\n",
        "\(String(repeating: "a", count: 64))  Sources/../../outside.swift\n",
        "\(String(repeating: "a", count: 64))  ./Package.swift\n",
        "\(String(repeating: "a", count: 64))  Sources/./Runner.swift\n",
        "\(String(repeating: "a", count: 64)) Package.swift\n",
        "",
    ])
    func aMalformedLineRefuses(manifest: String) throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        try fixture.writeStamp("RUNNER_FILES", manifest)

        let refusal = #expect(throws: ShippedRunner.Absence.self) {
            try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        }

        #expect(refusal?.description.contains("RUNNER_FILES line") == true)
    }

    /// A path listed twice — a second line that could give it another hash — refuses naming the path and the line that repeats it (SimWalk#141 item 3).
    @Test
    func aPathListedTwiceRefusesNamingThePathAndTheLine() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let manifest = try String(contentsOf: fixture.tree.appendingPathComponent("RUNNER_FILES"), encoding: .utf8)
        try fixture.writeStamp("RUNNER_FILES", manifest + "\(String(repeating: "a", count: 64))  Package.swift\n")

        let refusal = #expect(throws: ShippedRunner.Absence.self) {
            try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        }

        #expect(refusal?.description.hasSuffix("/RUNNER_FILES lists Package.swift twice (line 4); reinstall the package") == true)
    }

    /// A tree changed after release, beside a snapshot that already holds the same changed bytes, refuses rather than pairing that snapshot: reuse is judged against the listed hashes, not the tree (SimWalk#141 item 3).
    @Test
    func aChangedTreeRefusesEvenWhenASnapshotAlreadyHoldsItsBytes() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        let listed = try #require(shipped.hashes["Package.swift"])
        try Data("// swapped\n".utf8).write(to: fixture.tree.appendingPathComponent("Package.swift"))
        let found = ShippedRunner.sha256(of: Data("// swapped\n".utf8))
        try Self.snapshot(shipped, in: store)

        let refusal = #expect(throws: ShippedRunner.Absence.self) {
            try store.install(shipped: shipped, binaryHash: Self.binaryHash)
        }

        #expect(refusal == .fileChanged(root: shipped.root.path, path: "Package.swift", listed: listed, found: found))
        #expect(store.binding(forBinary: Self.binaryHash) == nil)
    }

    /// An unchanged tree beside a snapshot that holds its bytes reuses that snapshot rather than copying again: the listed hashes and the snapshot's bytes hash alike.
    @Test
    func anUnchangedTreeReusesASnapshotThatHoldsItsBytes() throws {
        let directory = try TemporaryDirectory()
        let fixture = try ShippedTreeFixture(in: directory, commit: Self.commit, stampedFor: Self.binaryHash)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let shipped = try ShippedRunner.find(besideExecutable: fixture.binary, binaryHash: Self.binaryHash)
        let snapshot = try Self.snapshot(shipped, in: store)
        let before = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.systemFileNumber] as? Int

        let installed = try store.install(shipped: shipped, binaryHash: Self.binaryHash)

        let after = try FileManager.default.attributesOfItem(atPath: snapshot.path)[.systemFileNumber] as? Int

        #expect(installed.outcome == .reusedSnapshot)
        #expect(before != nil)
        #expect(after == before)
    }

    /// Copies the tree's listed files, as they are on disk now, to the snapshot for its commit — what an earlier install of that tree left.
    @discardableResult
    private static func snapshot(_ shipped: ShippedRunner, in store: RunnerStore) throws -> URL {
        let snapshot = store.snapshotsDirectory.appendingPathComponent(shipped.commit, isDirectory: true)
        for file in shipped.files() {
            let destination = snapshot.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: shipped.root.appendingPathComponent(file), to: destination)
        }
        return snapshot
    }

    private static var commit: String {
        String(repeating: "c0", count: 20)
    }

    private static var binaryHash: String {
        String(repeating: "b1", count: 32)
    }
}
