//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// Why a walk refused to boot a device with some of its services switched off or on.
public enum SlimWalkError: Error, Equatable, CustomStringConvertible {
    /// `--stock` on a device SimWalk did not create, which has services switched off that only its creator can switch back on.
    case stockOnForeignDevice(udid: String, off: Int)

    public var description: String {
        switch self {
        case let .stockOnForeignDevice(udid, off):
            "--stock: \(udid) has \(off) launchd services off, and SimWalk did not create it, so it cannot switch them back on — walk a device without them"
        }
    }
}

extension SlimWalkError: UsageFailureClassifiable {
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
