//
// Copyright © Agulhas Labs
//

import Charts
import SwiftUI

/// The horizontal inset every screen's content sits at.
let screenInset: CGFloat = 22

/// A screen's scrolling content: a leading-aligned stack at the screen inset, identified for a walkbook's `expect`.
struct ScreenStack<Content: View>: View {
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, screenInset)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(identifier)
    }
}

/// A section's heading on its own: one run of caption text.
struct Heading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

/// A section's header row: its title at the leading edge and a detail at the trailing one, read as one element.
struct HeaderRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// A row a person can open: a title over a subtitle, with a figure at the trailing edge, on a rounded background reaching past the screen inset.
struct ValueRow: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        Button {} label: {
            RowLabel(title: title, subtitle: subtitle, value: value)
        }
        .buttonStyle(.plain)
    }
}

/// What a ``ValueRow`` draws, for a navigation link to draw the same.
struct RowLabel: View {
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, -8)
    }
}

/// A row that only reads: a title over a subtitle, combined into one element.
struct NoteRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// A figure over its label, read as one element.
struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row of stats, kept together as one container element.
struct StatGrid: View {
    let stats: [(value: String, label: String)]

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            ForEach(stats.indices, id: \.self) { index in
                Stat(value: stats[index].value, label: stats[index].label)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}

/// A chart's axis labels under its plot, read as one element. Spread to the ends of the row, or each centred in an equal column under its bar.
struct TickRow: View {
    let ticks: [String]
    var columns = false
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ticks.indices, id: \.self) { index in
                if columns {
                    Text(ticks[index])
                        .frame(maxWidth: .infinity)
                } else {
                    if index > 0 {
                        Spacer(minLength: 8)
                    }
                    Text(ticks[index])
                }
            }
        }
        .font(font)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// A chart hidden from accessibility, its axes hidden too, with its own row of axis labels 2 pt under it — so the tree carries the labels and nothing of the plot but the room it takes.
struct PlottedChart<Plot: View>: View {
    let height: CGFloat
    let ticks: [String]
    var columns = false
    var font: Font = .caption
    @ViewBuilder let plot: Plot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            plot
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: height)
                .accessibilityHidden(true)
            TickRow(ticks: ticks, columns: columns, font: font)
        }
    }
}

/// A week's row under `Days afloat`: its name, then one dot per day of the week, filled for each day afloat. Only the name is read; the dots are hidden from accessibility.
struct DaysRow: View {
    let name: String
    let days: Int

    var body: some View {
        HStack {
            Text(name)
                .font(.footnote)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0 ..< 7, id: \.self) { day in
                    Circle()
                        .fill(day < days ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
        }
    }
}
