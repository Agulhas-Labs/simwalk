//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// A `walk --parallel` that failed outside any one shard — before its shards ran, or merging their bundles — carrying what the shards handed back and every device the walk could not give back, which the bare error would leave unsaid.
struct ParallelWalkFailure: Error, CustomStringConvertible, UsageFailureClassifiable {
    let underlying: Error
    /// Each shard that walked, `<device> (<screens>):`, followed by its handback and setup notes; empty when no shard ran.
    let notes: [String]
    let unreleased: [ShardDevicePool.Unreleased]

    /// The underlying error's own kind, or a walk's default.
    var usageFailureKind: UsageFailureKind {
        UsageFailureKind.of(underlying) ?? .runnerFailed
    }

    var description: String {
        ([String(describing: underlying)] + notes + unreleased.map { "⚠ not given back: \($0)" }).joined(separator: "\n")
    }
}
