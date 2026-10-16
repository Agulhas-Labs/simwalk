//
// Copyright © Agulhas Labs
//

import Foundation

/// The serving loop's word that the exit record is written, which ``LiveSessionLiveness/stop(_:)`` requires.
///
/// Its `init` is the synthesized one, which is internal, so no code outside the core can make one: a requirement of a public protocol is public on every conformance, and this is what keeps the heartbeat's stop the loop's alone (the `Clearance` pattern).
public struct LiveSessionExitRecorded {}
