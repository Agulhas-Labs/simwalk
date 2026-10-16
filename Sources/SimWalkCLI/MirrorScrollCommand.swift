//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk mirror scroll <lines>` — wheel lines at a place in the window; positive reveals what is below, or to the right with `--horizontal`.
///
/// A negative count is written after `--` on a command line (`simwalk mirror scroll -- -3`); the MCP tool does it for the caller.
struct MirrorScrollCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "scroll", abstract: "Scroll by wheel lines at a place in the window: positive reveals what is below (or to the right with --horizontal).")

    @Argument(help: "Wheel lines, 1…50 in magnitude; positive reveals what is below, or to the right.")
    var lines: Int

    @Flag(name: .long, help: "Scroll sideways instead of down.")
    var horizontal = false

    @Option(name: .customLong("at"), help: "Where the pointer is, as <fx>,<fy> fractions of the window.")
    var position = ".5,.5"

    @OptionGroup var options: MirrorStepOptions

    func run() throws {
        try TimedCall.run(tool: "mirror scroll", target: "\(lines)", defaultFailureKind: .toolError) {
            try perform()
        }
    }

    func perform(makeStepper: (MirrorCaptureStore) -> any MirrorStepping = MirrorStepOptions.liveStepper, timeZone: TimeZone = .current) throws -> Answer {
        let count = try MirrorGestureBounds.checkedLines(lines)
        let parts = position.split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let x = parts[0], let y = parts[1] else {
            throw InputRefusal("--at '\(position)' is not <fx>,<fy> — two fractions of the window, e.g. .5,.5")
        }
        let action = try MirrorAction.scroll(lines: count, horizontal: horizontal, position: MirrorStepOptions.fraction(x, y))
        return try options.answer(action, makeStepper: makeStepper, timeZone: timeZone)
    }
}
