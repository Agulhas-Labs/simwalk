//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices

/// What a booted simulator holds in use, read for the usage log.
public struct SlimMemory: Equatable, Sendable {
    /// The device's reading, or `nil` when it is not booted; runs `ps` and `footprint` and takes about a second and a half.
    public static func measure(udid: String) throws -> Reading? {
        try DeviceMemory.measure(udid: udid).map { Reading(processes: $0.processes, footprintMB: $0.footprintMB) }
    }
}

public extension SlimMemory {
    /// The process count and footprint of one device.
    struct Reading: Equatable, Sendable {
        public let processes: Int
        public let footprintMB: Double

        public init(processes: Int, footprintMB: Double) {
            self.processes = processes
            self.footprintMB = footprintMB
        }
    }
}
