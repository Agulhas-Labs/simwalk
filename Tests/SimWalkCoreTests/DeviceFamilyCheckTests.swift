//
// Copyright © Agulhas Labs
//

import SimWalkCore
import Testing

/// SimWalk#166: an iPhone-only app is refused on an iPad, and only what was read is refused.
struct DeviceFamilyCheckTests {
    private static var ipad: String {
        "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5"
    }

    private static var iphone: String {
        "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
    }

    private func refusal(_ families: [Int]?, on type: String?) -> DeviceFamilyCheck.Refusal? {
        DeviceFamilyCheck.refusal(bundleID: "com.example.app", families: families, deviceTypeIdentifier: type, deviceName: "iPad Pro 11-inch (M5)", udid: "UDID-1")
    }

    @Test
    func anIPhoneOnlyAppOnAnIPadIsRefusedNamingTheFamiliesAndTheDevice() throws {
        let refused = try #require(refusal([1], on: Self.ipad))

        #expect(refused.description.contains("com.example.app declares iPhone only (UIDeviceFamily [1])"))
        #expect(refused.description.contains("iPad Pro 11-inch (M5) (UDID-1) is an iPad"))
        #expect(refused.description.contains("SimWalk#166"))
    }

    @Test
    func anAppThatDeclaresIPadIsNotRefusedOnAnIPad() {
        #expect(refusal([1, 2], on: Self.ipad) == nil)
        #expect(refusal([2], on: Self.ipad) == nil)
    }

    @Test
    func anIPhoneOnlyAppOnAnIPhoneIsNotRefused() {
        #expect(refusal([1], on: Self.iphone) == nil)
    }

    @Test
    func anAbsentOrEmptyFamilyListIsNotRefused() {
        #expect(refusal(nil, on: Self.ipad) == nil)
        #expect(refusal([], on: Self.ipad) == nil)
    }

    @Test
    func anUnknownDeviceTypeIsNotRefused() {
        #expect(refusal([1], on: nil) == nil)
    }

    @Test
    func theFamilyIsReadOffTheDeviceType() {
        #expect(DeviceFamily(deviceTypeIdentifier: Self.ipad) == .ipad)
        #expect(DeviceFamily(deviceTypeIdentifier: Self.iphone) == .iphone)
        #expect(DeviceFamily(deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K") == nil)
        #expect(DeviceFamily(deviceTypeIdentifier: nil) == nil)
    }
}
