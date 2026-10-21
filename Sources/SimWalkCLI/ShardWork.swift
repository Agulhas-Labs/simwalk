//
// Copyright © Agulhas Labs
//

/// One shard's walk as `DispatchQueue.concurrentPerform` runs it, on a thread of its own per shard.
///
/// Unchecked because its body reads values that are not `Sendable` — the shell, the clock and the telemetry, which a serial walk already shares with the threads its children's output drains run on — and writes its results only under its caller's lock.
struct ShardWork: @unchecked Sendable {
    let body: (Int) -> Void
}
