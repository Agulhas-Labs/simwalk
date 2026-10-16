//
// Copyright © Agulhas Labs
//

import Foundation

/// Decides, read by read, when a step on the mirrored phone may be answered.
///
/// **Modelled on `SettleTracker`, and in the core for the same reason: it is the part a test can reach.** The driver keeps the I/O (capture, recognise, wait) and asks here what to do next, so a scripted sequence of reads replays the whole decision. Time arrives as `elapsedMilliseconds`.
///
/// **The step is answered on the first two consecutive reads that agree and differ from the read taken before the event.** One read is not enough, because a screen mid-transition reads as something new for a moment; two agreeing reads say it has stopped. With no before-read (`read`) two agreeing reads are all it takes. At the bound the answer is qualified rather than refused: the last read is served either way, with `noVisibleChange` when it still matches `before` (the step may have done nothing, or changed nothing the screen shows) or `stillChanging` when the screen never held still.
public struct MirrorSettle {
    /// How long the driver leaves between two reads.
    public static let intervalMilliseconds = 250

    private let before: MirrorRead?
    private let bound: Int
    private var previous: MirrorRead?

    /// How many reads the decision has been handed.
    public private(set) var reads = 0

    /// - Parameters:
    ///   - before: The read taken before the event, or `nil` for a plain `read`.
    ///   - boundMilliseconds: How long to keep reading before answering with what is there (`--settle-ms`, 3 s by default).
    public init(before: MirrorRead?, boundMilliseconds: Int) {
        self.before = before
        bound = boundMilliseconds
    }

    /// What the driver should do having just read `read`, `elapsedMilliseconds` after the event.
    public mutating func take(_ read: MirrorRead, elapsedMilliseconds: Int) -> Decision {
        reads += 1
        defer { previous = read }
        let agreesWithPrevious = previous.map { read.agrees(with: $0) } ?? false
        let differsFromBefore = before.map { !read.agrees(with: $0) } ?? true
        if agreesWithPrevious, differsFromBefore {
            return .settled(read)
        }
        guard elapsedMilliseconds >= bound else { return .readAgain }
        if before != nil, !differsFromBefore {
            return .unsettled(read, .noVisibleChange)
        }
        return .unsettled(read, .stillChanging)
    }
}

public extension MirrorSettle {
    /// The driver's next move.
    enum Decision: Equatable, Sendable {
        /// Wait one interval and read again.
        case readAgain
        /// Two consecutive reads agreed and differ from the read before the event: answer with the second.
        case settled(MirrorRead)
        /// The bound is spent: answer with the last read, qualified by why.
        case unsettled(MirrorRead, Reason)
    }

    /// Why an answer is qualified.
    enum Reason: Equatable, Sendable {
        /// The last read still matches the one before the event: no visible text changed within the bound.
        case noVisibleChange
        /// The screen was still changing at the bound.
        case stillChanging
    }
}
