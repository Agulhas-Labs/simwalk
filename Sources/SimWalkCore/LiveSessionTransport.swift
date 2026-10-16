//
// Copyright © Agulhas Labs
//

import Foundation

/// What a live session's runner serves through: the simulator's file channel (``LiveSessionChannel``), or the socket a physical device listens on (``DeviceSessionTransport``).
///
/// **The loop's decisions do not depend on the carrier.** Which request comes next, when a session has gone idle and what a request the runner cannot read gets back are ``LiveSessionServingLoop``'s, decided once for both targets; a transport only carries the records. Each transport names its ``Liveness``, so the loop asks the simulator's runner for a beating heartbeat and the device's for the one form that says it has none, and neither can be handed the other's.
public protocol LiveSessionTransport {
    /// What the loop stops once the exit record is down: ``LiveSessionHeartbeat/Running`` on a simulator, ``DeviceSessionTransport/NoHeartbeat`` on a device.
    associatedtype Liveness: LiveSessionLiveness

    /// What the runner launches; a throw, there being nothing to launch among them, is the session's failure.
    func launchRecord() throws -> LiveSessionLaunch

    /// Says the runner is ready, once the app is launched, and from then on answers whoever asks.
    func markReady(_ ready: LiveSessionReady) throws

    /// Request `number`, if one has arrived; `nil` when none has yet.
    ///
    /// A throw is a request that is not one — of another shape, or an action this runner does not know — and the loop answers it as a failure under `number` through ``respond(_:)``, so a transport that throws has kept what it needs to deliver that answer.
    func request(_ number: Int) throws -> LiveSessionRequest?

    /// Waits after a ``request(_:)`` that found nothing, through `pause`, or not at all for a transport whose ``request(_:)`` already waited — so no exchange carries a wait twice.
    func afterEmptyPoll(pause: (TimeInterval) -> Void)

    /// Delivers the answer to the request just taken, under its number.
    func respond(_ response: LiveSessionResponse) throws

    /// Records why the runner stopped, where the host looks for it.
    func markExit(_ exit: LiveSessionExit) throws
}
