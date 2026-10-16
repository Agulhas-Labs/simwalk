//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Posts taps, drags and scroll-wheel lines into the iPhone Mirroring window: mouse and wheel events only, every method taking the guard's ``MirrorFocus/Clearance`` (Brief §8).
///
/// The timings are the 14 Oct spike's, which worked: the pointer arrives before the press, a press is held long enough to read as a tap, and a drag is interpolated so Mirroring sees motion rather than a jump.
///
/// **Every point is checked before the first event.** A fraction in the window's transparent border or a rounded corner of the screen is refused as a bad argument (``MirrorWindowFrame/target(for:)``), and then one snapshot of the window server's list must show every point the gesture touches — a drag's start, each interpolated step and its end — landing in the Mirroring window (``MirrorWindowStack/clear(_:into:focus:)``), or nothing is posted. The pass that check mints is what each event is posted on.
///
/// **Every gesture is re-checked after its last event.** A drag is 24 events over a third of a second; the guard ran before the first, and focus read again after the last says whether they all went to Mirroring. When it moved, the call is refused (``MirrorFocusRefusal/Moment/duringGesture``), because the events may have gone to whatever took focus. The check's clearance is what a gesture returns, so the capture after it runs on that one.
public struct MirrorPoster {
    /// The window the fractions are read against, looked up for this call.
    public let window: MirrorWindowFrame
    private let focus: MirrorFocusGuard
    private let stack: () -> MirrorWindowStack
    private let post: (MirrorEvent, MirrorWindowStack.Pass) -> Void
    private let pause: (TimeInterval) -> Void

    /// Interpolated steps in a drag, as the spike posted.
    static let dragSteps = 24

    /// A poster that hit-tests against the window server's live list and posts real events at the HID tap, re-checking focus through `focus`.
    public init(window: MirrorWindowFrame, focus: MirrorFocusGuard) {
        self.init(window: window, focus: focus, stack: MirrorWindow.stack, post: MirrorEvent.postToSystem, pause: Thread.sleep(forTimeInterval:))
    }

    /// A poster whose window list, events and waits come from and go to `stack`, `post` and `pause`, so a test records the sequence without posting anything.
    init(window: MirrorWindowFrame, focus: MirrorFocusGuard, stack: @escaping () -> MirrorWindowStack, post: @escaping (MirrorEvent, MirrorWindowStack.Pass) -> Void, pause: @escaping (TimeInterval) -> Void) {
        self.window = window
        self.focus = focus
        self.stack = stack
        self.post = post
        self.pause = pause
    }

    /// A tap: the pointer arrives, 60 ms, press, 70 ms, release — all at one point.
    public func tap(at fraction: MirrorFraction, clearance: MirrorFocus.Clearance) throws -> MirrorFocus.Clearance {
        let point = try window.target(for: fraction)
        let pass = try stack().clear([point], into: window, focus: clearance)
        post(.mouse(.moved, point: point), pass)
        pause(0.06)
        post(.mouse(.down, point: point), pass)
        pause(0.07)
        post(.mouse(.up, point: point), pass)
        return try focus.recheck(at: .duringGesture)
    }

    /// A drag from `start` to `end` over `milliseconds`: press at the start, ``dragSteps`` dragged events evenly along the line with the time split between them, the last on `end`, then release there 60 ms later.
    ///
    /// Fast (about 120 ms) on empty home-screen space pages it; slow on an icon enters edit mode. The screen is convex, so a line between two points on it stays on it; the window list is still checked at every step, because a window can sit over its middle.
    public func drag(from start: MirrorFraction, to end: MirrorFraction, milliseconds: Double, clearance: MirrorFocus.Clearance) throws -> MirrorFocus.Clearance {
        let from = try window.target(for: start)
        let to = try window.target(for: end)
        let steps = (1 ... Self.dragSteps).map { step in
            let progress = Double(step) / Double(Self.dragSteps)
            return MirrorWindowFrame.Point(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
        }
        let pass = try stack().clear([from] + steps, into: window, focus: clearance)
        post(.mouse(.moved, point: from), pass)
        pause(0.05)
        post(.mouse(.down, point: from), pass)
        for point in steps {
            post(.mouse(.dragged, point: point), pass)
            pause(milliseconds / 1000 / Double(Self.dragSteps))
        }
        pause(0.06)
        post(.mouse(.up, point: to), pass)
        return try focus.recheck(at: .duringGesture)
    }

    /// Scrolls `lines` lines of wheel at `fraction`, one line an event, 25 ms apart, after the pointer arrives there.
    ///
    /// Positive reveals what is below (or, `horizontal`, to the right): the wheel's own sign is the opposite, as the spike measured. Click-drag does not scroll inside an app over Mirroring; the wheel does.
    public func scroll(lines: Int32, horizontal: Bool, at fraction: MirrorFraction, clearance: MirrorFocus.Clearance) throws -> MirrorFocus.Clearance {
        let point = try window.target(for: fraction)
        let pass = try stack().clear([point], into: window, focus: clearance)
        post(.mouse(.moved, point: point), pass)
        pause(0.05)
        let step: Int32 = lines > 0 ? -1 : 1
        for _ in 0 ..< lines.magnitude {
            post(horizontal ? .wheel(count: 2, wheel1: 0, wheel2: step) : .wheel(count: 1, wheel1: step, wheel2: 0), pass)
            pause(0.025)
        }
        return try focus.recheck(at: .duringGesture)
    }
}
