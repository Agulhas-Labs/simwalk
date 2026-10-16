//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Where the progress and result files go (`Docs/SIMWALK-PROGRESS.md` §1): per session under the usage log's directory, and never anywhere a session id could point.
struct ProgressLocationTests {
    private let directory = URL(fileURLWithPath: "/scratch/simwalk", isDirectory: true)

    @Test
    func aSessionIdNamesItsOwnFilesUnderProgress() {
        let session = "0f6e2a9c-3b1d-4e7a-9c2f-1a2b3c4d5e6f"

        #expect(ProgressLocation.progressURL(session: session, in: directory).path == "/scratch/simwalk/progress/\(session).json")
        #expect(ProgressLocation.resultURL(session: session, in: directory).path == "/scratch/simwalk/progress/\(session).result.json")
    }

    @Test
    func noSessionIsTheDefaultSession() {
        #expect(ProgressLocation.progressURL(session: nil, in: directory).path == "/scratch/simwalk/progress/default.json")
        #expect(ProgressLocation.resultURL(session: "", in: directory).path == "/scratch/simwalk/progress/default.result.json")
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
