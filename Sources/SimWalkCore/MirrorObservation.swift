//
// Copyright © Agulhas Labs
//

import Foundation

/// What one mirror step saw: the screen before the action, and the read it settled on after.
///
/// **Plain values, no clock and no files of its own.** The driver's runner fills it; MirrorObservationSummary renders it, so a test scripts both ends without a Mac.
public struct MirrorObservation: Equatable, Sendable {
    /// What the step did, `nil` for a plain `read`.
    public let action: MirrorAction?
    /// The window as it was when the step ran.
    public let window: MirrorWindowFrame
    /// The read before the action, `nil` for a `read`.
    public let before: MirrorRead?
    /// The read the step is answered with; its `path` is the kept capture.
    public let read: MirrorRead
    /// Why the answer is qualified, `nil` when the screen settled.
    public let reason: MirrorSettle.Reason?
    /// When the action was posted — for a `read`, when the reading began.
    public let eventAt: Date
    /// How many reads the settle loop took.
    public let reads: Int
    /// The bound the settle loop ran to, in milliseconds.
    public let boundMilliseconds: Int

    public init(action: MirrorAction?, window: MirrorWindowFrame, before: MirrorRead?, read: MirrorRead, reason: MirrorSettle.Reason?, eventAt: Date, reads: Int, boundMilliseconds: Int) {
        self.action = action
        self.window = window
        self.before = before
        self.read = read
        self.reason = reason
        self.eventAt = eventAt
        self.reads = reads
        self.boundMilliseconds = boundMilliseconds
    }

    /// The action's label, or `read`.
    public var label: String {
        action?.label ?? "read"
    }

    /// Whole milliseconds from the event to the served read's capture.
    public var millisecondsToRead: Int {
        Int((read.capturedAt.timeIntervalSince(eventAt) * 1000).rounded())
    }
}
