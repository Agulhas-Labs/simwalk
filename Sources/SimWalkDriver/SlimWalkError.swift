//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// Why a walk refused to boot a device with some of its services switched off or on.
public enum SlimWalkError: Error, Equatable, CustomStringConvertible {
    /// `--stock` on a device SimWalk did not create, which has services switched off that only its creator can switch back on.
    case stockOnForeignDevice(udid: String, off: Int)

    /// The device's override file exists but cannot be read, so whether services are off cannot be told.
    case overrideUnreadable(path: String, reason: String, createdByWalk: Bool)

    public var description: String {
        switch self {
        case let .stockOnForeignDevice(udid, off):
            "--stock: \(udid) has \(off) launchd services off, and SimWalk did not create it, so it cannot switch them back on — walk a device without them"
        case let .overrideUnreadable(path, reason, createdByWalk):
            "\(path) exists but cannot be read (\(reason)), so whether this device has launchd services off cannot be told — "
                + (createdByWalk ? "remove the file, or shut the device down and walk again" : "remove the file, or walk a device SimWalk creates")
        }
    }
}

extension SlimWalkError: UsageFailureClassifiable {
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
