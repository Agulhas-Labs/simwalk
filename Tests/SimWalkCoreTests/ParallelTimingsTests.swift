//
// Copyright © Agulhas Labs
//

@testable import SimWalkCore
import Testing

/// The `walk.parallel` line's marks, which an interrupted walk's line holds through its own `ms` only (SimWalk#189).
struct ParallelTimingsTests {
    /// Every mark later than the cut is left out and one at the cut stays; nothing is capped to the cut, and the merge's duration, which is no offset, is left alone.
    @Test
    func throughLeavesOutEveryMarkLaterThanTheCutAndKeepsOneAtIt() {
        let shard = ShardTiming(index: 0, device: "A", origin: .cloned, readyMs: 10, runnerStartMs: 20, runnerEndMs: 100, retryStartMs: 101, retryEndMs: 200)
        let timings = ParallelTimings(shards: [shard], mergeMs: 150)

        let trimmed = timings.through(100)

        #expect(trimmed.shards[0].readyMs == 10)
        #expect(trimmed.shards[0].runnerStartMs == 20)
        #expect(trimmed.shards[0].runnerEndMs == 100)
        #expect(trimmed.shards[0].retryStartMs == nil)
        #expect(trimmed.shards[0].retryEndMs == nil)
        #expect(trimmed.mergeMs == 150)
        #expect(timings.through(200).shards == timings.shards)
        #expect(timings.through(200) == ParallelTimings(shards: [shard], mergeMs: 150))
    }

    /// The readiness mark is trimmed like the rest, and the shard's identity is not touched.
    @Test
    func throughTrimsReadinessAndKeepsTheShardsIdentity() {
        let shard = ShardTiming(index: 3, device: "B", origin: .created, readyMs: 50)

        let trimmed = ParallelTimings(shards: [shard]).through(49)

        #expect(trimmed.shards == [ShardTiming(index: 3, device: "B", origin: .created)])
    }
}
