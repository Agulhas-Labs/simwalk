//
// Copyright © Agulhas Labs
//

import Foundation

/// How a `walk --parallel` divides a plan's screens between its devices: each screen goes to one shard with all its states.
///
/// **In walkbook order, each to the shard with the fewest states so far, ties to the lowest index**: deterministic, so the same walkbook and count always shard the same way, and balanced by capture count rather than by screen count, because a state is what costs a walk its time. More devices than screens is clamped to the screen count, and ``requested`` keeps what was asked so the answer can say so.
public struct ShardPlan: Equatable, Sendable {
    /// The device count the caller asked for.
    public let requested: Int
    /// The screen ids each shard walks, in walkbook order within each; shard 0 first.
    public let shards: [[String]]

    /// Shards `book`'s screens across at most `devices` devices.
    public init(_ book: Walkbook, devices: Int) {
        requested = devices
        let count = max(1, min(devices, book.screens.count))
        var shards = Array(repeating: [String](), count: count)
        var states = Array(repeating: 0, count: count)
        for screen in book.screens {
            // `min(by:)` keeps the first of equal elements, so a tie goes to the lowest index.
            let lightest = states.indices.min { states[$0] < states[$1] } ?? 0
            shards[lightest].append(screen.id)
            states[lightest] += max(1, screen.states.count)
        }
        self.shards = shards
    }

    /// Whether fewer devices are used than were asked for, because the plan has fewer screens.
    public var clamped: Bool {
        shards.count < requested
    }
}
