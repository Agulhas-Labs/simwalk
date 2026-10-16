//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkMCP
import Testing

/// Which cancel reaches the call in flight (SimWalk#83): the one naming its id as a JSON value, and no other.
struct InFlightRequestTests {
    /// `"1"` and `true` are not the request `1`, though `NSNumber` would call `true` equal to it; and once the call is answered, a cancel naming it reaches nothing.
    @Test
    func aCancelReachesTheCallInFlightOnlyByItsIdAsAJSONValue() throws {
        let inFlight = InFlightRequest()
        let cancellation = inFlight.start(id: 1)

        try inFlight.hear(Self.cancel(naming: "1"))
        try inFlight.hear(Self.cancel(naming: true))
        let byLookalikes = cancellation.isCancelled
        try inFlight.hear(Self.cancel(naming: 1))
        let byItsOwnID = cancellation.isCancelled
        let next = inFlight.start(id: 2)
        inFlight.finish()
        try inFlight.hear(Self.cancel(naming: 2))

        #expect(!byLookalikes)
        #expect(byItsOwnID)
        #expect(!next.isCancelled)
    }

    /// A cancel naming a call that has not started is kept until that call starts, which consumes it; the set holds the newest `capacity` ids (SimWalk#85).
    @Test
    func aCancelAheadOfItsCallIsKeptUntilTheCallStartsAndIsBounded() throws {
        let inFlight = InFlightRequest()
        try inFlight.hear(Self.cancel(naming: 5))
        let queued = inFlight.start(id: 5)
        inFlight.finish()
        let again = inFlight.start(id: 5)
        inFlight.finish()

        for id in 100 ..< 100 + InFlightRequest.capacity + 1 {
            try inFlight.hear(Self.cancel(naming: id))
        }
        let evicted = inFlight.start(id: 100)
        inFlight.finish()
        let newest = inFlight.start(id: 100 + InFlightRequest.capacity)

        #expect(queued.isCancelled)
        #expect(!again.isCancelled)
        #expect(!evicted.isCancelled)
        #expect(newest.isCancelled)
    }

    /// A `notifications/cancelled` line naming `requestID`.
    private static func cancel(naming requestID: Any, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": requestID, "reason": "test"]]
        return try #require(String(data: JSONSerialization.data(withJSONObject: message), encoding: .utf8), sourceLocation: sourceLocation)
    }
}
