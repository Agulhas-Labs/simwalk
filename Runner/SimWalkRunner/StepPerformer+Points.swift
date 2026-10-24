//
// Copyright © Agulhas Labs
//

import SimWalkCore
import XCTest

extension StepPerformer {
    /// What a point gesture's optional `label` resolved to: the frame its points are placed within (nil with no label), or the refusal to land.
    private enum LabelledFrame {
        case frame(AXNode.Frame?)
        case blocked(StepResult)
    }

    /// Resolves and binds `label` as every point gesture does (`resolve`, then `bind`, reaching as a `scrollTo` does), keeping only its frame; `doing` completes the refusal ("tapped within", "dragged within").
    private func frameOfLabelled(_ label: String?, doing: String, quiet: TimeInterval, budget: TimeInterval) throws -> LabelledFrame {
        guard let label else { return .frame(nil) }
        let choice = try TargetResolution.resolve(label, reaching: .anything, in: app, quiet: quiet, budget: budget)
        guard case .chosen = choice else {
            return .blocked(.blocked(reason: choice.reason(for: label)))
        }
        let binding = try TargetResolution.bind(choice, labelled: label, in: app, quiet: quiet, budget: budget) {
            TargetResolution.element(for: $0, labelled: label, in: app)
        }
        guard case let .element(_, target, _) = binding else {
            return .blocked(.blocked(reason: binding.refusal(doing: doing)))
        }
        return .frame(target.node.frame)
    }

    /// A `drag` (SimWalk#148): press at `from`, rest `hold` seconds, move to `to` over `seconds`, lift.
    ///
    /// Both ends are placed as a `tapPoint` places its point, by `TapPointPlacement`, so the refusals match; it lands one quiet period after the release.
    func drag(between ends: (from: [Double], to: [Double]), within label: String?, hold: Double, seconds: Double, quiet: TimeInterval, budget: TimeInterval) throws -> StepResult {
        let element: AXNode.Frame?
        switch try frameOfLabelled(label, doing: "dragged within", quiet: quiet, budget: budget) {
        case let .blocked(result): return result
        case let .frame(frame): element = frame
        }
        let bounds = app.frame
        let screen = AXNode.Frame(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height)
        var placed: [(x: Double, y: Double)] = []
        for (field, point) in [("from", ends.from), ("to", ends.to)] {
            switch TapPointPlacement.of(point, within: element, onScreen: screen) {
            case let .refused(reason):
                return .blocked(reason: "drag's \(field): \(reason)")
            case let .point(x, y):
                placed.append((x, y))
            }
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: placed[0].x - screen.x, dy: placed[0].y - screen.y))
        let end = origin.withOffset(CGVector(dx: placed[1].x - screen.x, dy: placed[1].y - screen.y))
        // `XCUIGestureVelocity` is documented as pixels per second, but it behaves as points per second:
        // measured on an iPhone 17 (3x), a drag asked for `seconds` 2 with `hold` 0.1 took 2.46 s from press to
        // release (6 s or more if it were pixels), so the velocity is the distance in points over `seconds`.
        let distance = hypot(placed[1].x - placed[0].x, placed[1].y - placed[0].y)
        let velocity = XCUIGestureVelocity(max(distance, 1) / seconds)
        start.press(forDuration: hold, thenDragTo: end, withVelocity: velocity, thenHoldForDuration: 0)
        return landedAfterQuietPeriod()
    }

    /// Waits one of this walk's quiet periods, then lands, reading nothing of the tree (`TapPointLanding` decides when).
    func landedAfterQuietPeriod() -> StepResult {
        let landing = TapPointLanding(quiet: quiet)
        let touched = Date()
        while true {
            switch landing.next(elapsed: Date().timeIntervalSince(touched)) {
            case .watch:
                Thread.sleep(forTimeInterval: Self.settleInterval)
            case .landed:
                return .landed
            }
        }
    }

    /// Taps a point — within the frame of the element `label` resolves to, or on the screen when there is no label (SimWalk#29).
    ///
    /// **The label resolves through the same choice as every other step's** (`resolve`, then `bind`), reaching as a `scrollTo` does: a chart is content, not a control, and a bar's control is never preferred to it. What it contributes is only a frame; `TapPointPlacement` decides the point, or refuses — an empty frame, a point off the screen — in the core where a test holds it.
    ///
    /// **Landed means the touch was delivered there and, if it navigated, that the destination was reached** (SimWalk#29 review, item 1) — a `tap` that pushes returns before the push happens, so the same wait `tap` and `back` already pay is what this step now pays too, or SimWalk#6 recurs one step over: the settle window closes on the screen just left, filing its capture under the destination's id, and the next route step resolves against the wrong screen. So the step waits one quiet period after the touch, and then lands unconditionally: no read of the tree lands it early, since `ScreenIdentity` cannot tell a push from a ticking label, a spinner or a callout (the 2026-09-23 review), and nothing after the touch refuses (SimWalk#38, item 4). `TapPointLanding` holds the decision and the wait, in the core, where a test replays it against a scripted clock (SimWalk#38); this loop keeps only the clock. The manifest still names the step `tapPoint`, so a reader can tell what resolved it.
    func tapPoint(at point: [Double], within label: String?, in app: XCUIApplication, quiet: TimeInterval, budget: TimeInterval) throws -> StepResult {
        let element: AXNode.Frame?
        switch try frameOfLabelled(label, doing: "tapped within", quiet: quiet, budget: budget) {
        case let .blocked(result): return result
        case let .frame(frame): element = frame
        }
        let bounds = app.frame
        let screen = AXNode.Frame(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height)
        switch TapPointPlacement.of(point, within: element, onScreen: screen) {
        case let .refused(reason):
            return .blocked(reason: reason)
        case let .point(x, y):
            // One of this walk's quiet periods, not the fixed poll interval: a walk slowed with `--settle` is one
            // whose pushes take that long to reach the tree (SimWalk#29 review 2).
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - screen.x, dy: y - screen.y)).tap()
            return landedAfterQuietPeriod()
        }
    }
}
