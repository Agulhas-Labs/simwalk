//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Where walks build the runner — `~/.simwalk/runner-builds/<key>`, one directory per snapshot and one per working tree (SimWalk#16) — and the record each directory carries of what it builds.
///
/// **A build directory's name is a hash of the project it builds, and a hash cannot be read back.** So a walk writes the project's path into the directory as it starts, rewriting it on every walk. That record is what lets a prune tell a working tree's build whose checkout is gone — a worktree removed by `git worktree remove`, which never reaches in here — from one still in use, and when any build was last walked (SimWalk#22). A build made before the record existed is attributed by the `info.plist` Xcode writes into a derived-data directory, read only as that fallback.
public struct RunnerBuilds {
    /// `~/.simwalk/runner-builds`, or a scratch directory in a test.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The machine's own build directories.
    public static func standard() -> RunnerBuilds {
        RunnerBuilds(directory: HomeDirectories.simwalk()
            .appendingPathComponent("runner-builds", isDirectory: true))
    }

    /// The build directory `source` builds into — the one place its name is made.
    public func directory(for source: RunnerSource) -> URL {
        directory.appendingPathComponent(source.buildKey, isDirectory: true)
    }

    /// Records, in the build directory `source` is about to build into, which project it builds — and, by rewriting the record, that it is being walked now.
    ///
    /// **A prune can set the directory aside between its creation and the record's write** (SimWalk#34): the directory was already there, old enough to be planned for removal, and the prune renames it away the moment before the record lands. The write then finds no directory, so it is re-created and the record written once more — into a fresh directory at the path, where the prune's deletion of the renamed one cannot reach, and the walk builds afresh.
    public func recordUse(of source: RunnerSource) throws {
        try recordUse(of: source, racing: {})
    }

    /// ``recordUse(of:)``, calling `race` between creating the directory and writing its record — the seam a test uses to be the prune that sets it aside there (SimWalk#34).
    func recordUse(of source: RunnerSource, racing race: () -> Void) throws {
        let build = directory(for: source)
        let record = try JSONEncoder().encode(Record(projectPath: source.projectPath))
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        race()
        do {
            try record.write(to: Self.recordURL(in: build), options: .atomic)
        } catch {
            try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
            try record.write(to: Self.recordURL(in: build), options: .atomic)
        }
    }

    /// The project the build directory at `build` builds, from its record or, for a build made before records were kept, from Xcode's own `info.plist`; `nil` when neither says.
    public func builtProject(at build: URL) -> String? {
        if let data = try? Data(contentsOf: Self.recordURL(in: build)),
           let record = try? JSONDecoder().decode(Record.self, from: data)
        {
            return record.projectPath
        }
        guard let data = try? Data(contentsOf: Self.xcodeInfoURL(in: build)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["WorkspacePath"] as? String
    }

    /// The files whose modification dates say when a build was last walked or built: the directory, its record, and Xcode's `info.plist`.
    public static func useMarkers(in build: URL) -> [URL] {
        [build, recordURL(in: build), xcodeInfoURL(in: build)]
    }

    private static func recordURL(in build: URL) -> URL {
        build.appendingPathComponent("simwalk-build.json")
    }

    private static func xcodeInfoURL(in build: URL) -> URL {
        build.appendingPathComponent("info.plist")
    }
}

extension RunnerBuilds {
    /// What a build directory's record holds.
    struct Record: Codable {
        let projectPath: String
    }
}
