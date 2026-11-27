//
// Copyright © Agulhas Labs
//

import Foundation

/// What a walk that took a slim or stock decision records in the usage log: the verdict, and how much memory the device held once the walk had run.
///
/// The memory is best effort: a device that could not be measured leaves both figures `nil`, and a refused walk, which touched no device, never has them.
public struct SlimUsage: Codable, Equatable, Sendable {
    public let verdict: Verdict
    /// Processes the device held, or `nil` where it was not measured.
    public let processes: Int?
    /// The device's footprint in whole megabytes, or `nil` where it was not measured.
    public let footprintMB: Int?

    public init(verdict: Verdict, processes: Int? = nil, footprintMB: Int? = nil) {
        self.verdict = verdict
        self.processes = processes
        self.footprintMB = footprintMB
    }

    /// This usage with what the device held; the footprint is rounded to a whole number.
    public func measured(processes: Int, footprintMB: Double) -> SlimUsage {
        SlimUsage(verdict: verdict, processes: processes, footprintMB: Int(footprintMB.rounded()))
    }
}

public extension SlimUsage {
    /// How the decision came out.
    enum Verdict: String, Codable, Equatable, Sendable {
        /// The read-back confirmed the override.
        case slim
        /// The read-back timed out or failed.
        case slimUnverified
        /// The runtime did not apply the override.
        case notSlim
        /// The decision was stock, `--stock` putting things back included.
        case stock
        /// The walk was refused over `--slim` or `--stock` before any side effect.
        case refused
    }
}
