//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

struct XCTestCrashLogTests {
    /// `log show --style ndjson` output as macOS prints it (trimmed to the fields read): three ReportCrash events for `xctest`, one for another process, and the summary line.
    static var sample: String {
        """
        {"timestamp":"2026-10-22 08:14:18.891448+0100","eventMessage":"logGenerationTiming: sending CA event for xctest[309] elapsedTime=0.086","processImagePath":"\\/System\\/Library\\/CoreServices\\/ReportCrash"}
        {"timestamp":"2026-10-22 08:14:20.000000+0100","eventMessage":"logGenerationTiming: sending CA event for Finder[309] elapsedTime=0.100","processImagePath":"\\/System\\/Library\\/CoreServices\\/ReportCrash"}
        {"timestamp":"2026-10-22 08:14:26.838938+0100","eventMessage":"logGenerationTiming: sending CA event for xctest[309] elapsedTime=0.114","processImagePath":"\\/System\\/Library\\/CoreServices\\/ReportCrash"}
        {"timestamp":"2026-10-22 08:14:29.927062+0100","eventMessage":"logGenerationTiming: sending CA event for xctest[309] elapsedTime=0.073","processImagePath":"\\/System\\/Library\\/CoreServices\\/ReportCrash"}
        {"count":3,"finished":1}
        """
    }

    /// 2026-10-22 08:13:07 BST.
    private static let start = Date(timeIntervalSince1970: 1_792_653_187)

    /// The crashes of a process named `xctest` are counted, not another process's and not the summary line.
    @Test
    func everyXctestCrashInTheWindowIsCounted() {
        let window = DateInterval(start: Self.start, end: Self.start.addingTimeInterval(113))

        #expect(XCTestCrashLog.parse(ndjson: Self.sample, window: window) == XCTestCrashLog(crashes: 3))
    }

    /// A crash after the window's end is not counted.
    @Test
    func aCrashAfterTheWindowEndsIsNotCounted() {
        let window = DateInterval(start: Self.start, end: Self.start.addingTimeInterval(80))

        #expect(XCTestCrashLog.parse(ndjson: Self.sample, window: window) == XCTestCrashLog(crashes: 2))
    }

    /// Output with nothing decodable in it says nothing, which is not the same as no crashes.
    @Test(arguments: ["", "not json\nstill not"])
    func outputWithNoDecodableLineGivesNothing(output: String) {
        let window = DateInterval(start: Self.start, end: Self.start.addingTimeInterval(113))

        #expect(XCTestCrashLog.parse(ndjson: output, window: window) == nil)
    }

    /// Decodable output with no matching event is a count of zero.
    @Test
    func onlyTheSummaryLineIsZeroCrashes() {
        let window = DateInterval(start: Self.start, end: Self.start.addingTimeInterval(113))

        #expect(XCTestCrashLog.parse(ndjson: #"{"count":0,"finished":1}"#, window: window) == XCTestCrashLog(crashes: 0))
    }
}
