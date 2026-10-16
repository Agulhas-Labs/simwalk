//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A process's identity is the binary it was launched from, not whatever sits at that path later (SimWalk#16).
struct LaunchedBinaryTests {
    /// A deploy removes the file and copies a new one to the same path under a running MCP server; the identity it took at launch still names the binary it is running, so it keeps finding its own runner.
    @Test
    func anidentityIsTheBytesAtLaunchNotTheFileThatReplacedThem() throws {
        let directory = try TemporaryDirectory()
        let binary = directory.url.appendingPathComponent("simwalk")
        try Data("the binary that was launched".utf8).write(to: binary)
        let launched = LaunchedBinary.Identity(url: binary)
        let original = try #require(launched.hash)

        try FileManager.default.removeItem(at: binary)
        try Data("the binary a deploy copied in".utf8).write(to: binary)

        #expect(launched.hash == original)
        #expect(LaunchedBinary.Identity(url: binary).hash != original)
        #expect(RunnerProject.hash(ofExecutableAt: directory.url.appendingPathComponent("never")) == nil)
    }

    /// This process's own identity is taken once: asking again answers the same, and it names the executable actually running.
    @Test
    func thelaunchedIdentityIsTakenOnceAndNamesTheRunningExecutable() {
        LaunchedBinary.capture()
        let first = LaunchedBinary.launched

        LaunchedBinary.capture()

        #expect(LaunchedBinary.launched == first)
        #expect(first.hash == first.url.flatMap(RunnerProject.hash(ofExecutableAt:)))
        #expect(first.hash != nil)
    }
}
