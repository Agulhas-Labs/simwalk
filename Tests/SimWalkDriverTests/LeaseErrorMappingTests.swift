//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkDriver
import Testing

struct LeaseErrorMappingTests {
    private let expiry = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Each store error maps to the LeaseError case with the same values")
    func mapsEveryCase() {
        #expect(LeaseError(LeaseStoreError.storeFailed(path: "/p", reason: "r")) == .storeFailed(path: "/p", reason: "r"))
        #expect(LeaseError(LeaseStoreError.awaitingDeletion(udid: "U")) == .awaitingDeletion(udid: "U"))
        #expect(LeaseError(LeaseStoreError.held(udid: "U", holderPID: 7, expiresAt: expiry)) == .held(udid: "U", holderPID: 7, expiresAt: expiry))
        #expect(LeaseError(LeaseStoreError.unreadable(path: "/p")) == .unreadable(path: "/p"))
        #expect(LeaseError(LeaseStoreError.noSuchLease) == .noSuchLease)
        #expect(LeaseError(LeaseStoreError.expired(udid: "U", expiresAt: expiry)) == .expired(udid: "U", expiresAt: expiry))
        #expect(LeaseError(LeaseStoreError.holderExited(udid: "U", holderPID: 7)) == .holderExited(udid: "U", holderPID: 7))
    }

    @Test("mapping rethrows a store error as a LeaseError")
    func mappingRethrowsStoreError() {
        #expect(throws: LeaseError.noSuchLease) {
            try LeaseError.mapping { throw LeaseStoreError.noSuchLease }
        }
    }

    @Test("mapping passes a foreign error through untouched")
    func mappingPassesForeignError() {
        struct Foreign: Error, Equatable {}

        #expect(throws: Foreign()) {
            try LeaseError.mapping { throw Foreign() }
        }
        #expect(throws: LeaseError.noUnleasedDevice(runtime: "iOS")) {
            try LeaseError.mapping { throw LeaseError.noUnleasedDevice(runtime: "iOS") }
        }
    }

    @Test("A lease somebody holds is refused with the command that takes a device of one's own")
    func heldDescription() {
        let line = LeaseError.held(udid: "U", holderPID: 7, expiresAt: expiry).description

        #expect(line == "U is leased by pid 7 until \(LeaseError.time(expiry)) — take a device of your own (`simwalk lease acquire`), or pass that lease's token with --lease; nothing on the device was touched")
    }

    @Test("A token that holds nothing points at the list")
    func noSuchLeaseDescription() {
        #expect(LeaseError.noSuchLease.description == "no lease carries that token — it was released, or reclaimed after it expired; `simwalk lease list` shows what is held")
    }

    @Test("A lapsed clone points at prune")
    func awaitingDeletionDescription() {
        #expect(LeaseError.awaitingDeletion(udid: "U").description == "U is a clone a lease made, and that lease has lapsed or is being released, so the device is deleted rather than leased again — `simwalk prune` deletes it; take another device (`simwalk lease acquire`); nothing on the device was touched")
    }
}
