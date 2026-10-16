//
// Copyright © Agulhas Labs
//

import Foundation

/// A packaged install laid out on disk — `<prefix>/bin/simwalk` and `<prefix>/share/simwalk/` with its two stamps — for the tests of what a binary with no checkout does.
public struct ShippedTreeFixture {
    public let prefix: URL
    public let commit: String
    public let stampedFor: String

    /// Writes the layout under `directory`: the binary, the runner project, and the stamps, the binary stamp naming `stampedFor`.
    public init(in directory: TemporaryDirectory, commit: String, stampedFor: String) throws {
        prefix = directory.url.appendingPathComponent("prefix", isDirectory: true)
        self.commit = commit
        self.stampedFor = stampedFor
        let manager = FileManager.default
        try manager.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: binary)
        let project = tree.appendingPathComponent("Runner/SimWalkRunner.xcodeproj", isDirectory: true)
        try manager.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("// the shipped runner\n".utf8).write(to: project.appendingPathComponent("project.pbxproj"))
        try Data("// package\n".utf8).write(to: tree.appendingPathComponent("Package.swift"))
        try Data("# guide\n".utf8).write(to: tree.appendingPathComponent("SimWalk.md"))
        try Data("\(commit)\n".utf8).write(to: tree.appendingPathComponent("RUNNER_COMMIT"))
        try Data("\(stampedFor)\n".utf8).write(to: tree.appendingPathComponent("BINARY_SHA256"))
    }

    public var binary: URL {
        prefix.appendingPathComponent("bin/simwalk")
    }

    public var tree: URL {
        prefix.appendingPathComponent("share/simwalk", isDirectory: true)
    }

    /// Replaces one stamp's text, or removes the stamp when `text` is `nil`.
    public func writeStamp(_ name: String, _ text: String?) throws {
        let url = tree.appendingPathComponent(name)
        if let text {
            try Data(text.utf8).write(to: url)
        } else {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// A symlink to the binary in a directory of its own, as a package manager's bin directory holds one.
    public func link(in directory: TemporaryDirectory) throws -> URL {
        let bin = directory.url.appendingPathComponent("linked/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appendingPathComponent("simwalk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)
        return link
    }
}
