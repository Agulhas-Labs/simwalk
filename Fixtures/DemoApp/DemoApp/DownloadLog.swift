//
// Copyright © Agulhas Labs
//

import Foundation

/// The demo's download history, read from the bundled `downloads.csv`: one line per download, giving how many minutes before the moment the file is read it happened and its size in megabytes.
///
/// Two windows are computed at a given `now`. "Today" is the downloads since local midnight; "last 24 hours" is the downloads under 1,440 minutes old. `dataToday` is deliberately the sum over the **last 24 hours**, not today: its title says "today" but its figure is the rolling window. That ambiguity is the point of the example, since a value oracle that answers both windows shows which one the screen means.
struct DownloadLog {
    struct Download {
        let minutesAgo: Double
        let megabytes: Double
    }

    let downloads: [Download]
    let now: Date

    init(now: Date, bundle: Bundle = .main) {
        self.now = now
        guard let url = bundle.url(forResource: "downloads", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            downloads = []
            return
        }
        downloads = text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let fields = line.split(separator: ",")
            guard fields.count == 2, let minutes = Int(fields[0]), let size = Double(fields[1]) else { return nil }
            return Download(minutesAgo: Double(minutes), megabytes: size)
        }
    }

    private var today: [Download] {
        let midnight = Calendar.current.startOfDay(for: now)
        return downloads.filter { now.addingTimeInterval(-60 * $0.minutesAgo) >= midnight }
    }

    /// The number of downloads since local midnight.
    var downloadsToday: Int {
        today.count
    }

    /// The megabytes downloaded in the last 24 hours (not since midnight, whatever the title says).
    var dataToday: Double {
        downloads.filter { $0.minutesAgo < 1440 }.reduce(0) { $0 + $1.megabytes }
    }

    /// Today's megabytes over today's count; nil when nothing was downloaded today.
    var averageDownload: Double? {
        let entries = today
        guard !entries.isEmpty else { return nil }
        return entries.reduce(0) { $0 + $1.megabytes } / Double(entries.count)
    }
}
