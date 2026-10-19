//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A `GIT_*` environment inherited from a git hook must not steer any `git` SimWalk or its tests spawn.
///
/// A suite once ran from a pre-push hook, where git exports `GIT_DIR`; the fixtures' `git` children inherited it and committed to the pushing worktree instead of their temporary directories. The decoy here stands for that worktree.
///
/// Serialized because it edits the process environment, which every test shares.
@Suite(.serialized)
struct GitEnvironmentScrubTests {
    @Test
    func anInheritedGitEnvironmentNeverReachesTheDecoyRepository() throws {
        let directory = try TemporaryDirectory()
        let decoyDirectory = try TemporaryDirectory()
        let decoy = try GitCheckoutFixture(in: decoyDirectory)
        let decoyGitDirectory = decoy.url.appendingPathComponent(".git")
        let before = try Self.contents(of: decoyGitDirectory)
        let decoyHead = try decoy.head()

        let names = ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"]
        let saved = names.map { (name: $0, value: getenv($0).map { String(cString: $0) }) }
        defer {
            for entry in saved {
                if let value = entry.value {
                    setenv(entry.name, value, 1)
                } else {
                    unsetenv(entry.name)
                }
            }
        }
        setenv("GIT_DIR", decoyGitDirectory.path, 1)
        setenv("GIT_WORK_TREE", decoy.url.path, 1)
        setenv("GIT_INDEX_FILE", decoyGitDirectory.appendingPathComponent("index").path, 1)

        // The RunnerProject snapshot path, through the fixture and the product's `Shell`.
        let checkout = try GitCheckoutFixture(in: directory, files: ["Runner/SimWalkRunner.xcodeproj/project.pbxproj": "// another runner\n"])
        try checkout.write("// the next edit\n", to: "Runner/SimWalkRunner.xcodeproj/project.pbxproj")
        try checkout.commit("the next commit")
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let run: (String, [String]) throws -> Shell.Result = { try Shell().run($0, $1) }
        _ = try store.install(checkout: checkout.url, binaryHash: String(repeating: "3c", count: 32), run: run)
        let bare = directory.url.appendingPathComponent("bare.git", isDirectory: true)
        try GitCheckoutFixture.initBare(at: bare, in: directory)

        #expect(try Self.contents(of: decoyGitDirectory) == before)
        #expect(try decoy.head() == decoyHead)
        #expect(try checkout.head() != decoyHead)
        #expect(try GitWorkingTree.head(of: checkout.url, run: run) == checkout.head())
        #expect(FileManager.default.fileExists(atPath: bare.appendingPathComponent("HEAD").path))
        #expect(GitEnvironment.scrubbed(["GIT_DIR": "x", "GIT_WORK_TREE": "w", "GIT_SSH_COMMAND": "y", "PATH": "/bin"]) == ["GIT_SSH_COMMAND": "y", "PATH": "/bin"])
    }

    @Test
    func aFixtureRepositoryOutsideTheTestsDirectoryIsRefused() throws {
        let directory = try TemporaryDirectory()
        let elsewhere = try TemporaryDirectory()

        #expect(throws: GitCheckoutFixture.Failure.self) {
            try GitCheckoutFixture.initBare(at: elsewhere.url.appendingPathComponent("x.git"), in: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.url.appendingPathComponent("x.git").path))
    }

    /// Every file under `directory` that decides a repository's identity — `HEAD`, `config`, refs, the index — as bytes by relative path.
    private static func contents(of directory: URL) throws -> [String: Data] {
        var found: [String: Data] = [:]
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = files?.nextObject() as? URL {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(file.path.dropFirst(directory.path.count))
            guard relative == "/HEAD" || relative == "/config" || relative == "/index" || relative.hasPrefix("/refs/") else { continue }
            found[relative] = try Data(contentsOf: file)
        }
        return found
    }
}
