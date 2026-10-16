//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk mirror swipe <fx1> <fy1> <fx2> <fy2>` — a drag between two places in the window.
///
/// A drag moves things on the home screen and in the App Switcher but does not scroll inside an app; `scroll` does.
struct MirrorSwipeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "swipe", abstract: "Drag between two places (fractions 0…1 of the window). Does not scroll inside an app — use scroll.")

    @Argument(help: "Start, across the window.")
    var fx1: Double

    @Argument(help: "Start, down the window.")
    var fy1: Double

    @Argument(help: "End, across the window.")
    var fx2: Double

    @Argument(help: "End, down the window.")
    var fy2: Double

    @Option(name: .long, help: "How long the drag takes, in milliseconds (50…5000).")
    var ms = 350

    @OptionGroup var options: MirrorStepOptions

    func run() throws {
        try TimedCall.run(tool: "mirror swipe", target: "\(fx1),\(fy1)>\(fx2),\(fy2)", defaultFailureKind: .toolError) {
            try perform()
        }
    }

    func perform(makeStepper: (MirrorCaptureStore) -> any MirrorStepping = MirrorStepOptions.liveStepper, timeZone: TimeZone = .current) throws -> Answer {
        let duration = try MirrorGestureBounds.checkedMilliseconds(ms)
        let action = try MirrorAction.swipe(from: MirrorStepOptions.fraction(fx1, fy1), to: MirrorStepOptions.fraction(fx2, fy2), milliseconds: Double(duration))
        return try options.answer(action, makeStepper: makeStepper, timeZone: timeZone)
    }
}
