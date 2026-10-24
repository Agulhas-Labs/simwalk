//
// Copyright © Agulhas Labs
//

import Foundation

/// Waits for a launched app's frame to show the orientation a state stated, turning away and back once if it does not (SimWalk#224).
///
/// A just-booted device can ignore or lag the first orientation set, so the frame read straight after the launch may still be the old one. A frame that already agrees (or cannot be judged) is answered at once with no wait; otherwise the frame is polled, then the device is turned to the opposite orientation and back once. The last frame read is answered, and the caller applies `OrientationCheck.refusal` to it.
public struct OrientationSettle {
    /// Seconds between two reads of the frame.
    public static let pollInterval: TimeInterval = 0.1
    /// Seconds the frame is polled before the turn away, and again after the turn back.
    public static let pollBudget: TimeInterval = 2

    /// The frame to hold to `stated`: read through `frame`, with `turn` and `wait` supplied by the caller so the core needs no device.
    public static func settledFrame(
        stated: Walkbook.Orientation,
        frame: () -> AXNode.Frame,
        turn: (Walkbook.Orientation) -> Void,
        wait: (TimeInterval) -> Void,
        turnsAway: Bool = true
    ) -> AXNode.Frame {
        var latest = polled(stated: stated, frame: frame, wait: wait)
        guard turnsAway, contradicts(latest, stated) else { return latest }
        turn(stated == .landscape ? .portrait : .landscape)
        turn(stated)
        latest = polled(stated: stated, frame: frame, wait: wait)
        return latest
    }

    /// Reads the frame, then re-reads every `pollInterval` until it agrees or `pollBudget` has been waited.
    private static func polled(stated: Walkbook.Orientation, frame: () -> AXNode.Frame, wait: (TimeInterval) -> Void) -> AXNode.Frame {
        var latest = frame()
        var waited: TimeInterval = 0
        while contradicts(latest, stated), waited < pollBudget {
            wait(pollInterval)
            waited += pollInterval
            latest = frame()
        }
        return latest
    }

    private static func contradicts(_ frame: AXNode.Frame, _ stated: Walkbook.Orientation) -> Bool {
        guard let shown = OrientationCheck.judged(frame) else { return false }
        return shown != stated
    }
}
