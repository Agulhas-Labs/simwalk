//
// Copyright © Agulhas Labs
//

import Foundation

/// Watches the element a route step chose while it moves, read by read, and says when it holds steady enough to bind (SimWalk#255).
///
/// **A walk turns UIKit's animations off, not SwiftUI's.** A button on a panel a `withAnimation(.spring)` is still sliding in is read at one frame and is somewhere else by the time the runner binds it, so the step used to refuse it as moved after one more read, and real walkbooks grew a no-op `tapPoint` before each such step to wait the slide out. The runner now keeps reading until the element has held still for the quiet period of the screen the step is taken on, and binds it there.
///
/// **Measured as `RouteTargetTracker` and `SettleTracker` measure quiet**: each read whose frame is steady (`AXNode.Frame.isSteady(with:)`) adds an interval, any other starts again from nothing. Steady rather than equal, so an element an endless pulse keeps scaling a few percent still counts as holding still (SimWalk#252, #258), where a slide moves it by far more than the allowance on every read.
///
/// **Steady with the first frame of the run, not with the read before.** A spring's tail creeps a point or so a read, which is steady from one read to the next while the element travels ten points or more over the quiet period; compared read to read it would be bound mid-creep. Held against the run's first frame (its anchor), a creep breaks the run as soon as it has gone further than the allowance, and the frame that broke it anchors the next.
///
/// **A first read steady with the snapshot binds at once.** The snapshot that chose the element was itself read after the screen's quiet period, so an element the bind missed only because its label ticked between the two (a `{n}` chip, a lead-in) is still where the snapshot found it: holding it for a second quiet period would charge a still screen for motion it does not have. Only an element that really moved waits.
///
/// **A steady frame the bind then misses starts the wait again.** An element that held steady but could not be bound (its label ticked, or the screen shifted a frame under it) is not refused as moved at once: `missedBind()` drops the run, its anchor and the snapshot, so the next read begins a fresh quiet period, and only the lookup running out refuses the step (SimWalk#276).
///
/// **Bounded by the lookup**, the longest any step reads for its element: an element that never holds still is refused for having kept moving rather than tapped mid-flight, and one that vanishes is the miss the step always reported. It is in the core so a test can replay scripted frames against it, with time arriving as `elapsed`.
public struct MovingTargetSettle {
    private let quiet: TimeInterval
    private let lookup: TimeInterval
    private let interval: TimeInterval
    /// The first frame of the current run of steady reads, what every later read of the run is held to.
    private var anchor: AXNode.Frame?
    private var quietSoFar: TimeInterval = 0
    /// Where the snapshot that chose the element read it, until the first read has been held against it.
    private var snapshot: AXNode.Frame?

    /// - Parameters:
    ///   - quiet: How long the element must hold steady before it is bound — the quiet period of the screen the step is taken on.
    ///   - lookup: The longest the wait reads at all, from its first read.
    ///   - interval: How long the runner leaves between two reads — the unit stillness is measured in.
    ///   - snapshot: Where the read that chose the element found it, taken once the screen had held still: a first read steady with it is bound at once.
    public init(quiet: TimeInterval, lookup: TimeInterval, interval: TimeInterval = SettleWindow.interval, snapshot: AXNode.Frame? = nil) {
        self.quiet = quiet
        self.lookup = lookup
        self.interval = interval
        self.snapshot = snapshot
    }

    /// Records that the runner bound nothing at the frame `next(frame:elapsed:)` called steady, so the next read starts a fresh quiet period rather than counting the run that just failed (SimWalk#276).
    public mutating func missedBind() {
        anchor = nil
        quietSoFar = 0
        snapshot = nil
    }

    /// What the runner should do having just read the chosen element at `frame` — `nil` when the read no longer holds it — `elapsed` into the wait.
    public mutating func next(frame: AXNode.Frame?, elapsed: TimeInterval) -> Decision {
        guard let frame else { return .gone }
        defer { snapshot = nil }
        if let snapshot, frame.isSteady(with: snapshot) {
            return .steady(frame)
        }
        if let anchor, frame.isSteady(with: anchor) {
            quietSoFar += interval
        } else {
            anchor = frame
            quietSoFar = 0
        }
        if quietSoFar >= quiet {
            return .steady(frame)
        }
        return elapsed >= lookup ? .outOfTime(elapsed) : .watch
    }
}

public extension MovingTargetSettle {
    /// The runner's next move.
    enum Decision: Equatable, Sendable {
        /// Wait one interval and read again.
        case watch
        /// The element has held steady for the quiet period: bind it at this frame, the last one read.
        case steady(AXNode.Frame)
        /// The read no longer holds the element chosen: the miss stands.
        case gone
        /// The lookup ran out with the element still moving, after this many seconds.
        case outOfTime(TimeInterval)
    }
}
