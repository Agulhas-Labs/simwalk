//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkDriver

/// A throwaway git checkout holding a stand-in for the runner's project, committed — what `install-hook` snapshots the runner from.
///
/// Real `git`, in a scratch directory, with every piece of the machine's own configuration that could make a commit behave differently switched off: signing, hooks, and the author identity a fresh machine does not have.
public struct GitCheckoutFixture {
    public let url: URL

    /// Makes a checkout under `directory` holding `files` (path to contents), and commits them.
    public init(in directory: TemporaryDirectory, files: [String: String] = GitCheckoutFixture.runnerFiles) throws {
        url = directory.url.appendingPathComponent("checkout", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Self.requireInside(directory, url)
        try git("init", "-q")
        for (path, contents) in files {
            try write(contents, to: path)
        }
        try commit("the runner")
    }

    /// The runner's project file, at the path a snapshot is looked up by.
    public static var runnerFiles: [String: String] {
        ["Runner/SimWalkRunner.xcodeproj/project.pbxproj": "// the runner, as committed\n"]
    }

    /// Writes `contents` at `path` inside the checkout, creating directories as needed.
    public func write(_ contents: String, to path: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
    }

    /// Stages everything and commits it.
    public func commit(_ message: String) throws {
        try git("add", "-A")
        try git("commit", "-q", "-m", message)
    }

    /// `HEAD`'s full SHA.
    public func head() throws -> String {
        try git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs `git` in the checkout with the fixture's configuration, answering what it printed.
    @discardableResult
    public func git(_ arguments: String...) throws -> String {
        try Self.run([
            "-C", url.path,
            "-c", "user.name=SimWalk Tests",
            "-c", "user.email=tests@simwalk.invalid",
            "-c", "commit.gpgsign=false",
            "-c", "core.hooksPath=/dev/null",
        ] + arguments)
    }

    /// Makes a bare repository at `path` (inside `directory`) and answers nothing; the same scrubbed `git` as the checkout's.
    public static func initBare(at path: URL, in directory: TemporaryDirectory) throws {
        try requireInside(directory, path)
        try run(["init", "-q", "--bare", path.path])
    }

    /// Refuses a repository that would be made outside the test's own temporary directory — where a stray `git` would write into somebody's real one.
    public static func requireInside(_ directory: TemporaryDirectory, _ path: URL) throws {
        let root = directory.url.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let target = path.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard target.hasPrefix(root) else {
            throw Failure(arguments: ["refused: \(path.path) is outside \(directory.url.path)"], status: -1)
        }
    }

    /// `git` with every `GIT_*` variable of the test process's environment removed.
    @discardableResult
    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = GitEnvironment.scrubbed()
        let output = Pipe()
        process.standardOutput = output
        // Nowhere that can fill (SimWalk#31): a pipe nobody reads blocks a `git` with more than a buffer's worth to say, while this blocks on stdout.
        process.standardError = FileHandle.nullDevice
        // End-of-file, not the test process's stdin — `ShellTests` briefly puts a pipe of its own there, and
        // since SimWalk#21 un-serialized `RunnerProjectTests` these fixtures can spawn during that window.
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(arguments: arguments, status: process.terminationStatus)
        }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

public extension GitCheckoutFixture {
    /// A `git` call the fixture needed and did not get.
    struct Failure: Error, CustomStringConvertible {
        public let arguments: [String]
        public let status: Int32

        public var description: String {
            "git \(arguments.joined(separator: " ")) exited \(status)"
        }
    }
}
