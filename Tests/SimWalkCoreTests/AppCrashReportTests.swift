//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// Finding the crash report of an app on one simulator among the Mac's own (SimWalk#243).
struct AppCrashReportTests {
    /// The newest report of the app on the device is the one found: not an older one, not the app's on another device, not another app's, not a file that is no crash report.
    @Test
    func theNewestReportOfTheAppOnTheDeviceIsFound() throws {
        let directory = try TemporaryDirectory()
        try Self.write("older.ips", bundleID: "com.example.live", udid: "UDID-1", at: "2026-10-23 22:00:00.00 +0100", in: directory.url)
        try Self.write("newest.ips", bundleID: "com.example.live", udid: "UDID-1", at: "2026-10-23 23:32:32.00 +0100", in: directory.url)
        try Self.write("other-device.ips", bundleID: "com.example.live", udid: "UDID-2", at: "2026-10-23 23:40:00.00 +0100", in: directory.url)
        try Self.write("other-app.ips", bundleID: "com.example.other", udid: "UDID-1", at: "2026-10-23 23:40:00.00 +0100", in: directory.url)
        try Data("not json\n{}".utf8).write(to: directory.url.appendingPathComponent("torn.ips"))

        let found = AppCrashReport.latest(bundleID: "com.example.live", udid: "UDID-1", since: nil, in: directory.url)

        #expect(found?.path.lastPathComponent == "newest.ips")
        #expect(found?.crashedAt == Date(timeIntervalSince1970: 1_792_794_752))
    }

    /// A report from before `since` (the device's boot) is not why the app is not running now; a missing directory finds nothing.
    @Test
    func aReportBeforeSinceOrNoDirectoryFindsNothing() throws {
        let directory = try TemporaryDirectory()
        try Self.write("old.ips", bundleID: "com.example.live", udid: "UDID-1", at: "2026-10-23 22:00:00.00 +0100", in: directory.url)

        #expect(AppCrashReport.latest(bundleID: "com.example.live", udid: "UDID-1", since: Date(timeIntervalSince1970: 1_792_794_752), in: directory.url) == nil)
        #expect(AppCrashReport.latest(bundleID: "com.example.live", udid: "UDID-1", since: nil, in: directory.url.appendingPathComponent("absent")) == nil)
    }

    /// Writes a report shaped as the system's: a one-line JSON header, then the JSON body.
    static func write(_ name: String, bundleID: String, udid: String, at timestamp: String, in directory: URL) throws {
        let header = #"{"app_name":"Live","timestamp":"\#(timestamp)","bundleID":"\#(bundleID)","bug_type":"309"}"#
        let body = #"{"procPath":"/Users/USER/Library/Developer/CoreSimulator/Devices/\#(udid)/data/Containers/Bundle/Application/X/Live.app/Live","exception":{"type":"EXC_CRASH","signal":"SIGSEGV"}}"#
        try Data((header + "\n" + body).utf8).write(to: directory.appendingPathComponent(name))
    }
}
