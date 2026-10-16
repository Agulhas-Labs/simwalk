//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import SimWalkCore

/// One event the mirror poster sends: a left-button mouse event or a line of scroll wheel, and nothing else (Brief §8 "Never keystrokes").
///
/// **There is no keyboard case, by construction.** Keystrokes arrive scrambled through Mirroring, and one sent to the wrong window does damage, so the only events this target can describe are the ones it is allowed to post. Posting one takes the hit test's ``MirrorWindowStack/Pass``, which only a passing hit test over a focus clearance mints, so no code in this module posts without the guard and the hit test having run; the poster is the only code that asks for one.
enum MirrorEvent: Equatable {
    /// A left-button mouse event at a display point.
    case mouse(Mouse, point: MirrorWindowFrame.Point)
    /// One line of scroll wheel: `CGEvent(scrollWheelEvent2Source:units: .line …)`'s own `wheelCount`, `wheel1` (vertical) and `wheel2` (horizontal).
    case wheel(count: UInt32, wheel1: Int32, wheel2: Int32)

    /// Creates the event and posts it at the HID tap, where it enters as if from the hardware: the live seam ``MirrorPoster`` posts through, on the pass its hit test minted.
    static func postToSystem(_ event: Self, pass _: MirrorWindowStack.Pass) {
        switch event {
        case let .mouse(kind, point):
            CGEvent(mouseEventSource: nil, mouseType: kind.eventType, mouseCursorPosition: CGPoint(x: point.x, y: point.y), mouseButton: .left)?
                .post(tap: .cghidEventTap)
        case let .wheel(count, wheel1, wheel2):
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: count, wheel1: wheel1, wheel2: wheel2, wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
    }
}

extension MirrorEvent {
    /// The left-button mouse events a tap and a drag are made of.
    enum Mouse: Equatable {
        /// The pointer arriving, so Mirroring sees it there before the press.
        case moved
        /// The press.
        case down
        /// The pointer moving with the button held.
        case dragged
        /// The release.
        case up

        /// The `CGEventType` it is posted as.
        var eventType: CGEventType {
            switch self {
            case .moved:
                .mouseMoved
            case .down:
                .leftMouseDown
            case .dragged:
                .leftMouseDragged
            case .up:
                .leftMouseUp
            }
        }
    }
}
