//
// Copyright © Agulhas Labs
//

import Foundation

/// Which screens a device walk measures, and over how many iterations (SimWalk#67, M4): a screen's own `"measure"`, or a performance budget.
///
/// **A budget implies `measure`, as a motion budget implies `motion`**: a performance budget nothing measured can only answer UNREACHABLE in `bundle audit`, so declaring one is asking for the figures it is checked against. A motion-only budget does not — `MotionOptIn` is the other half of that rule. A budget without a `measure` takes the default iteration count.
///
/// **Only a device walk runs it.** A simulator's figures are not a device's, so a simulator walk measures nothing and says so (``deviceOnlyNote(for:)``), and `validate` says the same as a note.
public struct MeasureOptIn {
    /// The iterations `screen` is measured over, or `nil` when it is not measured.
    public static func iterations(for screen: Walkbook.Screen) -> Int? {
        if let measure = screen.measure {
            return measure.iterations
        }
        return screen.budgets?.hasPerformanceBudget == true ? Walkbook.Measure.defaultIterations : nil
    }

    /// The screens of `book` that are measured, in walkbook order.
    public static func measuredScreens(in book: Walkbook) -> [Walkbook.Screen] {
        book.screens.filter { iterations(for: $0) != nil }
    }

    /// The note a simulator walk adds to its answer: ``deviceOnlyNote(for:)`` over the screens the walk executes, which are all of them unless `--screens` selects some; `nil` when none of those is measured.
    public static func walkNote(for book: Walkbook, screens selected: [String]) -> String? {
        let executed = selected.isEmpty ? book.screens : book.screens.filter { selected.contains($0.id) }
        return deviceOnlyNote(for: executed)
    }

    /// What a simulator walk and a plain `validate` (not `validate --device`, which applies the device rules and so measures them) say about the screens a device walk would measure; `nil` when there are none.
    ///
    /// One line naming the screens, so an agent reading a walk's answer does not take the absence of figures for a clean bill.
    public static func deviceOnlyNote(for screens: [Walkbook.Screen]) -> String? {
        let measured = screens.filter { iterations(for: $0) != nil }.map(\.id)
        guard !measured.isEmpty else { return nil }
        return "measure: device only, not run (\(measured.joined(separator: ", ")))"
    }

    /// Measured screen-states above which a walk's answer notes the launch environment's size.
    public static let launchEnvironmentNoteThreshold = 20

    /// The note `validate` and a device walk's answer carry when `book` measures more than ``launchEnvironmentNoteThreshold`` screen-states; `nil` otherwise.
    ///
    /// The records travel to the walk's runner as one environment variable, about 3 KB per measured state at 3 iterations, so dozens of them could push the launch environment toward iOS's limit and fail the walk's own launch.
    public static func launchEnvironmentNote(for book: Walkbook) -> String? {
        let count = MeasureRun.runs(for: book).count
        guard count > launchEnvironmentNoteThreshold else { return nil }
        return "measure: \(count) screen-states — each adds about 3 KB to the runner's launch environment; above about 50 the walk's runner may fail to launch"
    }
}
