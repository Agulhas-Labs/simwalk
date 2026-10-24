//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a text field's value has held still long enough to be judged (SimWalk#214).
///
/// **An app may rewrite a field a beat after it changed** (an `onChange` that uppercases it, a formatter), so a value read straight after typing is a race. The value is settled once it has not changed for `quiet`, or when `budget` has run out, whichever comes first; the runner supplies the reads and the clock, and this holds the decision where a test replays it against scripted reads.
public struct FieldValueSettle: Equatable {
    /// The last value read, `nil` when it could not be read.
    public private(set) var value: String?
    private let quiet: TimeInterval
    private let budget: TimeInterval
    private var changedAt: TimeInterval?

    public init(quiet: TimeInterval, budget: TimeInterval) {
        self.quiet = quiet
        self.budget = budget
    }

    /// Records a read taken `elapsed` seconds after the first one; a read different from the last restarts the quiet period.
    public mutating func record(_ read: String?, at elapsed: TimeInterval) {
        guard changedAt == nil || read != value else { return }
        value = read
        changedAt = elapsed
    }

    /// Whether the value has held for `quiet` as of `elapsed`, or the budget has run out.
    public func isSettled(at elapsed: TimeInterval) -> Bool {
        guard let changedAt else { return false }
        return elapsed - changedAt >= quiet || elapsed >= budget
    }
}
