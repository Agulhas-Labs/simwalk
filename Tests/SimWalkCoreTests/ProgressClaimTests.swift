//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// Which files a run alive beside another of its session writes (`Docs/SIMWALK-PROGRESS.md` §1, SimWalk#83).
struct ProgressClaimTests {
    /// The first run keeps the session's own files, a second alive beside it takes the next slot, and a slot given up is the next one taken.
    @Test
    func aRunAliveBesideAnotherTakesTheNextSlotAndAFreedSlotIsReused() throws {
        let directory = try TemporaryDirectory()
        let first = ProgressClaim.take(session: "s", in: directory.url)
        var second: ProgressClaim? = ProgressClaim.take(session: "s", in: directory.url)
        let secondURLs = second.map { [$0.progressURL.lastPathComponent, $0.resultURL.lastPathComponent] }
        second = nil
        let third = ProgressClaim.take(session: "s", in: directory.url)

        #expect(first.progressURL.lastPathComponent == "s.json")
        #expect(first.resultURL.lastPathComponent == "s.result.json")
        #expect(secondURLs == ["s.2.json", "s.2.result.json"])
        #expect(third.progressURL.lastPathComponent == "s.2.json")
    }

    /// A shared claim no child was spawned holding — a session start refused or failed before its spawn — is unlocked when it goes away, even while another copy of its descriptor is open, as a thread mid-spawn holds one until its exec (SimWalk#71, SimWalk#83).
    @Test
    func aSharedClaimNeverHandedOverIsUnlockedDespiteAnotherCopyOfItsDescriptor() throws {
        let directory = try TemporaryDirectory()
        var claim: ProgressClaim? = ProgressClaim.take(session: "s", in: directory.url, sharedWithChild: true)
        let copy = try dup(#require(claim?.descriptorForChild))
        defer { close(copy) }
        claim = nil

        let next = ProgressClaim.take(session: "s", in: directory.url)

        #expect(next.progressURL.lastPathComponent == "s.json")
    }

    /// A shared claim a child holds stays the child's when the claim goes away: the copy of its descriptor keeps the lock (SimWalk#83).
    @Test
    func aSharedClaimHandedOverStaysHeldByTheCopy() throws {
        let directory = try TemporaryDirectory()
        var claim: ProgressClaim? = ProgressClaim.take(session: "s", in: directory.url, sharedWithChild: true)
        let copy = try dup(#require(claim?.descriptorForChild))
        defer { close(copy) }
        claim?.markHandedOver()
        claim = nil

        let next = ProgressClaim.take(session: "s", in: directory.url)

        #expect(next.progressURL.lastPathComponent == "s.2.json")
    }

    /// A lock that cannot be taken at all leaves the run on the session's own files, unclaimed, as before: progress never fails a walk.
    @Test
    func aDirectoryThatCannotHoldALockLeavesTheSessionsOwnFiles() throws {
        let directory = try TemporaryDirectory()
        let blocker = directory.url.appendingPathComponent("file")
        try Data().write(to: blocker)

        let claim = ProgressClaim.take(session: "s", in: blocker)

        #expect(claim.progressURL == ProgressLocation.progressURL(session: "s", in: blocker))
    }
}
