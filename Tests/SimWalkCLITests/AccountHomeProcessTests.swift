//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// The account home, held to the built binary under `CFFIXED_USER_HOME`: the lease store is the account's, never the scratch home the variable names.
///
/// **Driven as a process, deliberately.** `homeDirectoryForCurrentUser` ignores `HOME` but follows `CFFIXED_USER_HOME`, which it reads on every call, so only a process that starts with the variable set can tell `getpwuid` from it; an in-process test runs with the variable unset and passes either way. `Shell` strips `GIT_*` from the child's environment.
struct AccountHomeProcessTests {
    /// `lease list` under a scratch `CFFIXED_USER_HOME` and `HOME` names the account's lease store and creates nothing under the scratch home.
    @Test
    func leaseListNamesTheAccountsStoreNotTheScratchHome() throws {
        let scratch = try TemporaryDirectory()
        let home = scratch.url.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let account = try #require(getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) })
        // The usage log and session tag pinned, so a run never writes a record into the real log or a live session's count.
        let environment = ["HOME": home.path, "CFFIXED_USER_HOME": home.path, UsageLog.overrideVariable: scratch.url.appendingPathComponent("usage.jsonl").path, "CLAUDE_CODE_SESSION_ID": ""]
        let binary = try UsageLogOverrideTests.binary()

        let listed = try Shell().run(binary.path, ["lease", "list"], environment: environment)

        #expect(listed.standardOutput.hasPrefix("leases: \(account)/.simwalk/leases"))
        #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".simwalk").appendingPathComponent("leases").path))
    }
}
