//
// Copyright © Agulhas Labs
//

import Foundation

/// Where the time of a `walk --parallel` went, per shard, read from one record rather than rebuilt from the runners' own lines.
///
/// Every offset is in milliseconds from the walk's start on the walk's own monotonic clock, so each is at most the walk's `totalMs`. The same value is the result's `timings.parallel` and the usage log's `walk.parallel` line.
public struct ParallelTimings: Codable, Equatable, Sendable {
    /// One entry per shard, in shard order.
    public var shards: [ShardTiming]
    /// How long merging the shards' bundles took; `nil` when the walk ended before it.
    public var mergeMs: Int?

    public init(shards: [ShardTiming], mergeMs: Int? = nil) {
        self.shards = shards
        self.mergeMs = mergeMs
    }

    /// These timings as they stood at `milliseconds`: every mark later than it is left out (`nil`), so a line ending there holds no mark after its own end (SimWalk#189).
    ///
    /// Absent means "had not happened by then", which is what a runner an interruption stopped has for its end. A later mark is dropped, never capped to `milliseconds`, which would record a time nobody measured. A mark at `milliseconds` is kept.
    ///
    /// The shards' marks only: `mergeMs` is a duration, not an offset, so whether the merge ended by then is the recorder's to judge, which knows where it began.
    public func through(_ milliseconds: Int) -> ParallelTimings {
        func kept(_ mark: Int?) -> Int? {
            mark.flatMap { $0 <= milliseconds ? $0 : nil }
        }
        var trimmed = self
        for index in trimmed.shards.indices {
            trimmed.shards[index].readyMs = kept(shards[index].readyMs)
            trimmed.shards[index].runnerStartMs = kept(shards[index].runnerStartMs)
            trimmed.shards[index].runnerEndMs = kept(shards[index].runnerEndMs)
            trimmed.shards[index].retryStartMs = kept(shards[index].retryStartMs)
            trimmed.shards[index].retryEndMs = kept(shards[index].retryEndMs)
        }
        return trimmed
    }
}
