//
// Copyright © Agulhas Labs
//

import SwiftUI

/// The usage screen: three figures drawn from the bundled download log, computed when the screen appears and formatted in the current locale.
///
/// "Data today" is the rolling 24 hours, not today (see `DownloadLog`); `downloads-oracle.sh` answers both windows so a walk shows which one the screen drew. The clock is read in `onAppear`, not in `init`: the Account list builds its `NavigationLink`'s destination whenever its body runs, so a clock read there would date the figures from launch rather than from the moment the screen is shown and captured.
struct UsageScreen: View {
    @State private var log: DownloadLog?

    private static let megabytes = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

    var body: some View {
        List {
            row("Downloads today", log.map { $0.downloadsToday.formatted() }, id: "downloads-today")
            row("Data today", log.map { $0.dataToday.formatted(Self.megabytes) + " MB" }, id: "data-today")
            row("Average download", log.map { $0.averageDownload.map { $0.formatted(Self.megabytes) + " MB" } ?? "—" }, id: "average-download")
        }
        .accessibilityIdentifier("usage-screen")
        .navigationTitle("Usage")
        .onAppear { log = DownloadLog(now: Date()) }
    }

    private func row(_ title: LocalizedStringKey, _ value: String?, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value ?? "")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(id)
        }
    }
}
