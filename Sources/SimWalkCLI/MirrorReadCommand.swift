//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk mirror read` — what the iPhone shows now, as OCR text lines with their boxes, and the path of the screenshot.
struct MirrorReadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "read", abstract: "Read the iPhone's screen through iPhone Mirroring: OCR text lines with boxes, and the screenshot's path.")

    @OptionGroup var options: MirrorStepOptions

    func run() throws {
        try TimedCall.run(tool: "mirror read", target: nil, defaultFailureKind: .toolError) {
            try perform()
        }
    }

    func perform(makeStepper: (MirrorCaptureStore) -> any MirrorStepping = MirrorStepOptions.liveStepper, timeZone: TimeZone = .current) throws -> Answer {
        try options.answer(nil, makeStepper: makeStepper, timeZone: timeZone)
    }
}
