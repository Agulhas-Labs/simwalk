//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The parse of `xcresulttool get test-results metrics` into a performance record (SimWalk#67, M4), over output trimmed from a real device run.
struct XCResultMetricsTests {
    static var test: String {
        "WalkRunner/testMeasure()"
    }

    /// One test, one run, two metrics and one that reported nothing — the shape `xcresulttool` printed for an iPad.
    static func json(test: String = Self.test, runs: Int = 1, extra: String = "") -> Data {
        let run = """
        {"device": {"deviceId": "00008000-0000000000000000", "deviceName": "iPad"}, "metrics": [
        {"baselineAverage": 0, "baselineName": "", "displayName": "Duration (ApplicationFirstFramePresentationResponsive)", "identifier": "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration", "maxPercentRegression": 10, "maxPercentRelativeStandardDeviation": 10, "maxRegression": 0, "maxStandardDeviation": 10, "measurements": [0.307, 0.298, 0.41], "polarity": "prefers smaller", "unitOfMeasurement": "s"},
        {"displayName": "Number of Hitches (NavigationTransition)", "identifier": "com.apple.dt.XCTMetric_OSSignpost-NavigationTransition.animation.hitch.number", "measurements": [0, 0, 0], "polarity": "prefers smaller", "unitOfMeasurement": "hitches", "baselineAverage": 0, "baselineName": ""}\(extra)
        ], "testPlanConfiguration": {"configurationId": "1", "configurationName": "Test Scheme Action"}}
        """
        let runList = Array(repeating: run, count: runs).joined(separator: ",")
        return Data("""
        [{"testIdentifier": "\(test)", "testIdentifierURL": "test://x", "testRuns": [\(runList)]}]
        """.utf8)
    }

    @Test
    func everyMetricIsKeptVerbatimInXCTestsOrderAndUnits() throws {
        let record = try XCResultMetrics.performance(from: Self.json(), test: Self.test, iterations: 3)

        #expect(record.iterations == 3)
        #expect(record.separateLaunches)
        #expect(record.metrics.map(\.identifier) == [
            "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration",
            "com.apple.dt.XCTMetric_OSSignpost-NavigationTransition.animation.hitch.number",
        ])
        #expect(record.metrics[0] == CaptureManifest.Performance.Metric(
            identifier: "com.apple.dt.XCTMetric_ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration",
            displayName: "Duration (ApplicationFirstFramePresentationResponsive)",
            unit: "s",
            polarity: "prefers smaller",
            measurements: [0.307, 0.298, 0.41]
        ))
        #expect(record.metrics[1].unit == "hitches")
        #expect(record.metrics[1].measurements == [0, 0, 0])
    }

    @Test
    func aMetricThatReportedNothingIsAbsentAndNeverAZero() throws {
        let silent = #",{"displayName": "Frame Count", "identifier": "x.frames", "measurements": [], "polarity": "prefers larger", "unitOfMeasurement": "frames"},{"displayName": "No key", "identifier": "x.none"}"#
        let record = try XCResultMetrics.performance(from: Self.json(extra: silent), test: Self.test, iterations: 3)

        #expect(record.metric("x.frames") == nil)
        #expect(record.metric("x.none") == nil)
        #expect(record.metrics.count == 2)
    }

    @Test
    func aJSONWithoutTheTestIsRefusedNamingWhatItHeld() {
        let thrown = #expect(throws: XCResultMetrics.Failure.self) {
            try XCResultMetrics.performance(from: Self.json(test: "Other/testX()"), test: Self.test, iterations: 3)
        }

        #expect(thrown == .testNotFound(identifier: Self.test, found: ["Other/testX()"]))
        #expect(thrown?.description.contains("Other/testX()") == true)
    }

    @Test
    func moreThanOneRunOfTheTestIsRefused() {
        let thrown = #expect(throws: XCResultMetrics.Failure.self) {
            try XCResultMetrics.performance(from: Self.json(runs: 2), test: Self.test, iterations: 3)
        }

        #expect(thrown == .multipleRuns(identifier: Self.test, count: 2))
    }

    @Test
    func aTestThatReportedNoMetricsAndNonsenseAreRefused() {
        let empty = Data(#"[{"testIdentifier": "WalkRunner/testMeasure()", "testRuns": [{"metrics": []}]}]"#.utf8)

        #expect(throws: XCResultMetrics.Failure.noMetrics(identifier: Self.test)) {
            try XCResultMetrics.performance(from: empty, test: Self.test, iterations: 3)
        }
        #expect(throws: XCResultMetrics.Failure.self) {
            try XCResultMetrics.performance(from: Data("{}".utf8), test: Self.test, iterations: 3)
        }
    }

    @Test
    func theMedianIsTheMiddleFigureOrTheMeanOfTheMiddleTwo() {
        func metric(_ values: [Double]) -> CaptureManifest.Performance.Metric {
            CaptureManifest.Performance.Metric(identifier: "m", displayName: "m", unit: "s", polarity: "", measurements: values)
        }

        #expect(metric([0.41, 0.298, 0.307]).median == 0.307)
        #expect(metric([1, 2, 3, 10]).median == 2.5)
        #expect(metric([]).median == nil)
    }

    @Test
    func aCapturesPerformanceRoundTripsThroughTheManifestAndIsAbsentWhenNotMeasured() throws {
        let record = try XCResultMetrics.performance(from: Self.json(), test: Self.test, iterations: 3)
        let measured = CaptureManifest.StateCapture(screenID: "about", state: Walkbook.CaptureState(theme: .light), performance: record)
        let bare = CaptureManifest.StateCapture(screenID: "about", state: Walkbook.CaptureState(theme: .light))

        let decoded = try JSONDecoder().decode(CaptureManifest.StateCapture.self, from: JSONEncoder().encode(measured))
        let bareJSON = try String(decoding: JSONEncoder().encode(bare), as: UTF8.self)

        #expect(decoded.performance == record)
        #expect(!bareJSON.contains("performance"))
        #expect(try JSONDecoder().decode(CaptureManifest.StateCapture.self, from: Data(bareJSON.utf8)).performance == nil)
    }
}
