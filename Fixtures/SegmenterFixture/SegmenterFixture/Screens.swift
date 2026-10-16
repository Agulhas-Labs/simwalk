//
// Copyright © Agulhas Labs
//

import Charts
import SwiftUI

/// `Log`: an untitled lead, three headed sections (one row, two rows, three rows that only read) and a footnote.
struct SummaryScreen: View {
    var body: some View {
        ScreenStack(identifier: "summary-screen") {
            Text("Saturday 12 July")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Two entries are worth checking, starting with the rigging.")
                .font(.title3.weight(.semibold))
            HeaderRow(title: "Underway", detail: "1")
            ValueRow(title: "Wind speed", subtitle: "Up 4 kn on the last passage", value: "14 kn")
            HeaderRow(title: "Check soon", detail: "2")
            ValueRow(title: "Rigging tension", subtitle: "Down 3% on the last check", value: "82%")
            ValueRow(title: "Battery charge", subtitle: "Down 9% since Thursday", value: "71%")
            HeaderRow(title: "Before next sail", detail: "3")
            NoteRow(title: "Check the bilge pump", subtitle: "Bilge — nothing logged, so nothing to compare")
            NoteRow(title: "Top up the fresh water", subtitle: "Water tank — nothing logged since 2 July")
            NoteRow(title: "Log the engine hours", subtitle: "Engine — nothing logged, so nothing to compare")
            Text("Nothing was logged for 3 of them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// `Passages`: a week's lead and total, then its passages, its boats, its days afloat and an empty-state section below the fold.
struct PassagesScreen: View {
    let week: Week

    var body: some View {
        ScreenStack(identifier: "passages-screen") {
            Text(week.range)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(week.lead)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Time under sail")
                    Spacer()
                    Text(week.range)
                }
                .font(.caption)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(week.total)
                        .font(.largeTitle.bold())
                    Text(week.passageCount)
                        .font(.subheadline)
                    Spacer()
                    Text("7 days")
                        .font(.footnote)
                }
                Text(week.footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            HeaderRow(title: "Passages", detail: "Most recent first")
            ForEach(week.passages.indices, id: \.self) { index in
                let passage = week.passages[index]
                NavigationLink(value: passage.kind) {
                    RowLabel(title: passage.kind, subtitle: passage.when, value: passage.duration)
                }
                .buttonStyle(.plain)
            }
            HeaderRow(title: "By boat", detail: week.boatCount)
            ForEach(week.boats.indices, id: \.self) { index in
                let boat = week.boats[index]
                ValueRow(title: boat.name, subtitle: boat.summary, value: boat.count)
            }
            HeaderRow(title: "Days afloat", detail: week.daysAfloat)
            ForEach(week.weeks.indices, id: \.self) { index in
                DaysRow(name: week.weeks[index].name, days: week.weeks[index].days)
            }
            HeaderRow(title: "Too few passages yet", detail: "1 chart")
            Text("No wind trend yet — it appears once there are six passages.")
                .font(.footnote)
            Text(week.logged)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A passage's detail: its lead, a wind chart over the time of day, a boat-speed card whose chart collapses to no height, and the earlier passages running below the fold.
struct PassageDetailScreen: View {
    private static let wind: [(minute: Int, knots: Double)] = [(0, 10), (15, 11), (30, 13), (45, 12), (60, 14), (75, 15), (90, 13), (105, 12), (120, 11), (130, 12)]

    var body: some View {
        ScreenStack(identifier: "passage-detail") {
            Heading("Coastal passage")
            Text("Coastal passage — 8.2 nm in 2:10.")
                .font(.title3.weight(.semibold))
            Text("8.2 nm")
                .font(.largeTitle.bold())
            Text("09:10–11:20")
                .font(.caption)
                .foregroundStyle(.secondary)
            StatGrid(stats: [("2:10", "Duration"), ("6", "Tacks"), ("4", "Crew aboard")])
            Heading("Wind speed")
            PlottedChart(height: 96, ticks: ["09:10", "10:15", "11:20"]) {
                Chart(Self.wind, id: \.minute) { sample in
                    LineMark(x: .value("Minute", sample.minute), y: .value("Knots", sample.knots))
                }
            }
            StatGrid(stats: [("12 kn", "Average"), ("19 kn", "Gusts")])
            HeaderRow(title: "Boat speed", detail: "3.8 kn avg")
            PlottedChart(height: 0, ticks: ["depart", "arrive"]) {
                Chart(Self.wind, id: \.minute) { sample in
                    LineMark(x: .value("Minute", sample.minute), y: .value("Knots", sample.knots / 3))
                }
            }
            StatGrid(stats: [("3.8 kn", "Avg speed"), ("6.4 kn", "Top speed")])
            HStack(spacing: 12) {
                Image(systemName: "arrow.up")
                VStack(alignment: .leading, spacing: 2) {
                    Text("5% faster than your average")
                        .font(.subheadline)
                    Text("3.8 kn against 3.6 kn")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            HeaderRow(title: "Earlier passages", detail: "5 passages")
            ForEach(Self.earlier.indices, id: \.self) { index in
                let passage = Self.earlier[index]
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(passage.day)
                            .font(.subheadline)
                        Text(passage.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(passage.change)
                        .font(.subheadline.monospacedDigit())
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    /// An earlier passage on the same route: its day, when and how far, and how much further this one went.
    private struct Earlier {
        let day: String
        let detail: String
        let change: String
    }

    private static let earlier = [
        Earlier(day: "Sun 6 Jul", detail: "6 July 10:05 · 7.9 nm", change: "+0.3 nm"),
        Earlier(day: "Sat 28 Jun", detail: "28 June 09:40 · 8.0 nm", change: "+0.2 nm"),
        Earlier(day: "Sun 22 Jun", detail: "22 June 11:15 · 7.4 nm", change: "+0.8 nm"),
        Earlier(day: "Sat 14 Jun", detail: "14 June 08:55 · 8.6 nm", change: "−0.4 nm"),
        Earlier(day: "Sun 8 Jun", detail: "8 June 10:30 · 6.9 nm", change: "+1.3 nm"),
    ]
}

/// `Wind`: a month of wind over an axis from `30 days ago` to `Today`.
struct WindScreen: View {
    var body: some View {
        ScreenStack(identifier: "wind-screen") {
            Heading("Wind")
            Text("Wind has eased over the month, from fresh to moderate.")
                .font(.title3.weight(.semibold))
            Heading("Average wind")
            Text("11 kn")
                .font(.largeTitle.bold())
            PlottedChart(height: 82, ticks: ["30 days ago", "Today"]) {
                Chart(0 ..< 30, id: \.self) { day in
                    LineMark(x: .value("Day", day), y: .value("Knots", 16 - Double(day % 7) - Double(day) / 6))
                }
            }
            Text("Read from the masthead sensor at each log entry.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// `Hours afloat`: a week's bars over single-letter weekdays.
struct HoursAfloatScreen: View {
    private static let hours: [Double] = [1, 0, 2.5, 0, 1.5, 4, 0]

    var body: some View {
        ScreenStack(identifier: "hours-screen") {
            Heading("Hours afloat")
            Text("9 hours afloat this week, most of them on Saturday.")
                .font(.title3.weight(.semibold))
            Heading("This week")
            PlottedChart(height: 80, ticks: ["T", "W", "T", "F", "S", "S", "M"], columns: true) {
                Chart(Self.hours.indices, id: \.self) { day in
                    BarMark(x: .value("Day", day), y: .value("Hours", Self.hours[day]))
                }
            }
            Text("Counted from cast off to mooring.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// `Anchor watch`: one night's watches over packed time ticks, and the last seven nights over short weekday names.
struct AnchorWatchScreen: View {
    /// One watch: when it began and ended, in hours from 10 pm, and where it was kept.
    private struct Watch {
        let start: Double
        let end: Double
        let row: String
    }

    private static let watches = [Watch(start: 0, end: 1.5, row: "Deck"), Watch(start: 1.5, end: 4, row: "Bunk"), Watch(start: 4, end: 5.5, row: "Deck"), Watch(start: 5.5, end: 8, row: "Bunk")]
    private static let nights: [Double] = [6, 7.5, 5, 8, 6.5, 7, 6]

    var body: some View {
        ScreenStack(identifier: "watch-screen") {
            Heading("Anchor watch")
            Text("Two watches on deck last night, both quiet.")
                .font(.title3.weight(.semibold))
            Heading("Last night")
            PlottedChart(height: 112, ticks: ["10:00 pm", "12:00 am", "2:00 am", "4:00 am", "6:00 am"], columns: true) {
                Chart(Self.watches.indices, id: \.self) { index in
                    let watch = Self.watches[index]
                    RectangleMark(xStart: .value("Start", watch.start), xEnd: .value("End", watch.end), y: .value("Where", watch.row))
                }
            }
            Heading("Last seven nights")
            PlottedChart(height: 62, ticks: ["Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Mon"], columns: true, font: .caption2) {
                Chart(Self.nights.indices, id: \.self) { night in
                    BarMark(x: .value("Night", night), y: .value("Hours", Self.nights[night]))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
