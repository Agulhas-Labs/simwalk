//
// Copyright © Agulhas Labs
//

import Foundation

/// One week of the log as the `Passages` tab shows it. Every figure is fixed, so a capture is the same tree every time.
struct Week {
    struct Passage {
        let kind: String
        let when: String
        let duration: String
    }

    struct Boat {
        let name: String
        let summary: String
        let count: String
    }

    let range: String
    let lead: String
    let total: String
    let passageCount: String
    let footnote: String
    let passages: [Passage]
    let boatCount: String
    let boats: [Boat]
    let daysAfloat: String
    let weeks: [(name: String, days: Int)]
    let logged: String
}

enum LogData {
    /// The week a launch shows: the first, or the later one under `-SegmenterFixtureLaterWeek`.
    static let week = ProcessInfo.processInfo.arguments.contains("-SegmenterFixtureLaterWeek") ? later : first

    static let first = Week(
        range: "6 – 12 July",
        lead: "4 passages, 31 nm. 3 days in harbour.",
        total: "8 h 50 min",
        passageCount: "4 passages",
        footnote: "Summed from the 4 passages listed below.",
        passages: [
            Week.Passage(kind: "Coastal passage", when: "Saturday 09:10 · 8.2 nm", duration: "2 h 10 min"),
            Week.Passage(kind: "Harbour sail", when: "Thursday 17:30 · 4.6 nm", duration: "1 h 25 min"),
            Week.Passage(kind: "Night passage", when: "Tuesday 21:05 · 12.9 nm", duration: "3 h 40 min"),
            Week.Passage(kind: "Harbour sail", when: "Monday 18:15 · 5.3 nm", duration: "1 h 35 min"),
        ],
        boatCount: "3 boats",
        boats: [
            Week.Boat(name: "Kestrel", summary: "Saturday · 8.2 nm in 2 h 10 min", count: "1"),
            Week.Boat(name: "Tern", summary: "Thursday · 9.9 nm in 3 h", count: "2"),
            Week.Boat(name: "Petrel", summary: "Tuesday · 12.9 nm in 3 h 40 min", count: "1"),
        ],
        daysAfloat: "4 passages across 4 days",
        weeks: [("Week 24", 2), ("Week 25", 3), ("Week 26", 1), ("Week 27", 2), ("Week 28", 4)],
        logged: "31 nm is what was logged. There is no target on this screen."
    )

    static let later = Week(
        range: "13 – 19 July",
        lead: "3 passages, 28.4 nm. 4 days in harbour.",
        total: "8 h 5 min",
        passageCount: "3 passages",
        footnote: "Summed from the 3 passages listed below.",
        passages: [
            Week.Passage(kind: "Coastal passage", when: "Sunday 08:40 · 10.4 nm", duration: "2 h 45 min"),
            Week.Passage(kind: "Night passage", when: "Friday 20:50 · 14.1 nm", duration: "4 h 5 min"),
            Week.Passage(kind: "Harbour sail", when: "Wednesday 18:00 · 3.9 nm", duration: "1 h 10 min"),
        ],
        boatCount: "2 boats",
        boats: [
            Week.Boat(name: "Kestrel", summary: "Sunday · 14.3 nm in 3 h 55 min", count: "2"),
            Week.Boat(name: "Tern", summary: "Friday · 14.1 nm in 4 h 5 min", count: "1"),
        ],
        daysAfloat: "3 passages across 3 days",
        weeks: [("Week 25", 3), ("Week 26", 1), ("Week 27", 2), ("Week 28", 4), ("Week 29", 3)],
        logged: "28.4 nm is what was logged. There is no target on this screen."
    )
}
