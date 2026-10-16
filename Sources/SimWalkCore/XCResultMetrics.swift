//
// Copyright © Agulhas Labs
//

import Foundation

/// Reads one test's metrics out of `xcrun xcresulttool get test-results metrics --path <xcresult>` (SimWalk#67, M4).
///
/// **Pure on purpose**: the host runs `xcresulttool` and hands the bytes here, so what a result bundle's JSON means is decided where `swift test` can hold it, not in the host's shell code.
///
/// **The test is selected by identifier** (the runner's is `WalkRunner/testMeasure()`), and a JSON without it, or with more than one run of it, is refused rather than guessed at: a result bundle is one `measure` run's, so two runs of the test would be figures of two launches blended into one record.
///
/// **Every metric is kept verbatim**; only one that reported no measurements is left out, since "a metric that reported nothing is absent, never a zero".
public struct XCResultMetrics {
    /// The record for `testIdentifier` in `json`, recorded over `iterations` iterations.
    public static func performance(from json: Data, test testIdentifier: String, iterations: Int) throws -> CaptureManifest.Performance {
        let tests: [Test]
        do {
            tests = try JSONDecoder().decode([Test].self, from: json)
        } catch {
            throw Failure.undecodable(String(describing: error))
        }
        let runs = tests.filter { $0.testIdentifier == testIdentifier }.flatMap(\.testRuns)
        guard let run = runs.first else {
            throw Failure.testNotFound(identifier: testIdentifier, found: tests.map(\.testIdentifier))
        }
        guard runs.count == 1 else {
            throw Failure.multipleRuns(identifier: testIdentifier, count: runs.count)
        }
        let metrics = run.metrics.compactMap { metric -> CaptureManifest.Performance.Metric? in
            guard let measurements = metric.measurements, !measurements.isEmpty else { return nil }
            return CaptureManifest.Performance.Metric(
                identifier: metric.identifier,
                displayName: metric.displayName ?? metric.identifier,
                unit: metric.unitOfMeasurement ?? "",
                polarity: metric.polarity ?? "",
                measurements: measurements
            )
        }
        guard !metrics.isEmpty else {
            throw Failure.noMetrics(identifier: testIdentifier)
        }
        return CaptureManifest.Performance(iterations: iterations, metrics: metrics)
    }
}

public extension XCResultMetrics {
    /// Why a record could not be made from the JSON.
    enum Failure: Error, Equatable, CustomStringConvertible {
        /// The bytes are not the array `xcresulttool` prints.
        case undecodable(String)
        /// No test with the identifier is in the JSON; `found` is what it held.
        case testNotFound(identifier: String, found: [String])
        /// The test appears in more than one run, `count` of them.
        case multipleRuns(identifier: String, count: Int)
        /// The test ran but no metric reported a measurement.
        case noMetrics(identifier: String)

        public var description: String {
            switch self {
            case let .undecodable(reason):
                "the result bundle's metrics are not the JSON xcresulttool prints: \(reason)"
            case let .testNotFound(identifier, found):
                "the result bundle has no metrics for \(identifier) (it holds \(found.isEmpty ? "no tests" : found.joined(separator: ", ")))"
            case let .multipleRuns(identifier, count):
                "the result bundle holds \(count) runs of \(identifier); one measure run's figures are expected"
            case let .noMetrics(identifier):
                "\(identifier) ran but reported no measurements"
            }
        }
    }
}

private extension XCResultMetrics {
    struct Test: Decodable {
        let testIdentifier: String
        let testRuns: [Run]
    }

    struct Run: Decodable {
        let metrics: [Metric]
    }

    struct Metric: Decodable {
        let identifier: String
        let displayName: String?
        let unitOfMeasurement: String?
        let polarity: String?
        let measurements: [Double]?
    }
}
