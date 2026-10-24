//
// Copyright © Agulhas Labs
//

/// The device family a simulator belongs to, read off its device type identifier (SimWalk#166).
public enum DeviceFamily: String, CaseIterable, Sendable {
    case iphone
    case ipad

    /// The family a device type names, such as `com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5`; nil when the identifier is absent or names neither an iPhone nor an iPad.
    public init?(deviceTypeIdentifier: String?) {
        guard let deviceTypeIdentifier else { return nil }
        if deviceTypeIdentifier.contains("iPad") {
            self = .ipad
        } else if deviceTypeIdentifier.contains("iPhone") {
            self = .iphone
        } else {
            return nil
        }
    }
}
