//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import Testing

/// SimWalk#166: the family list is read from the installed bundle's `Info.plist`, and only a readable list can refuse.
struct AppDeviceFamiliesTests {
    private let ipad = Simulator(udid: "UDID-1", name: "iPad Pro 11-inch (M5)", osVersion: "27.0", isBooted: true, deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5")

    private func withApp(plist: [String: Any]?, _ body: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AppDeviceFamiliesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        if let plist {
            try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: dir.appendingPathComponent("Info.plist"))
        }
        try body(dir.path)
    }

    @Test
    func theFamilyListIsReadFromTheBundlesInfoPlist() throws {
        try withApp(plist: ["UIDeviceFamily": [1]]) { path in
            #expect(AppDeviceFamilies.read(appAt: path) == [1])
        }
    }

    @Test
    func aSingleFamilyNumberReadsAsAListOfOne() throws {
        try withApp(plist: ["UIDeviceFamily": 1]) { path in
            #expect(AppDeviceFamilies.read(appAt: path) == [1])
        }
    }

    @Test
    func aMissingPlistOrKeyReadsAsNil() throws {
        try withApp(plist: nil) { #expect(AppDeviceFamilies.read(appAt: $0) == nil) }
        try withApp(plist: ["CFBundleIdentifier": "x"]) { #expect(AppDeviceFamilies.read(appAt: $0) == nil) }
    }

    @Test
    func anIPhoneOnlyBundleOnAnIPadThrowsTheRefusal() throws {
        try withApp(plist: ["UIDeviceFamily": [1]]) { path in
            #expect(throws: SimulatorError.self) { try AppDeviceFamilies.require(bundleID: "com.example.app", installedAt: path, on: ipad) }
        }
    }

    @Test
    func aUniversalOrUnreadBundleOnAnIPadIsNotRefused() throws {
        try withApp(plist: ["UIDeviceFamily": [1, 2]]) { try AppDeviceFamilies.require(bundleID: "com.example.app", installedAt: $0, on: ipad) }
        try withApp(plist: nil) { try AppDeviceFamilies.require(bundleID: "com.example.app", installedAt: $0, on: ipad) }
    }
}
