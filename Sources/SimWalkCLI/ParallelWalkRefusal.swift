//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// Why a `walk --parallel` produced no bundle: the shard that failed first, what became of the others, and any device not given back.
struct ParallelWalkRefusal: Error, CustomStringConvertible, UsageFailureClassifiable {
    /// The failed shard's device as `<name> <udid8>`, its screens, and the failure's own text.
    let device: String
    let screens: [String]
    let cause: String
    /// Whether that failure was the walk's own stop ending the shard — an interruption's, since a shard's own failure is what stops the others — so the line says it was stopped rather than that it failed.
    var causeIsStop = false
    /// Whether the run was interrupted (a SIGINT or SIGTERM), which the refusal says first: every shard was stopped by it.
    var interrupted = false
    /// One line per other shard by what happened to it — `finished: `, `stopped: ` or `failed: <device> (<screens>)` with its cause — each followed by its handback and setup notes.
    let others: [String]
    /// What the shard pool could not give back.
    let unreleased: [ShardDevicePool.Unreleased]
    let usageFailureKind: UsageFailureKind

    var description: String {
        let head = "\(device) (\(screens.joined(separator: ", "))) \(causeIsStop ? "was stopped" : "failed"): \(cause)"
        return ((interrupted ? ["the walk was interrupted, so every shard was stopped"] : []) + [head] + others + unreleased.map { "⚠ not given back: \($0)" }).joined(separator: "\n")
    }
}

extension ParallelWalkRefusal {
    /// An extra device whose installed app hashes differently from shard 0's, so its captures would not be of the build the bundle names.
    struct BuildDiffers: Error, CustomStringConvertible {
        let udid: String
        let expected: String
        let found: String

        var description: String {
            "the app installed on \(udid) is \(AppBuildIdentity.printed(found)), not shard 0's \(AppBuildIdentity.printed(expected)) — nothing was walked on it"
        }
    }
}
