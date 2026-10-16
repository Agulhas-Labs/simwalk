//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk mirror burst <fx> <fy> --frames <n>` — a tap, then frames as fast as capture goes, to see an animation or a transition that settles before a read could.
struct MirrorBurstCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "burst", abstract: "Tap, then capture 1…60 frames as fast as possible; --sheet tiles them into one image.")

    /// The most frames a burst takes.
    static var frameLimit: Int {
        60
    }

    @Argument(help: ArgumentHelp("Across the window, 0 (left) to 1 (right).", valueName: "fx"))
    var across: Double

    @Argument(help: ArgumentHelp("Down the window, 0 (top) to 1 (bottom).", valueName: "fy"))
    var down: Double

    @Option(name: .long, help: "How many frames to take, 1…60.")
    var frames: Int

    @Flag(name: .long, help: "Also write sheet.png beside the frames: the frames tiled, six to a row, each labelled with its time after the tap.")
    var sheet = false

    @Option(name: .long, help: "Keep the frames in this directory, unpruned, instead of the standard store.")
    var out: String?

    func run() throws {
        try TimedCall.run(tool: "mirror burst", target: "\(across),\(down)", defaultFailureKind: .toolError) {
            try perform()
        }
    }

    func perform(
        makeStepper: (MirrorCaptureStore) -> any MirrorStepping = MirrorStepOptions.liveStepper,
        makeSheet: (MirrorBurst) throws -> URL? = MirrorContactSheet.write
    ) throws -> Answer {
        guard (1 ... Self.frameLimit).contains(frames) else {
            throw InputRefusal("--frames \(frames) is outside 1…\(Self.frameLimit)")
        }
        let point = try MirrorStepOptions.fraction(across, down)
        let store = out.map { MirrorCaptureStore.out(URL(fileURLWithPath: $0)) } ?? .standard()
        let burst = try makeStepper(store).burst(at: point, frames: frames)
        return try MirrorBurstSummary.answer(burst, sheet: sheet ? makeSheet(burst) : nil)
    }
}
