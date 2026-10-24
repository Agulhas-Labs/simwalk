//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// `OrientationSettle` waits for a just-booted device to take a stated orientation (SimWalk#224).
struct OrientationSettleTests {
    private let portrait = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private let landscape = AXNode.Frame(x: 0, y: 0, width: 874, height: 402)
    private let square = AXNode.Frame(x: 0, y: 0, width: 400, height: 400)

    /// Settles with a frame that is `before` until `agreeAfterReads` reads (or until the turn back when nil), then `after`.
    private func settle(_ stated: Walkbook.Orientation, before: AXNode.Frame, after: AXNode.Frame, agreeAfterReads: Int?, probe: Probe) -> AXNode.Frame {
        OrientationSettle.settledFrame(
            stated: stated,
            frame: {
                probe.reads += 1
                if let agreeAfterReads {
                    return probe.reads > agreeAfterReads ? after : before
                }
                return probe.turns.count >= 2 ? after : before
            },
            turn: { probe.turns.append($0) },
            wait: { probe.waits.append($0) }
        )
    }

    @Test
    func agreeingFrameAnswersAtOnceWithNoWaitOrTurn() {
        let probe = Probe()
        let answered = settle(.landscape, before: landscape, after: landscape, agreeAfterReads: 0, probe: probe)

        #expect(answered == landscape)
        #expect(probe.waits.isEmpty)
        #expect(probe.turns.isEmpty)
    }

    @Test
    func frameAgreeingAfterFewPollsAnswersWithoutTurning() {
        let probe = Probe()
        let answered = settle(.landscape, before: portrait, after: landscape, agreeAfterReads: 3, probe: probe)

        #expect(answered == landscape)
        #expect(probe.waits.count == 3)
        #expect(probe.turns.isEmpty)
    }

    @Test
    func frameAgreeingOnlyAfterTurnAwayAndBackRecordsThatTurn() {
        let probe = Probe()
        let answered = settle(.landscape, before: portrait, after: landscape, agreeAfterReads: nil, probe: probe)

        #expect(answered == landscape)
        #expect(probe.turns == [.portrait, .landscape])
    }

    @Test
    func portraitStatedTurnsAwayToLandscapeAndBack() {
        let probe = Probe()
        _ = settle(.portrait, before: landscape, after: portrait, agreeAfterReads: nil, probe: probe)

        #expect(probe.turns == [.landscape, .portrait])
    }

    @Test
    func neverAgreeingAnswersContradictingFrameWithinBothBudgets() {
        let probe = Probe()
        let answered = settle(.landscape, before: portrait, after: portrait, agreeAfterReads: Int.max, probe: probe)

        #expect(answered == portrait)
        #expect(probe.turns == [.portrait, .landscape])
        #expect(probe.waits.reduce(0, +) <= 2 * OrientationSettle.pollBudget + 0.001)
        #expect(!probe.waits.isEmpty)
    }

    @Test
    func withoutTurnAwayOnlyPollsOnce() {
        let probe = Probe()
        let answered = OrientationSettle.settledFrame(
            stated: .landscape, frame: { portrait }, turn: { probe.turns.append($0) }, wait: { probe.waits.append($0) }, turnsAway: false
        )

        #expect(answered == portrait)
        #expect(probe.turns.isEmpty)
        #expect(probe.waits.reduce(0, +) <= OrientationSettle.pollBudget + 0.001)
    }

    @Test
    func unjudgeableFrameAnswersAtOnce() {
        let probe = Probe()
        let answered = settle(.landscape, before: square, after: square, agreeAfterReads: Int.max, probe: probe)

        #expect(answered == square)
        #expect(probe.waits.isEmpty)
        #expect(probe.turns.isEmpty)
    }
}

extension OrientationSettleTests {
    private final class Probe {
        var reads = 0
        var waits: [TimeInterval] = []
        var turns: [Walkbook.Orientation] = []
    }
}
