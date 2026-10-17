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

    /// A line that is not `<64 hex>  <relative path>` — a short hash, an escaped name, an absolute path, a `..` component — refuses.
    @Test(arguments: [
        "abc  Package.swift\n",
        "\\\(String(repeating: "a", count: 64))  odd\\nname\n",
        "\(String(repeating: "a", count: 64))  /etc/passwd\n",
        "\(String(repeating: "a", count: 64))  ../outside.swift\n",
        "\(String(repeating: "a", count: 64))  Sources/../../outside.swift\n",
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

    private static var commit: String {
        String(repeating: "c0", count: 20)
    }

    private static var binaryHash: String {
        String(repeating: "b1", count: 32)
    }
}
