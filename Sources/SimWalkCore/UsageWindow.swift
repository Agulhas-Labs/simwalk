//
// Copyright © Agulhas Labs
//

import Foundation

/// How far back `simwalk usage --since` reaches: a whole number of days or hours before now, as `3d` or `12h`.
///
/// Rolling rather than calendar — `3d` is the last seventy-two hours, not "since midnight three days ago" — because an hour window has no calendar reading at all, and one rule for both units is one rule a reader has to hold. The start is resolved once, from a `now` the face passes in, so the core never reads the clock and a test can state exactly which calls fall inside.
public struct UsageWindow: Equatable, Sendable {
    /// The window as it was asked for, `3d` — what the report's header repeats back.
    public let spelling: String
    /// The earliest moment a call can have been made and still be in the window.
    public let start: Date

    /// The window `spelling` names, ending at `now` — or `nil` when it names none: anything but a positive whole number of up to six digits followed by `d` or `h`.
    ///
    /// Six digits is a century and more of days, and the bound is what keeps the arithmetic below from overflowing on a number nobody meant.
    public init?(spelling: String, now: Date) {
        guard let match = spelling.wholeMatch(of: /([1-9][0-9]{0,5})([dh])/),
              let amount = Int(match.1)
        else {
            return nil
        }
        let hours = match.2 == "d" ? amount * Self.hoursPerDay : amount
        self.spelling = spelling
        // Floored to the whole second the header prints (`Timestamp.wholeSecondString`), not merely
        // displayed at that precision: a `start` left at full sub-second precision would let the printed
        // instant read later than the true boundary, so a call stamped exactly at what a reader sees
        // could fall just outside it. Flooring only ever widens the window, never narrows it.
        let exact = now.addingTimeInterval(-TimeInterval(hours) * Self.secondsPerHour)
        start = Date(timeIntervalSince1970: exact.timeIntervalSince1970.rounded(.down))
    }

    /// Whether `entry` was made inside the window.
    ///
    /// A timestamp that does not parse cannot be placed in any window, so it is left out of every one — never counted as recent. Every writer of the log stamps it through `Timestamp`, so this is a line somebody wrote by hand.
    public func contains(_ entry: UsageLog.Entry) -> Bool {
        guard let made = Timestamp.date(from: entry.timestamp) else { return false }
        return made >= start
    }

    private static var hoursPerDay: Int {
        24
    }

    private static var secondsPerHour: TimeInterval {
        3600
    }
}
