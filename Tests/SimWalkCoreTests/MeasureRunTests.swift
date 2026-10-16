//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// What the host and the runner agree on for a device walk's measure runs (SimWalk#67, M4): the runs a walkbook asks for, the variables that name one, the records handed to the walk, and the answer's line.
struct MeasureRunTests {
    private static func book(_ json: String) throws -> Walkbook {
        try WalkbookLoader.load(from: Data(json.utf8), source: "test")
    }

    @Test
    func eachStateOfEachMeasuredScreenIsARunInWalkbookOrder() throws {
        let book = try Self.book(#"{"name":"w","appBundleID":"x.y","screens":[{"id":"a","route":[{"tab":{"label":"A"}}],"states":[{"theme":"light"}]},{"id":"b","route":[{"tab":{"label":"B"}}],"states":[{"theme":"light"},{"theme":"dark"}],"measure":{"iterations":5}}]}"#)

        let runs = MeasureRun.runs(for: book)

        #expect(runs == [MeasureRun(screenID: "b", stateSlug: "light", iterations: 5), MeasureRun(screenID: "b", stateSlug: "dark", iterations: 5)])
    }

    @Test
    func theRunnerReadsBackTheRunTheHostNamed() throws {
        let run = MeasureRun(screenID: "general", stateSlug: "dark", iterations: 3)
        let stripped = Dictionary(uniqueKeysWithValues: run.hostEnvironment.map { (String($0.key.dropFirst("TEST_RUNNER_".count)), $0.value) })

        #expect(run.hostEnvironment.keys.allSatisfy { $0.hasPrefix("TEST_RUNNER_") })
        #expect(try MeasureRun.named(in: stripped) == run)
        #expect(try MeasureRun.named(in: [:]) == nil)
        #expect(throws: MeasureRun.Incomplete.self) {
            try MeasureRun.named(in: ["SIMWALK_MEASURE_SCREEN": "general", "SIMWALK_MEASURE_STATE": "dark"])
        }
    }

    @Test
    func theRecordsRoundTripThroughTheEnvironmentKeyedByScreenThenState() throws {
        let record = CaptureManifest.Performance(iterations: 1, metrics: [CaptureManifest.Performance.Metric(identifier: "m", displayName: "M", unit: "s", polarity: "prefers smaller", measurements: [0.5])])
        var measured = MeasuredPerformance()
        measured.record(record, for: MeasureRun(screenID: "general", stateSlug: "light", iterations: 1))

        let json = try measured.json()
        let read = try MeasuredPerformance.read(from: [MeasuredPerformance.environmentKey: json])

        #expect(MeasuredPerformance.hostEnvironmentKey == "TEST_RUNNER_" + MeasuredPerformance.environmentKey)
        #expect(json.hasPrefix(#"{"general":{"light":{"#))
        #expect(read.performance(screenID: "general", stateSlug: "light") == record)
        #expect(read.performance(screenID: "general", stateSlug: "dark") == nil)
        #expect(try MeasuredPerformance.read(from: [:]).isEmpty)
        #expect(throws: DecodingError.self) {
            try MeasuredPerformance.read(from: [MeasuredPerformance.environmentKey: "[]"])
        }
    }

    @Test
    func theSummaryNamesOnlyTheFiguresPresentAsMedians() {
        let metric = { (id: String, unit: String, values: [Double]) in
            CaptureManifest.Performance.Metric(identifier: "com.apple.dt.XCTMetric_" + id, displayName: id, unit: unit, polarity: "prefers smaller", measurements: values)
        }
        let full = CaptureManifest.Performance(iterations: 3, metrics: [
            metric("ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration", "s", [0.307, 0.298, 0.41]),
            metric("CPU-x.y.time", "s", [1.349, 1.347, 1.32]),
            metric("Memory-x.y.physical_peak", "kB", [65372.808, 63963.784, 63619.696]),
            metric("OSSignpost-NavigationTransition.animation.hitch.number", "hitches", [0, 0, 0]),
        ])
        let launchOnly = CaptureManifest.Performance(iterations: 1, metrics: [metric("ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration", "s", [0.5])])

        #expect(full.summary(appBundleID: "x.y") == "3 iterations, launch 307 ms, cpu 1347 ms, memory peak 62.5 MB, transition hitches 0")
        #expect(launchOnly.summary(appBundleID: "x.y") == "1 iteration, launch 500 ms")
    }
}
