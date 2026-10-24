//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A crash report is read for its process and capture time from the second of its two JSON documents (SimWalk#176).
struct HostCrashReportTests {
    @Test
    func aHostReportIsReadForItsProcessPathAndCaptureTime() throws {
        let report = try #require(HostCrashReport.parse(fileName: "xctest-host.ips", Self.fixture("xctest-host")))

        #expect(report.fileName == "xctest-host.ips")
        #expect(report.processName == "xctest")
        #expect(report.processPath == "/private/var/folders/*/xctest")
        #expect(abs(report.capturedAt.timeIntervalSince1970 - 1_792_574_715.6053) < 0.001, "DateFormatter keeps milliseconds")
        #expect(!report.isInSimulator)
    }

    @Test
    func aReportFromInsideASimulatorSaysSo() throws {
        let report = try #require(HostCrashReport.parse(fileName: "xctest-simulator.ips", Self.fixture("xctest-simulator")))

        #expect(report.isInSimulator)
        #expect(report.processPath.hasSuffix("iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"), "the real shape: not under CoreSimulator")
        #expect(report.parentProcess == "launchd_sim")
        #expect(report.coalitionName == "com.apple.CoreSimulator.SimDevice.DEVICE")
    }

    /// Each marker is enough alone, and a path and parent that name neither stays on the Mac.
    @Test
    func eachSimulatorMarkerAloneMakesAReportSimulatorAndNoneMakesItHost() {
        let date = Date(timeIntervalSince1970: 0)
        let host = "/private/var/folders/*/xctest"
        func report(path: String = host, parent: String? = nil, coalition: String? = nil) -> HostCrashReport {
            HostCrashReport(fileName: "a.ips", processName: "xctest", processPath: path, parentProcess: parent, coalitionName: coalition, capturedAt: date)
        }

        #expect(report(path: "/Users/x/Library/Developer/CoreSimulator/Devices/D/data/xctest").isInSimulator)
        #expect(report(path: "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest").isInSimulator)
        #expect(report(parent: "launchd_sim").isInSimulator)
        #expect(report(coalition: "com.apple.CoreSimulator.SimDevice.DEVICE").isInSimulator)
        #expect(!report().isInSimulator)
        #expect(!report(parent: "sleep", coalition: "com.apple.Terminal").isInSimulator)
    }

    /// A header with no body, a body that is not JSON, and a capture time in another spelling are each evidence of nothing.
    @Test
    func anUnreadableReportIsNil() throws {
        let otherTime = #"{"name":"xctest"}"# + "\n" + #"{"procName":"xctest","procPath":"/x","captureTime":"21/10/2026 10:25"}"#

        #expect(try HostCrashReport.parse(fileName: "xctest-unreadable.ips", Self.fixture("xctest-unreadable")) == nil)
        #expect(HostCrashReport.parse(fileName: "a.ips", Data(#"{"name":"xctest"}"#.utf8)) == nil)
        #expect(HostCrashReport.parse(fileName: "a.ips", Data(otherTime.utf8)) == nil)
    }

    static func fixture(_ name: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "ips", subdirectory: "Fixtures/crash-reports"), sourceLocation: sourceLocation)
        return try Data(contentsOf: url)
    }
}
