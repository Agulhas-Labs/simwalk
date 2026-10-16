//
// Copyright © Agulhas Labs
//

import Foundation

/// What a runner hands ``LiveSessionServingLoop/run(heartbeat:start:answer:handBack:now:pause:)`` to say how its stop is bounded, stopped by the loop once the exit record that supersedes it is written.
///
/// Each ``LiveSessionTransport`` names the one form it takes, so the proof cannot be traded: a simulator runner must start its heartbeat (``LiveSessionHeartbeat/Running`` is minted only by starting one), and a device runner says in so many words that it has none (``DeviceSessionTransport/NoHeartbeat/onDevice``).
///
/// **Only the loop can stop one.** ``stop(_:)`` takes a ``LiveSessionExitRecorded``, which only this module mints, so code outside the core — the runner included — cannot stop a heartbeat before `exit.json` is down, though the conformance makes the method itself public.
public protocol LiveSessionLiveness {
    /// Stops whatever bounds the stop; nothing more of it is written once this returns.
    ///
    /// - Parameter recorded: the loop's word that the exit record which supersedes the heartbeat is written.
    func stop(_ recorded: LiveSessionExitRecorded)
}
