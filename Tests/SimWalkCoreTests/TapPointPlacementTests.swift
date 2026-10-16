//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Where a point step's touch lands is decided here rather than in the runner, which `swift test` never compiles — so each answer, and each refusal, is held by a test (SimWalk#29).
struct TapPointPlacementTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    @Test
    func apointOnTheScreenIsTappedWhereItIsWritten() {
        #expect(TapPointPlacement.of([201, 610], within: nil, onScreen: Self.screen) == .point(x: 201, y: 610))
    }

    /// The form that survives a change of device: the same fractions of a chart land on the same bar whatever the chart measures.
    @Test
    func apointWithinAnElementIsMeasuredAgainstItsFrame() {
        let chart = AXNode.Frame(x: 16, y: 300, width: 370, height: 200)

        #expect(TapPointPlacement.of([0.8, 0.5], within: chart, onScreen: Self.screen) == .point(x: 312, y: 400))
    }

    /// Health leaves the previous period's bars in the tree at zero size: every fraction of such a frame is its one corner, which is not the element the step names.
    @Test
    func anelementWithAnEmptyFrameIsRefused() {
        let stale = AXNode.Frame(x: 40, y: 400, width: 0, height: 0)

        let placement = TapPointPlacement.of([0.5, 0.5], within: stale, onScreen: Self.screen)

        guard case let .refused(reason) = placement else {
            Issue.record("expected a refusal, got \(placement)")
            return
        }

        #expect(reason.contains("frame is empty"))
    }

    /// The half of an absolute point `validate` cannot check, not knowing the device, is refused here rather than tapped.
    @Test
    func apointBeyondTheScreenIsRefusedNamingTheScreen() {
        let placement = TapPointPlacement.of([201, 900], within: nil, onScreen: Self.screen)

        #expect(placement == .refused(reason: "201,900 is outside the screen (402×874 pt)"))
    }

    /// An element partly off screen puts some of its fractions off it too; those are refused, naming where they would have landed.
    @Test
    func apointWithinAnElementThatFallsOffTheScreenIsRefused() {
        let row = AXNode.Frame(x: 0, y: 800, width: 402, height: 200)

        let placement = TapPointPlacement.of([0.5, 0.9], within: row, onScreen: Self.screen)

        #expect(placement == .refused(reason: "0.5,0.9 of the element's frame, 201,980, is outside the screen (402×874 pt)"))
    }

    /// The screen's edges are on it, so the far corner of an element flush with the screen's is tapped.
    @Test
    func thefarCornerOfAnElementFlushWithTheScreenIsTapped() {
        #expect(TapPointPlacement.of([1, 1], within: Self.screen, onScreen: Self.screen) == .point(x: 402, y: 874))
    }

    /// A walkbook that reached the runner without `validate` is held to the same two rules as one that did.
    @Test(arguments: [[0.5], [1.5, 0.5]])
    func apointValidateWouldRefuseIsRefusedHereToo(_ point: [Double]) {
        let chart = AXNode.Frame(x: 16, y: 300, width: 370, height: 200)

        let placement = TapPointPlacement.of(point, within: chart, onScreen: Self.screen)

        guard case .refused = placement else {
            Issue.record("expected a refusal, got \(placement)")
            return
        }
    }
}
