//
// Copyright © Agulhas Labs
//

/// Whether an app can run natively on a device, read off the families its `Info.plist` declares (SimWalk#166).
///
/// An iPhone-only app on an iPad simulator runs scaled inside the iPad screen in iPhone compatibility mode, so the frames a walk binds its steps by are not the app's own: a route fails as unreachable, or acts on the wrong element. The walk is refused up front instead, with that reason.
///
/// Refuses only what was read: a family list that is absent or unreadable, or a device type that is unknown, is not a refusal.
public struct DeviceFamilyCheck {
    /// `UIDeviceFamily`'s value for an iPhone (and iPod touch).
    public static let iPhoneFamily = 1
    /// `UIDeviceFamily`'s value for an iPad.
    public static let iPadFamily = 2

    /// The refusal for walking this app on this device, or nil when it may run.
    ///
    /// - Parameters:
    ///   - families: the app's `UIDeviceFamily`, nil when absent or unreadable.
    ///   - deviceTypeIdentifier: the simulator's device type, such as `com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5`; nil when unknown.
    public static func refusal(bundleID: String, families: [Int]?, deviceTypeIdentifier: String?, deviceName: String, udid: String) -> Refusal? {
        guard let families, !families.isEmpty, DeviceFamily(deviceTypeIdentifier: deviceTypeIdentifier) == .ipad, !families.contains(iPadFamily) else {
            return nil
        }
        return Refusal(bundleID: bundleID, families: families, deviceName: deviceName, udid: udid)
    }
}

public extension DeviceFamilyCheck {
    /// The refusal of an iPhone-only app on an iPad.
    struct Refusal: Equatable, Sendable, CustomStringConvertible {
        public let bundleID: String
        public let families: [Int]
        public let deviceName: String
        public let udid: String

        public init(bundleID: String, families: [Int], deviceName: String, udid: String) {
            self.bundleID = bundleID
            self.families = families
            self.deviceName = deviceName
            self.udid = udid
        }

        public var description: String {
            "\(bundleID) declares iPhone only (UIDeviceFamily \(families)) and \(deviceName) (\(udid)) is an iPad, where it runs scaled in iPhone compatibility mode: the frames a walk binds its steps by are not the app's there, so its routes would fail or act on the wrong element — walk it on an iPhone simulator (SimWalk#166)"
        }
    }
}
