//
// Copyright © Agulhas Labs
//

import Foundation

public extension CaptureManifest {
    /// What XCTest measured of a screen's route on a physical device, verbatim (SimWalk#67, M4; Brief "M4, performance on a device").
    ///
    /// **The figures come from their own launches, not the capture's.** A measure run terminates and launches the app, takes the route and waits, once per iteration, in a test of its own; the walk that took the captures ran separately. ``separateLaunches`` says so on every record, so a reader never mistakes a launch time for the launch the screenshot was taken in. It is always `true` when written; it is a field so that a record which one day is not from a separate launch cannot be mistaken for one that is.
    ///
    /// **What XCTest reported, and nothing it did not.** A metric that reported nothing is absent from ``metrics``, never a zero, and nothing here is converted: units are XCTest's (`s`, `kB`, `hitches`), because a figure read back in other units is a figure the record can no longer be checked against. ``Metric/median`` and the audit are where units are read. The app's CPU includes answering the runner's element queries for the route's steps, as on any XCUITest measurement.
    ///
    /// **Inside format 8**, as ``Motion`` is: a capture decodes leniently, so a reader that predates the key ignores it and loses only the record.
    struct Performance: Codable, Equatable, Sendable {
        /// How many iterations were recorded; the unrecorded warm-up run `measure` makes first is not counted.
        public var iterations: Int
        /// Whether the figures come from launches of their own rather than the one the captures were taken in; `true` whenever a record is written.
        public var separateLaunches: Bool
        /// Every metric that reported, in the order XCTest gave them.
        public var metrics: [Metric]

        public init(iterations: Int, separateLaunches: Bool = true, metrics: [Metric]) {
            self.iterations = iterations
            self.separateLaunches = separateLaunches
            self.metrics = metrics
        }

        /// The metric XCTest reported under `identifier`, or `nil` when it reported none.
        public func metric(_ identifier: String) -> Metric? {
            metrics.first { $0.identifier == identifier }
        }
    }
}

public extension CaptureManifest.Performance {
    /// One metric, as `xcresulttool get test-results metrics` names it.
    struct Metric: Codable, Equatable, Sendable {
        /// XCTest's identifier, such as `com.apple.dt.XCTMetric_CPU-com.example.app.time`; it embeds the app's bundle id for CPU and memory.
        public var identifier: String
        /// XCTest's display name, such as `Duration (ApplicationFirstFramePresentationResponsive)`.
        public var displayName: String
        /// XCTest's unit, as it spells it: `s`, `kB`, `kC`, `kI`, `hitches`, `fps`.
        public var unit: String
        /// XCTest's polarity, such as `prefers smaller`.
        public var polarity: String
        /// One figure per recorded iteration, in the unit above; never empty in a record the parse makes.
        public var measurements: [Double]

        public init(identifier: String, displayName: String, unit: String, polarity: String, measurements: [Double]) {
            self.identifier = identifier
            self.displayName = displayName
            self.unit = unit
            self.polarity = polarity
            self.measurements = measurements
        }

        /// The median of the measurements: the middle one, or the mean of the two middle ones; `nil` with none.
        ///
        /// **The median, not the mean**, because a launch is a handful of figures and the first of them is often cold: one slow iteration should not move the verdict the way it moves an average.
        public var median: Double? {
            guard !measurements.isEmpty else { return nil }
            let sorted = measurements.sorted()
            return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
        }
    }
}

public extension CaptureManifest {
    /// Whether this manifest is a physical device's walk, read from how the walk knew the app's build.
    ///
    /// **The most direct signal the manifest has.** A simulator walk hashes the installed app (`AppBuildIdentity.hash`), so its `appBuildHash` is a hash and its provenance absent; a device walk cannot read the phone's copy (SimWalk#116), so it records either the placeholder `device-unread` or, with `--app`, a hash taken on the Mac and `installed` as the provenance. `device.name` is no signal (a model name, `iPad17,3`, or a marketing name) and the UDID's shape is a convention of Apple's. Performance is recorded on a device only, so `performanceBudget` reads this to refuse a simulator bundle by name.
    var isDeviceWalk: Bool {
        appBuildProvenance == .installed || appBuildHash == AppBuildIdentity.unreadOnDevice
    }
}
