//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// Why a walk refused to boot a device with some of its services switched off or on.
public enum SlimWalkError: Error, Equatable, CustomStringConvertible {
    /// The device's override file exists but cannot be read, so whether services are off cannot be told.
    case overrideUnreadable(path: String, reason: String, createdByWalk: Bool)
    /// The device is booted, the walk may not reboot it, and the change to its services takes effect only at its next boot.
    case bootedInUse(udid: String, switchingOff: Bool)

    public var description: String {
        switch self {
        case let .overrideUnreadable(path, reason, createdByWalk):
            "\(path) exists but cannot be read (\(reason)), so whether this device has launchd services off cannot be told — "
                + (createdByWalk ? "remove the file, or shut the device down and walk again" : "remove the file")
        case let .bootedInUse(udid, switchingOff):
            "\(udid) is booted and may be in use; launchd reads the switch-\(switchingOff ? "off" : "on") at boot. Shut it down (xcrun simctl shutdown \(udid)) or name it with --device"
        }
    }
}

extension SlimWalkError: UsageFailureClassifiable {
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
