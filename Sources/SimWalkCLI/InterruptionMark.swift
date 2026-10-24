//
// Copyright © Agulhas Labs
//

import Foundation

/// The offset on the walk's clock (``WalkTelemetry/elapsedMilliseconds()``) at which the walk's interruption was heard, which an interrupted `walk.parallel` line ends at (SimWalk#189).
///
/// Read by a cancel handler registered ahead of the one that stops the runners and gives the devices back: handlers run in registration order, and the line's own handler runs after that one, so a reading taken there would count deleting the walk's clones.
///
/// Unchecked because the offset is only touched under `lock`; the telemetry is only read.
final class InterruptionMark: @unchecked Sendable {
    private let telemetry: WalkTelemetry?
    private let lock = NSLock()
    private var offset: Int?

    /// With no telemetry there is no clock, and the mark stays `nil`.
    init(telemetry: WalkTelemetry?) {
        self.telemetry = telemetry
    }

    /// Reads the walk's clock; once a reading is taken, a later call keeps it.
    ///
    /// Read under the lock, so a reading is stored as it is taken: a writer that reads its own `now` and then finds no mark ended before the cancel was heard.
    func mark() {
        lock.withLock { offset = offset ?? telemetry?.elapsedMilliseconds() }
    }

    /// The reading ``mark()`` took; `nil` before it ran, or when it ran before the walk began.
    var milliseconds: Int? {
        lock.withLock { offset }
    }
}
