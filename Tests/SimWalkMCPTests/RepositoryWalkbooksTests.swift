//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import SimWalkTestSupport
import Testing

/// A working directory reached through a symlink still finds the walkbooks its physical location is served by — the walk up to `.git` and the `../` prefix it hands back both have to agree with where the kernel actually resolves that path, not with the symlinked spelling the session happens to stand at (SimWalk#37 item 1).
struct RepositoryWalkbooksTests {
    @Test
    func aworkingDirectoryReachedThroughASymlinkStillFindsTheWalkbook() throws {
        let scratch = try TemporaryDirectory()
        let root = scratch.url.appendingPathComponent("real-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let folder = root.appendingPathComponent("Docs/Walkbooks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(Self.walkbook.utf8).write(to: folder.appendingPathComponent("x.json"))
        let deep = root.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        // A symlink two levels shallower than `deep` actually sits: lexically walking up from it never
        // reaches `root`'s `.git` at all, which is the failure this test pins.
        let shortcut = scratch.url.appendingPathComponent("shortcut", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: deep)

        #expect(RepositoryWalkbooks.loaded(from: shortcut.path) == [RepositoryWalkbooks.Found(path: "../../Docs/Walkbooks/x.json", screens: 2, states: 3)])
    }

    /// A `*.json` that does not load as a walkbook is not "here" — the status line asks the same question the hand-drive hook offers by, not merely whether a file with that suffix exists (SimWalk#37 item 4).
    @Test
    func afileThatDoesNotLoadIsNotAWalkbook() throws {
        let scratch = try TemporaryDirectory()
        let root = scratch.url.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let folder = root.appendingPathComponent("Docs/Walkbooks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a walkbook".utf8).write(to: folder.appendingPathComponent("junk.json"))

        #expect(RepositoryWalkbooks.candidates(from: root.path) == ["Docs/Walkbooks/junk.json"])
        #expect(RepositoryWalkbooks.loaded(from: root.path).isEmpty)
        #expect(RepositoryWalkbooks.exist(from: root.path) == false)
    }

    static var walkbook: String {
        """
        {"name": "x", "appBundleID": "com.example.app", "screens": [
          {"id": "home", "route": [{"tab": {"label": "Home"}}], "states": [{"theme": "light"}, {"theme": "dark"}]},
          {"id": "settings", "route": [{"tab": {"label": "Settings"}}], "states": [{"theme": "light"}]}
        ]}
        """
    }
}
