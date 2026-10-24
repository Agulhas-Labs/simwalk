//
// Copyright © Agulhas Labs
//

import Foundation

/// The crashes of a process named `xctest` the macOS system log records in a window, whether or not macOS saved a report for them (SimWalk#191).
///
/// macOS keeps at most 25 of one process's crash reports and logs `Report … not saved because the limit of 25 logs has been reached` for the rest, yet XCUITest still blames a crash it was told of. ReportCrash logs `logGenerationTiming: sending CA event for xctest[…]` for each crash it handled; this reads that line from `log show --style ndjson` output. The line names no path, so it cannot tell a host process from a simulator one: it is evidence for the answer's line, never an excuse. Pure: the output and the window in, a count out.
public struct XCTestCrashLog: Equatable, Sendable {
    /// How many crashes of a process named `xctest` the log records in the window.
    public let crashes: Int

    public init(crashes: Int) {
        self.crashes = crashes
    }

    /// The `log show` predicate: ReportCrash's line for a crash of a process named `xctest`.
    public static var predicate: String {
        #"process == "ReportCrash" AND eventMessage CONTAINS "sending CA event for xctest[""#
    }

    private static var messagePrefix: String {
        "logGenerationTiming: sending CA event for xctest["
    }

    /// The arguments `log` is run with to read `window`: start rounded down and end rounded up to the second, in UTC.
    public static func arguments(window: DateInterval) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        let start = Date(timeIntervalSince1970: window.start.timeIntervalSince1970.rounded(.down))
        let end = Date(timeIntervalSince1970: window.end.timeIntervalSince1970.rounded(.up))
        return ["show", "--style", "ndjson", "--start", formatter.string(from: start), "--end", formatter.string(from: end), "--predicate", predicate]
    }

    /// The crashes in `ndjson` whose timestamp is inside `window`; `nil` when the output holds no decodable line at all.
    public static func parse(ndjson: String, window: DateInterval) -> XCTestCrashLog? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        var decoded = false
        var crashes = 0
        for line in ndjson.split(whereSeparator: \.isNewline) {
            guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)) else { continue }
            decoded = true
            guard let message = event.eventMessage, message.hasPrefix(messagePrefix),
                  let stamp = event.timestamp, let date = formatter.date(from: stamp),
                  window.contains(date)
            else { continue }
            crashes += 1
        }
        return decoded ? XCTestCrashLog(crashes: crashes) : nil
    }
}

extension XCTestCrashLog {
    private struct Event: Decodable {
        let eventMessage: String?
        let timestamp: String?
    }
}
