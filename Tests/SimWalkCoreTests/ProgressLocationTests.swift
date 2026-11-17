//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// Where the progress and result files go (`Docs/SIMWALK-PROGRESS.md` §1): per session under the usage log's directory, and never anywhere a session id could point.
struct ProgressLocationTests {
    private let directory = URL(fileURLWithPath: "/scratch/simwalk", isDirectory: true)

    @Test
    func aSessionIdNamesItsOwnFilesUnderProgress() {
        let session = "0f6e2a9c-3b1d-4e7a-9c2f-1a2b3c4d5e6f"

        #expect(ProgressLocation.progressURL(session: session, in: directory).path == "/scratch/simwalk/progress/\(session).json")
        #expect(ProgressLocation.resultURL(session: session, pid: 9, startedAt: Date(timeIntervalSince1970: 2), in: directory).path == "/scratch/simwalk/progress/\(session)@9-2000.result.json")
    }

    /// A walk that writes its result clears the result files more than a week old beside it, and touches nothing else (SimWalk#262).
    @Test
    func pruningRemovesResultFilesOlderThanTheAgeAndNothingElse() throws {
        let scratch = try TemporaryDirectory()
        let folder = scratch.url
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day: TimeInterval = 24 * 3600
        func touch(_ name: String, daysOld: Double) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-daysOld * day)], ofItemAtPath: url.path)
            return url
        }
        let old = try touch("x.result.json", daysOld: 8)
        let recent = try touch("y.result.json", daysOld: 1)
        let progress = try touch("x.json", daysOld: 8)
        let written = folder.appendingPathComponent("z.result.json")

        ProgressLocation.pruneResults(beside: written, now: now)

        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(FileManager.default.fileExists(atPath: progress.path))
    }

    @Test
    func noSessionIsTheDefaultSession() {
        #expect(ProgressLocation.progressURL(session: nil, in: directory).path == "/scratch/simwalk/progress/default.json")
        #expect(ProgressLocation.resultURL(session: "", pid: 9, startedAt: Date(timeIntervalSince1970: 2), in: directory).path == "/scratch/simwalk/progress/default@9-2000.result.json")
    }

    @Test(arguments: ["../escape", "a/b", "dot.ted", " spaced", "café", "a\u{0}b"])
    func aSessionThatCouldNameAPathIsTheDefaultSession(session: String) {
        #expect(ProgressLocation.fileStem(session) == "default")
    }

    @Test
    func lettersDigitsUnderscoresAndHyphensAreKept() {
        #expect(ProgressLocation.fileStem("Run_42-b") == "Run_42-b")
    }
}
