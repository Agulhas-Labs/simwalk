//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What `lease release` says it did to the device, for each way a release can end (SimWalk#249).
struct LeaseReleaseCommandTests {
    /// A clone's release says the clone was deleted.
    @Test
    func acloneIsSaidToBeDeleted() throws {
        let answer = try Self.release(createdDevice: true)

        #expect(answer.text.contains("released DEVICE-1 and deleted the device it cloned (simctl shutdown, simctl delete)"))
    }

    /// A device the lease found shut down, and `simctl` shut down, is said to be shut down as it was found.
    @Test
    func adeviceFoundShutDownIsSaidToBeShutDown() throws {
        let answer = try Self.release(foundShutDown: true)

        #expect(answer.text.contains("released DEVICE-1 and shut the device down, as the lease found it (simctl shutdown)"))
    }

    /// A device `simctl` answered was already shut down is not said to be shut down by the release.
    @Test
    func adeviceAlreadyShutDownIsSaidToBeAlreadyShutDown() throws {
        let answer = try Self.release(foundShutDown: true, simctl: "Unable to shutdown device in current state: Shutdown")

        #expect(answer.text.contains("released DEVICE-1; the device was already shut down, as the lease found it"))
        #expect(!answer.text.contains("shut the device down"))
    }

    /// A device the lease found shut down that no longer exists is said to be gone.
    @Test
    func adeviceGoneIsSaidToBeGone() throws {
        let answer = try Self.release(foundShutDown: true, simctl: "Invalid device: DEVICE-1")

        #expect(answer.text.contains("released DEVICE-1; the device the lease found shut down no longer exists"))
    }

    /// A device the lease found booted is said to be left as it is.
    @Test
    func adeviceFoundBootedIsSaidToBeLeftAsItIs() throws {
        let answer = try Self.release()

        #expect(answer.text.contains("released DEVICE-1; the device was not the lease's to shut down and is left as it is"))
    }

    /// Releases a lease on `DEVICE-1` through the command, `simctl` answering every call with success, or failing with `simctl` on stderr.
    private static func release(createdDevice: Bool = false, foundShutDown: Bool = false, simctl failure: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) throws -> Answer {
        let directory = try TemporaryDirectory()
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: "DEVICE-1", ttl: 60, holderPID: 41, now: Date(), createdDevice: createdDevice, foundShutDown: foundShutDown)
        let shell = Shell { _, _, _ in
            Shell.Result(status: failure == nil ? 0 : 1, standardOutput: "", standardError: failure.map { "An error was encountered processing the command (code=405):\n\($0)\n" } ?? "")
        }
        let answer = try LeaseReleaseCommand.parse([lease.token]).answer(leasing: DeviceLeasing(store: store, shell: shell))
        #expect(store.all().isEmpty, sourceLocation: sourceLocation)
        return answer
    }
}
