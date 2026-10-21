//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a parallel walk could not get the extra devices its shards run on.
public enum ShardDevicePoolError: Error, Equatable, CustomStringConvertible {
    /// The pool was released, by the walk's cancel, while it was still acquiring, so it took nothing more.
    case released
    /// Shard 0 was booted, so it could not be cloned, and the device list names no device type or runtime for it to create a device like it.
    case deviceTypeUnknown(udid: String)

    public var description: String {
        switch self {
        case .released:
            "the walk was cancelled while its extra devices were being acquired; every device it had acquired was given back"
        case let .deviceTypeUnknown(udid):
            "`simctl list devices` names no device type or runtime for \(udid), so no device like it can be created for another shard, and it is booted, so it cannot be cloned — shut it down to have it cloned, or walk without --parallel"
        }
    }
}
