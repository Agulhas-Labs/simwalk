//
// Copyright © Agulhas Labs
//

import SimWalkCore

/// What the command line and the MCP tool ask of the mirror driver: one step, or one burst.
///
/// **A protocol so the faces can be tested without a Mac.** ``MirrorStepRunner`` is the only conformer in production; a test hands each subcommand a fake and sees the action it was given and the answer it passed through, with no window, no events and no capture.
public protocol MirrorStepping {
    /// Runs `action`, or a plain read for `nil`, and answers what the screen settled on.
    func run(_ action: MirrorAction?, settleMilliseconds: Int) throws -> MirrorObservation

    /// A tap at `point`, then `frames` captures as fast as capture goes.
    func burst(at point: MirrorFraction, frames: Int) throws -> MirrorBurst
}

extension MirrorStepRunner: MirrorStepping {}
