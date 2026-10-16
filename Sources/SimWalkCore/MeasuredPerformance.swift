//
// Copyright © Agulhas Labs
//

import Foundation

/// The performance records a device walk's measure runs produced, by screen id and then state slug (SimWalk#67, M4): what the host passes the walk's runner, which files each on its capture.
///
/// **The manifest stays the runner's single write** (Brief "M4, performance on a device", ruling 4): the host does not edit the bundle after the copy, so manifest-last holds and the nonce check covers the record. The host encodes this as ``hostEnvironmentKey`` and the runner reads it back through ``read(from:)``; both ends name the key here, as ``MotionOptIn`` does.
///
/// Encoded as a plain JSON object, `{"<screen id>": {"<state slug>": <Performance>}}`.
public struct MeasuredPerformance: Codable, Equatable, Sendable {
    private var records: [String: [String: CaptureManifest.Performance]]

    public init() {
        records = [:]
    }

    public init(from decoder: Decoder) throws {
        records = try decoder.singleValueContainer().decode([String: [String: CaptureManifest.Performance]].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(records)
    }

    /// Files `performance` as `run`'s screen and state's record.
    public mutating func record(_ performance: CaptureManifest.Performance, for run: MeasureRun) {
        records[run.screenID, default: [:]][run.stateSlug] = performance
    }

    /// The record for a screen's state, or `nil` when it was not measured or its run failed.
    public func performance(screenID: String, stateSlug: String) -> CaptureManifest.Performance? {
        records[screenID]?[stateSlug]
    }

    public var isEmpty: Bool {
        records.isEmpty
    }

    /// The JSON the host passes as ``hostEnvironmentKey``.
    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }

    /// The records the runner's environment carries: none when the variable is absent.
    ///
    /// - Throws: the decoding error when it is present and is not this type's JSON. The host wrote it, so a value the runner cannot read is a broken walk, never a walk without figures.
    public static func read(from environment: [String: String]) throws -> MeasuredPerformance {
        guard let json = environment[environmentKey] else { return MeasuredPerformance() }
        return try JSONDecoder().decode(MeasuredPerformance.self, from: Data(json.utf8))
    }

    /// The runner-side variable.
    public static var environmentKey: String {
        "SIMWALK_PERFORMANCE_JSON"
    }

    /// The variable the host sets, which `xcodebuild` forwards to the test process as ``environmentKey``.
    public static var hostEnvironmentKey: String {
        "TEST_RUNNER_" + environmentKey
    }
}
