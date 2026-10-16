//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import Testing

/// What a caller is told before a build that starts from nothing (SimWalk#98).
struct RunnerColdBuildNoteTests {
    /// An empty build directory is a cold build: the line names the first 8 characters of the commit and says it takes minutes.
    @Test
    func anEmptyBuildDirectoryAnswersTheColdBuildLine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: directory.path)

        #expect(runner.coldBuildNote(commit: "0123456789abcdef") == "building the runner (01234567) — a first build takes several minutes")
    }

    /// A build directory holding an `.xctestrun` under `Build/Products` is warm, so there is nothing to say.
    @Test
    func aBuildDirectoryHoldingBuiltProductsAnswersNil() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("simwalk-tests-\(UUID().uuidString)", isDirectory: true)
        let products = directory.appendingPathComponent("Build/Products", isDirectory: true)
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: products.appendingPathComponent("x.xctestrun"))
        let runner = RunnerInvocation(projectPath: "/runner/SimWalkRunner.xcodeproj", derivedDataPath: directory.path)

        #expect(runner.coldBuildNote(commit: "0123456789abcdef") == nil)
    }
}
