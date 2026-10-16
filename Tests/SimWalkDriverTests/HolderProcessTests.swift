//
// Copyright © Agulhas Labs
//

@testable import SimWalkDriver
import Testing

/// When the process a lease lives as long as is probably not one that outlives the command asking.
struct HolderProcessTests {
    /// Under a wrapper the search does not know, the holder is the command's own parent, which exits with it: the warning names it and `--holder-pid`.
    @Test
    func anUnknownDirectParentIsWarnedAbout() throws {
        let warning = try #require(HolderProcess.unverifiedHolderWarning(holder: 500, parent: 500, name: "caffeinate"))

        #expect(warning.contains("pid 500 (caffeinate)"))
        #expect(warning.contains("--holder-pid"))
    }

    /// A known long-lived parent, and an ancestor further up than the parent, are not warned about.
    @Test
    func aKnownSessionProcessOrADistantAncestorIsNotWarnedAbout() {
        #expect(HolderProcess.unverifiedHolderWarning(holder: 500, parent: 500, name: "claude") == nil)
        #expect(HolderProcess.unverifiedHolderWarning(holder: 400, parent: 500, name: "caffeinate") == nil)
    }
}
