//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// A heartbeat schedule fired by hand: the beat it was handed, its interval, and, for each stop, whether `exit.json` was already down.
final class ScriptedHeartbeatSchedule: @unchecked Sendable {
    private(set) var interval: TimeInterval?
    private(set) var stops: [Stop] = []
    private var beat: (@Sendable () -> Void)?
    private let channel: LiveSessionChannel

    init(channel: LiveSessionChannel) {
        self.channel = channel
    }

    func schedule(_ interval: TimeInterval, _ beat: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        self.interval = interval
        self.beat = beat
        return { [self] in
            stops.append(FileManager.default.fileExists(atPath: channel.layout.exit.path) ? .afterExitRecord : .beforeExitRecord)
        }
    }

    /// One tick of the timer.
    func fire() {
        beat?()
    }
}

extension ScriptedHeartbeatSchedule {
    /// Where a stop came relative to the exit record.
    enum Stop: Equatable {
        case beforeExitRecord, afterExitRecord
    }
}
