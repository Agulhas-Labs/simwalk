//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// When the runner may bind an element that moved between the read that chose it and the bind (SimWalk#255), replayed against scripted frames of it.
///
/// Every test drives the tracker as the runner does — one read, then one interval's wait before the next — so the quiet period is measured in the reads the runner would make.
struct MovingTargetSettleTests {
    /// A button on a panel a spring slides up from the bottom edge is bound where it comes to rest, once it has held there for the quiet period — not refused as moved on the first read.
    @Test
    func aslideIsBoundWhereItComesToRestOnceTheQuietPeriodPasses() {
        let resting = Self.button(y: 700)
        let frames = [Self.button(y: 874), Self.button(y: 790), Self.button(y: 724), resting, resting, resting, resting, resting]

        let decisions = Self.replay(frames, quiet: 0.5)

        #expect(decisions.count == 6)
        #expect(decisions.dropLast().allSatisfy { $0 == .watch })
        #expect(decisions.last == .steady(resting))
    }

    /// SimWalk#252: an endless pulse scales the element about 6% on every read, and that is an element holding still, bound at the last frame read.
    @Test
    func apulseHoldsStill() {
        let small = Self.button(y: 700)
        let large = AXNode.Frame(x: 88, y: 698.5, width: 212, height: 47.7)
        let frames = [small, large, small, large, small]

        let decisions = Self.replay(frames, quiet: 0.5)

        #expect(decisions == [.watch, .watch, .steady(small)])
    }

    /// An element still moving when the lookup runs out is refused for having kept moving, with how long the wait lasted.
    @Test
    func anelementThatNeverHoldsStillRunsOutOfTime() {
        let frames = (0 ..< 60).map { Self.button(y: 874 - Double($0) * 10) }

        let decisions = Self.replay(frames, quiet: 0.25, lookup: 2)

        #expect(decisions.count == 9)
        #expect(decisions.dropLast().allSatisfy { $0 == .watch })
        #expect(decisions.last == .outOfTime(2))
    }

    /// A read that no longer holds the element ends the wait at once: the miss stands.
    @Test
    func avanishedElementIsGone() {
        var settle = MovingTargetSettle(quiet: 0.5, lookup: 10, interval: 0.25)

        #expect(settle.next(frame: Self.button(y: 874), elapsed: 0) == .watch)
        #expect(settle.next(frame: nil, elapsed: 0.25) == .gone)
    }

    /// **Stillness before a jump counts for nothing.** An element steady for two reads that then jumps is bound only once it has held steady for the whole quiet period again from the jump.
    @Test
    func ajumpStartsTheQuietPeriodAgainFromNothing() {
        let before = Self.button(y: 700)
        let after = Self.button(y: 600)
        let frames = [before, before, before, after, after, after, after, after]

        let decisions = Self.replay(frames, quiet: 0.75)

        #expect(decisions.count == 7)
        #expect(decisions.dropLast().allSatisfy { $0 == .watch })
        #expect(decisions.last == .steady(after))
    }

    /// **A creep is not stillness.** A spring's tail moving a point a read is steady with the read before every time, yet travels further than the allowance within the quiet period; held to the first frame of its run, it is bound only once it stops.
    @Test
    func acreepAPointAReadIsNotBoundUntilItStops() {
        let creep = (0 ..< 20).map { Self.button(y: 700 - Double($0)) }
        let rest = Array(repeating: Self.button(y: 681), count: 6)

        let decisions = Self.replay(creep + rest, quiet: 1.0)

        #expect(decisions.count > creep.count)
        #expect(decisions.dropLast().allSatisfy { $0 == .watch })
        #expect(decisions.last == .steady(Self.button(y: 681)))
    }

    /// **A still screen pays one read.** An element the bind missed only because its label ticked is, on the first read, steady with where the snapshot found it (here a pulse's other phase), and is bound there without a second read or a quiet period.
    @Test
    func afirstReadSteadyWithTheSnapshotIsBoundAtOnce() {
        let snapshot = Self.button(y: 700)
        let pulsed = AXNode.Frame(x: 88, y: 698.5, width: 212, height: 47.7)

        let decisions = Self.replay([pulsed, pulsed, pulsed], quiet: 0.5, snapshot: snapshot)

        #expect(decisions == [.steady(pulsed)])
    }

    /// **Only the first read is held to the snapshot.** An element that has moved is waited for as ever, and coming back past the snapshot's frame mid-flight does not bind it.
    @Test
    func anelementThatMovedFromTheSnapshotWaitsTheQuietPeriod() {
        let snapshot = Self.button(y: 700)
        let resting = Self.button(y: 600)
        let frames = [Self.button(y: 800), snapshot, resting, resting, resting, resting]

        let decisions = Self.replay(frames, quiet: 0.5, snapshot: snapshot)

        #expect(decisions == [.watch, .watch, .watch, .watch, .steady(resting)])
    }

    /// SimWalk#276: a frame steady with the run the bind just missed is not bound again at once; the quiet period starts afresh.
    @Test
    func aframeSteadyWithTheOldRunWaitsTheQuietPeriodAfterAMissedBind() {
        let resting = Self.button(y: 700)
        var settle = MovingTargetSettle(quiet: 0.5, lookup: 10, interval: 0.25, snapshot: nil)
        #expect(settle.next(frame: resting, elapsed: 0) == .watch)
        #expect(settle.next(frame: resting, elapsed: 0.25) == .watch)
        #expect(settle.next(frame: resting, elapsed: 0.5) == .steady(resting))

        settle.missedBind()

        #expect(settle.next(frame: resting, elapsed: 0.75) == .watch)
        #expect(settle.next(frame: resting, elapsed: 1) == .watch)
        #expect(settle.next(frame: resting, elapsed: 1.25) == .steady(resting))
    }

    /// SimWalk#276: an element that keeps moving after a missed bind runs the lookup out rather than being refused as moved.
    @Test
    func anelementThatKeepsMovingAfterAMissedBindRunsOutOfTime() {
        var settle = MovingTargetSettle(quiet: 0.5, lookup: 2, interval: 0.25, snapshot: Self.button(y: 700))
        #expect(settle.next(frame: Self.button(y: 700), elapsed: 0) == .steady(Self.button(y: 700)))

        settle.missedBind()

        #expect(settle.next(frame: Self.button(y: 600), elapsed: 0.25) == .watch)
        #expect(settle.next(frame: Self.button(y: 500), elapsed: 1) == .watch)
        #expect(settle.next(frame: Self.button(y: 400), elapsed: 2) == .outOfTime(2))
    }

    /// The tracker's decisions over `frames`, read one interval apart, up to and including the first that is not `.watch`.
    private static func replay(_ frames: [AXNode.Frame], quiet: TimeInterval, lookup: TimeInterval = 10, interval: TimeInterval = 0.25, snapshot: AXNode.Frame? = nil) -> [MovingTargetSettle.Decision] {
        var settle = MovingTargetSettle(quiet: quiet, lookup: lookup, interval: interval, snapshot: snapshot)
        var decisions: [MovingTargetSettle.Decision] = []
        for (read, frame) in frames.enumerated() {
            let decision = settle.next(frame: frame, elapsed: Double(read) * interval)
            decisions.append(decision)
            if decision != .watch {
                break
            }
        }
        return decisions
    }

    private static func button(y: Double) -> AXNode.Frame {
        AXNode.Frame(x: 95, y: y, width: 200, height: 45)
    }
}
