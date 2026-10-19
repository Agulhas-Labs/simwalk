//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The tool call the server is answering now, and the one route a client's cancel of it has in (SimWalk#83).
///
/// **The cancel is heard where the line is read, not where it is handled.** The server answers one call at a time, inside the actor, and a walk holds it for minutes — so a `notifications/cancelled` handled in turn would wait for the walk it names to end. ``hear(_:)`` is called by ``FileHandleLines`` for every line as it arrives, on the reader's queue, and cancels the call in flight when the line names it.
///
/// **A cancel for a call not yet started is kept** (SimWalk#85): Claude Code sends calls in parallel and this server answers one at a time, so a call can be cancelled while it is still queued behind a walk. The reader cannot tell a queued call from an unknown or already answered one, so a cancel naming any request other than the one in flight goes into a small bounded set, oldest dropped first; ``start(id:)`` consumes the id and returns a ``Cancellation`` already raised, and the server skips the call without answering. A stale id that is never started costs one slot until it ages out.
///
/// **Ids match as JSON values**: `1` and `"1"` are different requests, and `true` is not `1` — which `NSNumber`'s own equality would say it is — so an id is compared by its canonical JSON text.
final class InFlightRequest: @unchecked Sendable {
    private let lock = NSLock()
    /// The calls being answered, by id: one at a time for a blocking client, overlapping for a bounded one.
    private var current: [String: Cancellation] = [:]
    private var cancelledAhead: [String] = []

    /// How many cancels naming no call in flight are remembered.
    static var capacity: Int {
        64
    }

    /// Marks the call `id` as in flight, returning what a cancel of it raises — already raised when the client cancelled it before it started.
    func start(id: Any) -> Cancellation {
        let cancellation = Cancellation()
        lock.withLock {
            let key = Self.key(id)
            if let key {
                current[key] = cancellation
            }
            if let key, let index = cancelledAhead.firstIndex(of: key) {
                cancelledAhead.remove(at: index)
                cancellation.cancel()
            }
        }
        return cancellation
    }

    /// Marks the call `id` as answered: a cancel arriving after this names nothing.
    func finish(id: Any) {
        guard let key = Self.key(id) else { return }
        lock.withLock { current[key] = nil }
    }

    /// Cancels the call in flight when `line` is a `notifications/cancelled` naming it.
    ///
    /// A cancel naming anything else is stored, including one that names a queued request that is not a tool call (`tools/list`, `ping`) or a call whose answer won the race with it. Such an id is never started, so it stays until it ages out of the ``capacity``-slot set, and a non-tool request it named is still answered (SimWalk#89). That is acceptable: a client never reuses a request id within a session, so a stale id cannot cancel a later call, and the set is bounded, so stale ids cost at most ``capacity`` slots.
    func hear(_ line: String) {
        // Most lines are requests: only one that could name the method is worth parsing twice — by its last word, since a
        // serialiser may escape the slash.
        guard line.contains("cancelled"),
              let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["method"] as? String == Self.cancelledMethod,
              let params = message["params"] as? [String: Any],
              let requestID = params["requestId"].flatMap(Self.key)
        else {
            return
        }
        let cancellation: Cancellation? = lock.withLock {
            if let running = current[requestID] {
                return running
            }
            if !cancelledAhead.contains(requestID) {
                cancelledAhead.append(requestID)
                if cancelledAhead.count > Self.capacity {
                    cancelledAhead.removeFirst()
                }
            }
            return nil
        }
        cancellation?.cancel()
    }

    /// The method a client cancels a request with.
    static var cancelledMethod: String {
        "notifications/cancelled"
    }

    /// An id's canonical JSON text — what two ids are compared by.
    private static func key(_ id: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [id], options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
