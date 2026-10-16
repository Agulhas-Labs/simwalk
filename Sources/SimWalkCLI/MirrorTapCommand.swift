//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk mirror tap <fx> <fy>` — a tap at a place in the mirroring window, as fractions of its width and height.
struct MirrorTapCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "tap", abstract: "Tap at fractions (0…1) of the iPhone Mirroring window — the centre of a line box an answer gave — and read what changed.")

    @Argument(help: ArgumentHelp("Across the window, 0 (left) to 1 (right).", valueName: "fx"))
    var across: Double

    @Argument(help: ArgumentHelp("Down the window, 0 (top) to 1 (bottom).", valueName: "fy"))
    var down: Double

    @OptionGroup var options: MirrorStepOptions

    func run() throws {
        try TimedCall.run(tool: "mirror tap", target: "\(across),\(down)", defaultFailureKind: .toolError) {
            try perform()
        }
    }

    func perform(makeStepper: (MirrorCaptureStore) -> any MirrorStepping = MirrorStepOptions.liveStepper, timeZone: TimeZone = .current) throws -> Answer {
        try options.answer(.tap(MirrorStepOptions.fraction(across, down)), makeStepper: makeStepper, timeZone: timeZone)
    }
}
