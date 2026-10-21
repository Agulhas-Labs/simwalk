//
// Copyright © Agulhas Labs
//

import Foundation

/// Why a `walk --parallel` could not merge its shard bundles into one, each saying what to look at.
public enum ShardBundleMergeError: Error, Equatable, CustomStringConvertible {
    /// The shards were not walked against one build, so their screens do not describe one app.
    case buildsDiffer(builds: [String])
    /// A shard's manifest holds no record of a screen the plan gave it.
    case screenMissing(shard: Int, screenID: String)

    public var description: String {
        switch self {
        case let .buildsDiffer(builds):
            "the shards were walked against different builds of the app (\(builds.joined(separator: ", "))), so their screens cannot be merged into one walk; walk again"
        case let .screenMissing(shard, screenID):
            "shard \(shard)'s bundle has no record of screen \(screenID), which the plan gave it, so the walk is not whole; its bundle is left in place"
        }
    }
}
