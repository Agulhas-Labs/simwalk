//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// `simwalk usage --since`: which spellings name a window, where it starts, and which calls fall inside it.
struct UsageWindowTests {
    private static let now = Date(timeIntervalSince1970: 1_786_867_200)

    @Test
    func daysAndHoursAreRollingWindowsEndingNow() throws {
        let days = try #require(UsageWindow(spelling: "3d", now: Self.now))
        let hours = try #require(UsageWindow(spelling: "12h", now: Self.now))

        #expect(days.start == Self.now.addingTimeInterval(-3 * 86400))
        #expect(days.spelling == "3d")
        #expect(hours.start == Self.now.addingTimeInterval(-12 * 3600))
    }

    /// Anything but a positive whole number of days or hours names no window — including a zero, which would be a window of nothing and read as an empty log.
    @Test
    func aspellingThatIsNotAWholeNumberOfDaysOrHoursNamesNoWindow() {
        for spelling in ["", "3", "d", "0d", "-3d", "3w", "1.5d", "3D", " 3d", "03d", "1234567d"] {
            #expect(UsageWindow(spelling: spelling, now: Self.now) == nil, "\(spelling)")
        }
    }

    /// A call is inside the window from its start on, in either timestamp shape the log has carried — and a timestamp that does not parse is inside none, never counted as recent.
    @Test
    func acallIsInsideFromTheStartOnAndAnUnreadableTimestampIsInsideNone() throws {
        let window = try #require(UsageWindow(spelling: "1h", now: Self.now))

        #expect(window.contains(Self.entry("2026-08-16T07:00:00.000Z")))
        #expect(window.contains(Self.entry("2026-08-16T07:30:00Z")))
        #expect(!window.contains(Self.entry("2026-08-16T06:59:59.999Z")))
        #expect(!window.contains(Self.entry("yesterday")))
    }

    private static func entry(_ timestamp: String) -> UsageLog.Entry {
        UsageLog.Entry(timestamp: timestamp, tool: "walk", target: nil, milliseconds: 1, succeeded: true, error: nil)
    }

    /// `start` is floored to the whole second the header prints it at, not merely displayed there — a `now` with sub-second precision must not leave a `start` a reader's printed instant falls after, or a call stamped exactly at what the header shows would compare as *before* the true, unrounded start and be excluded, which is what a reader sees as "the window's edge does not include its own edge".
    @Test
    func thewindowsStartIsFlooredToTheWholeSecondItIsPrinted() throws {
        let now = Date(timeIntervalSince1970: 1_786_867_200.842)
        let window = try #require(UsageWindow(spelling: "1h", now: now))
        let exact = now.addingTimeInterval(-3600)

        #expect(window.start.timeIntervalSince1970 == exact.timeIntervalSince1970.rounded(.down))
        #expect(window.start <= exact)
        #expect(Timestamp.wholeSecondString(from: window.start).hasSuffix("Z"))
        // A call stamped exactly at the printed instant is inside the window — the property a display
        // that rounded independently of the comparison used to violate.
        #expect(window.contains(Self.entry(Timestamp.wholeSecondString(from: window.start))))
    }
}
