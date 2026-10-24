//
// Copyright © Agulhas Labs
//

import Foundation

/// A crash report the system wrote for an app on a simulator: where it is and when the app crashed (SimWalk#243).
///
/// A simulator's apps are Mac processes, so their crash reports land in the Mac's own `~/Library/Logs/DiagnosticReports` as `.ips` files: a one-line JSON header naming the `bundleID` and the crash's `timestamp`, then a JSON body whose `procPath` runs through the device's `CoreSimulator/Devices/<UDID>/` directory. That path is what tells one device's crash from the same app's on another.
public struct AppCrashReport: Equatable, Sendable {
    public let path: URL
    public let crashedAt: Date

    public init(path: URL, crashedAt: Date) {
        self.path = path
        self.crashedAt = crashedAt
    }

    /// The newest report in `directory` of `bundleID` crashing on the simulator `udid`, at or after `since` when given; `nil` when there is none, or the directory cannot be read.
    public static func latest(bundleID: String, udid: String, since: Date?, in directory: URL) -> AppCrashReport? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "ips" }
            .compactMap { report(at: $0, bundleID: bundleID, udid: udid) }
            .filter { report in since.map { report.crashedAt >= $0 } ?? true }
            .max { $0.crashedAt < $1.crashedAt }
    }

    /// The report at `file` when it is of `bundleID` on `udid` and its crash time reads.
    private static func report(at file: URL, bundleID: String, udid: String) -> AppCrashReport? {
        guard let data = try? Data(contentsOf: file), let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let header = try? JSONDecoder().decode(Header.self, from: data[..<newline]),
              header.bundleID == bundleID,
              let body = try? JSONDecoder().decode(Body.self, from: data[data.index(after: newline)...]),
              body.procPath.contains("/Devices/\(udid)/"),
              let crashedAt = timestampFormat.date(from: header.timestamp)
        else {
            return nil
        }
        return AppCrashReport(path: file, crashedAt: crashedAt)
    }

    /// The header's `timestamp`, `2026-10-23 23:32:32.00 +0100`.
    private static var timestampFormat: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        return formatter
    }
}

extension AppCrashReport {
    private struct Header: Decodable {
        let bundleID: String
        let timestamp: String
    }

    private struct Body: Decodable {
        let procPath: String
    }
}
