//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimulatorServices
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// Releasing a device SimWalk created removes the launchd override directory `simctl delete` leaves behind.
struct DeviceLeasingOverrideTests {
    private static var clone: String {
        "11111111-2222-3333-4444-0000000000A1"
    }

    private static var other: String {
        "11111111-2222-3333-4444-0000000000B2"
    }

    private static let start = Date(timeIntervalSince1970: 1_786_867_200)

    @Test
    func releasingACreatedDeviceRemovesItsOverrideDirectoryAndOnlyThat() throws {
        let directory = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        let overrides = DisabledServicesOverride(root: root.url)
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: Self.clone, ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SOURCE-1")
        try overrides.write(["gizmo.a"], for: Self.clone)
        try overrides.write(["gizmo.a"], for: Self.other)

        try DeviceLeasing(store: store, shell: Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: "", standardError: "") }), overrides: overrides).release(token: lease.token)

        #expect(try !FileManager.default.fileExists(atPath: overrides.directory(for: Self.clone).path))
        #expect(try overrides.labels(for: Self.other) == ["gizmo.a"])
    }

    /// A lease on a device it did not create deletes nothing, its override included.
    @Test
    func releasingALeaseOnAnExistingDeviceKeepsItsOverride() throws {
        let directory = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        let overrides = DisabledServicesOverride(root: root.url)
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: Self.other, ttl: 60, holderPID: 41, now: Self.start)
        try overrides.write(["gizmo.a"], for: Self.other)

        try DeviceLeasing(store: store, shell: Shell(script: { _, _, _ in Shell.Result(status: 0, standardOutput: "", standardError: "") }), overrides: overrides).release(token: lease.token)

        #expect(try overrides.labels(for: Self.other) == ["gizmo.a"])
    }

    /// A device already gone is what the delete wanted, and its override directory goes all the same.
    @Test
    func aDeviceAlreadyGoneStillLosesItsOverride() throws {
        let directory = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        let overrides = DisabledServicesOverride(root: root.url)
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: Self.clone, ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SOURCE-1")
        try overrides.write(["gizmo.a"], for: Self.clone)
        let shell = Shell(script: { _, _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "Invalid device: \(Self.clone)") })

        try DeviceLeasing(store: store, shell: shell, overrides: overrides).release(token: lease.token)

        #expect(try !FileManager.default.fileExists(atPath: overrides.directory(for: Self.clone).path))
    }

    /// A delete that failed leaves the device, and so its override, in place.
    @Test
    func aDeleteThatFailedKeepsTheOverride() throws {
        let directory = try TemporaryDirectory()
        let root = try TemporaryDirectory()
        let overrides = DisabledServicesOverride(root: root.url)
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        let lease = try store.acquire(udid: Self.clone, ttl: 60, holderPID: 41, now: Self.start, createdDevice: true, clonedFrom: "SOURCE-1")
        try overrides.write(["gizmo.a"], for: Self.clone)
        let shell = Shell(script: { _, _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "boom") })

        #expect(throws: LeaseError.self) {
            try DeviceLeasing(store: store, shell: shell, overrides: overrides).release(token: lease.token)
        }

        #expect(try overrides.labels(for: Self.clone) == ["gizmo.a"])
    }
}
