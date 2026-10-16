//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// The options every mirror step shares, and the one place a step becomes an answer — so the five verbs that take a step cannot answer differently.
///
/// `--out` names a directory the captures are kept in without pruning, since a person who named a directory keeps what is in it; without it they go to the standard store, which prunes to the newest hundred.
struct MirrorStepOptions: ParsableArguments {
    /// `.unconditional` for the reason `inspect`'s is: a match can begin with a dash.
    @Option(name: .long, parsing: .unconditional, help: "Only the text lines that contain this text (case-insensitive) are listed as served.")
    var match: String?

    @Option(name: .customLong("settle-ms"), help: "The longest to wait, in milliseconds, for the screen to stop changing.")
    var settleMilliseconds = 3000

    @Option(name: .long, help: "Keep the captures in this directory, unpruned, instead of the standard store.")
    var out: String?

    /// The store captures go to.
    func store() -> MirrorCaptureStore {
        out.map { MirrorCaptureStore.out(URL(fileURLWithPath: $0)) } ?? .standard()
    }

    /// Runs `action` (nil is a read) through the stepper `makeStepper` builds over this store, and renders the observation.
    func answer(
        _ action: MirrorAction?,
        makeStepper: (MirrorCaptureStore) -> any MirrorStepping,
        timeZone: TimeZone = .current
    ) throws -> Answer {
        guard settleMilliseconds >= 0 else {
            throw InputRefusal("--settle-ms \(settleMilliseconds) is negative — it is how long to wait, in milliseconds")
        }
        let observation = try makeStepper(store()).run(action, settleMilliseconds: settleMilliseconds)
        return MirrorObservationSummary.answer(observation, match: match, timeZone: timeZone)
    }

    /// The default stepper: the real runner over `store`.
    static func liveStepper(_ store: MirrorCaptureStore) -> any MirrorStepping {
        MirrorStepRunner(store: store)
    }

    /// `x` and `y` as a fraction of the window, refused naming the value when outside `0…1`.
    static func fraction(_ x: Double, _ y: Double) throws -> MirrorFraction {
        try MirrorFraction(x: x, y: y)
    }
}
