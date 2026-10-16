//
// Copyright © Agulhas Labs
//

import Foundation

/// The four figures a performance record is read for (SimWalk#67, M4) — by `bundle audit`'s `performanceBudget` and by a device walk's `measured:` line — so the metric each is read from is named once.
///
/// **Units are converted here, on reading, and nowhere in the record**: XCTest's seconds become milliseconds and its kilobytes become megabytes (1 MB = 1024 kB, as Instruments counts), so the manifest keeps what XCTest said.
public enum PerformanceFigure: CaseIterable, Sendable {
    /// To the first responsive frame; `AppLaunch.duration` measures something else, so it is no stand-in.
    case launch
    case cpuTime
    case memoryPeak
    case transitionHitches

    /// The metric XCTest reports the figure under; CPU and memory embed the app's bundle id.
    public func identifier(appBundleID: String) -> String {
        let prefix = "com.apple.dt.XCTMetric_"
        return switch self {
        case .launch: "\(prefix)ApplicationLaunch-ApplicationFirstFramePresentationResponsive.duration"
        case .cpuTime: "\(prefix)CPU-\(appBundleID).time"
        case .memoryPeak: "\(prefix)Memory-\(appBundleID).physical_peak"
        case .transitionHitches: "\(prefix)OSSignpost-NavigationTransition.animation.hitch.number"
        }
    }

    /// The unit the figure is read in.
    public var unit: String {
        switch self {
        case .launch, .cpuTime: "ms"
        case .memoryPeak: "MB"
        case .transitionHitches: "hitches"
        }
    }

    /// The median of the figure's measurements in ``unit``, and how many measurements it is of; `nil` when the metric is absent, reported no measurement, or is in a unit other than XCTest's for it (a figure in the wrong unit is not a figure).
    public func median(in performance: CaptureManifest.Performance, appBundleID: String) -> (value: Double, count: Int)? {
        guard let metric = performance.metric(identifier(appBundleID: appBundleID)), metric.unit == reportedUnit, let median = metric.median else { return nil }
        return (median * scale, metric.measurements.count)
    }

    /// The unit XCTest reports the metric in.
    private var reportedUnit: String {
        switch self {
        case .launch, .cpuTime: "s"
        case .memoryPeak: "kB"
        case .transitionHitches: "hitches"
        }
    }

    private var scale: Double {
        switch self {
        case .launch, .cpuTime: 1000
        case .memoryPeak: 1 / 1024
        case .transitionHitches: 1
        }
    }
}

public extension CaptureManifest.Performance {
    /// One line of the record's medians, for a device walk's answer: `3 iterations, launch 307 ms, cpu 1347 ms, memory peak 62.5 MB, transition hitches 0`.
    ///
    /// **Only the figures present**: a metric that reported nothing is left out, never printed as a zero.
    func summary(appBundleID: String) -> String {
        let names: [(PerformanceFigure, String)] = [(.launch, "launch"), (.cpuTime, "cpu"), (.memoryPeak, "memory peak"), (.transitionHitches, "transition hitches")]
        let figures = names.compactMap { figure, name -> String? in
            guard let median = figure.median(in: self, appBundleID: appBundleID) else { return nil }
            let unit = figure == .transitionHitches ? "" : " \(figure.unit)"
            return "\(name) \(Self.rendered(median.value, as: figure))\(unit)"
        }
        return (["\(iterations) iteration\(iterations == 1 ? "" : "s")"] + figures).joined(separator: ", ")
    }

    /// Milliseconds whole, megabytes to one decimal, hitches whole unless XCTest gave a fraction (and unitless, as the name says them).
    private static func rendered(_ value: Double, as figure: PerformanceFigure) -> String {
        switch figure {
        case .launch, .cpuTime: String(Int(value.rounded()))
        case .memoryPeak: String(format: "%.1f", value)
        case .transitionHitches:
            if value.rounded() == value {
                String(Int(value))
            } else {
                String(format: "%.1f", value)
            }
        }
    }
}
