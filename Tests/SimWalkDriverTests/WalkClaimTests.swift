//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A walk's claim on its device: present while its holder is alive and it is unreleased, and nothing else (SimWalk#128).
struct WalkClaimTests {
    private let alive: Set<Int32> = [100, 200]

    private func store(_ directory: TemporaryDirectory) -> LeaseStore {
        LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
    }

    /// A claim whose holder is alive marks its device as walked.
    @Test
    func aClaimIsHeldWhileItsHolderIsAlive() throws {
        let directory = try TemporaryDirectory()
        let leases = store(directory)

        _ = try WalkClaim.take(udid: "UDID-1", in: leases, holder: 100, isAlive: { alive.contains($0) })

        #expect(WalkClaim.walkedDevices(in: leases, isAlive: { alive.contains($0) }) == ["UDID-1"])
    }

    /// A released claim's file is gone; the device's directory stays, since removing it could take another walk's claim written meanwhile.
    @Test
    func aReleasedClaimIsGone() throws {
        let directory = try TemporaryDirectory()
        let leases = store(directory)
        let claim = try WalkClaim.take(udid: "UDID-1", in: leases, holder: 100, isAlive: { alive.contains($0) })

        claim.release()

        #expect(WalkClaim.walkedDevices(in: leases, isAlive: { alive.contains($0) }).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: claim.file.path))
        #expect(FileManager.default.fileExists(atPath: claim.file.deletingLastPathComponent().path))
    }

    /// A walk killed without releasing leaves its file behind; with its holder gone it marks nothing.
    @Test
    func aDeadHoldersClaimDoesNotCount() throws {
        let directory = try TemporaryDirectory()
        let leases = store(directory)
        _ = try WalkClaim.take(udid: "UDID-1", in: leases, holder: 100, isAlive: { alive.contains($0) })

        #expect(WalkClaim.walkedDevices(in: leases, isAlive: { _ in false }).isEmpty)
    }

    /// Several walks may be on one device: one releasing leaves the device walked by the other.
    @Test
    func releasingOneOfTwoClaimsLeavesTheDeviceWalked() throws {
        let directory = try TemporaryDirectory()
        let leases = store(directory)
        let first = try WalkClaim.take(udid: "UDID-1", in: leases, holder: 100, isAlive: { alive.contains($0) })
        _ = try WalkClaim.take(udid: "UDID-1", in: leases, holder: 200, isAlive: { alive.contains($0) })

        first.release()

        #expect(WalkClaim.walkedDevices(in: leases, isAlive: { alive.contains($0) }) == ["UDID-1"])
    }

    /// Taking a claim clears the files of holders that died without releasing theirs.
    @Test
    func takingAClaimSweepsADeadHoldersFile() throws {
        let directory = try TemporaryDirectory()
        let leases = store(directory)
        let dead = try WalkClaim.take(udid: "UDID-1", in: leases, holder: 100, isAlive: { alive.contains($0) })

        let live = try WalkClaim.take(udid: "UDID-1", in: leases, holder: 200, isAlive: { $0 == 200 })

        #expect(!FileManager.default.fileExists(atPath: dead.file.path))
        #expect(FileManager.default.fileExists(atPath: live.file.path))
    }
}
