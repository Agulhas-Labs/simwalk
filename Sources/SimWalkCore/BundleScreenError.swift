//
// Copyright © Agulhas Labs
//

/// Why one screen's text could not be read from a bundle that itself opened cleanly.
///
/// `CaptureBundle.read` already refuses a bundle that cannot be trusted; what is left here is a step that names a position the walk's plan does not have, or a screen the evidence cannot answer for under the state asked — the same "refuse rather than guess" the manifest's own reader holds to, one level down.
public enum BundleScreenError: Error, Equatable, CustomStringConvertible {
    /// `step` names a position outside the walk's plan — the manifest holds `screenCount` screens, in walkbook order.
    case stepOutOfRange(step: Int, screenCount: Int)
    /// `step` names a screen id this walk does not hold — ids are supposed to be unique, so more than one match refuses here too rather than guessing at the first.
    case screenIDNotFound(id: String, available: [String])
    /// `step` reads both ways and the two disagree: it is a valid position, naming `positionScreenID`, and it is also the exact id of the different screen at `idPosition` — answering either would be a guess at which one the caller meant.
    case ambiguousStep(step: String, positionScreenID: String, idPosition: Int)
    /// The screen at `step` holds no capture to read — every outcome but `.captured` can be empty, and `CaptureManifestValidator` holds `.captured` to at least one, so this is always a refused screen.
    case screenNotCaptured(step: Int, screenID: String, outcome: String)
    /// The screen holds no capture in the named state, and the walk did not refuse it either: the state was never one the walkbook planned for this screen, or it was planned and its capture failed (a `captureFailed` screen keeps the captures it did take).
    case stateNotFound(step: Int, screenID: String, requested: String, available: [String])
    /// The named state was planned and refused (`stateNotApplied`), not simply absent — a different fact from `stateNotFound`, and one the manifest can tell apart.
    case stateRefused(step: Int, screenID: String, requested: String, available: [String])

    public var description: String {
        switch self {
        case let .stepOutOfRange(step, screenCount):
            "step \(step) is out of range — this walk asked for \(screenCount) screen\(screenCount == 1 ? "" : "s"), so a valid step is 1 to \(screenCount)"
        case let .screenIDNotFound(id, available):
            "'\(id)' is not one of this walk's screen ids — it holds \(available.joined(separator: ", "))"
        case let .ambiguousStep(step, positionScreenID, idPosition):
            "'\(step)' names two screens — step \(step) by position is '\(positionScreenID)', and '\(step)' is also the id of step \(idPosition); say '\(positionScreenID)' for the first or \(idPosition) for the second"
        case let .screenNotCaptured(step, screenID, outcome):
            "step \(step) ('\(screenID)') was \(outcome) — there is no capture to read; run `bundle inspect` for the route and the reason"
        case let .stateNotFound(step, screenID, requested, available):
            "step \(step) ('\(screenID)') holds no '\(requested)' capture — it holds \(available.joined(separator: ", "))"
        case let .stateRefused(step, screenID, requested, available):
            "step \(step) ('\(screenID)') asked for '\(requested)', which this walk refused rather than captured — it holds \(available.isEmpty ? "nothing" : available.joined(separator: ", "))"
        }
    }
}

extension BundleScreenError: UsageFailureClassifiable {
    /// Every case is the caller's step or state naming something the bundle does not hold or did not capture — a refused argument, not a tool fault.
    public var usageFailureKind: UsageFailureKind {
        .inputRefused
    }
}
