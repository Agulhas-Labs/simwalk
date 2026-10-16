//
// Copyright © Agulhas Labs
//

import Foundation

/// The window server's on-screen windows at one moment, front to back, and the displays they sit on: what decides which window a mouse event at a point lands in (Brief §8 "Frontmost is not where a mouse event lands").
///
/// **Frontmost is not where a click goes.** An event posted at the HID tap goes to the window under the pointer, so a floating panel, an alert or another app's window over the target point takes it while System Events still names Mirroring frontmost. So before a gesture posts, ``clear(_:into:focus:)`` requires every point it touches to land in the Mirroring window, decided here over plain records so a test scripts the list; the driver only takes the snapshot (`MirrorWindow.stack()`).
///
/// **Two kinds of window are passed over.** One drawn with alpha 0 shows nothing and takes no click. One that fills a whole display at a layer above normal windows, **and is owned by a known system surface matched by bundle id** (``systemSurfaces``: the Dock and Notification Centre), is passed over: on 14 Oct each listed a window the size of the display with alpha 1 over every app, drawing, and taking clicks, only where their content is, and counting them would refuse every call. Any other display-sized raised window (the `screencaptureui` area picker, a presentation or annotation overlay) takes clicks everywhere, so it covers the point and refuses, naming its owner; so does one whose bundle id is unknown. The owner is matched by bundle id, never by name, which is localised. **What that leaves unseen:** content those surfaces draw over the point — the Dock itself, or a banner Notification Centre draws inside its surface rather than in a window of its own — which the list cannot tell from their transparent remainder.
public struct MirrorWindowStack: Equatable, Sendable {
    /// The on-screen windows, frontmost first, as the window server lists them.
    public let windows: [Window]
    /// Each display's bounds in global display points.
    public let displays: [Bounds]

    public init(windows: [Window], displays: [Bounds]) {
        self.windows = windows
        self.displays = displays
    }

    /// The bundle ids of the system surfaces whose display-sized raised windows are passed over, each there because it lists such a window while drawing and taking clicks only where its content is: `com.apple.dock` (the Dock, layer 20) and `com.apple.notificationcenterui` (Notification Centre, layer 21).
    public static let systemSurfaces: Set<String> = ["com.apple.dock", "com.apple.notificationcenterui"]

    /// A pass for a gesture whose every point in `points` lands in `frame`'s window, or a refusal naming the owner of the first window found over one of them (``MirrorFocusRefusal/Moment/pointCovered``, exit 3: a banner or panel goes away, so a retry is right).
    ///
    /// If the list has an entry for the window it must also still have the frame's bounds (within half a point), because the points were computed from a frame measured before a read that can take minutes: a window moved since puts a point in the transparent border or on another control, so that refuses with ``MirrorFocusRefusal/Moment/windowMoved`` (exit 3, a retry measures again).
    ///
    /// Takes the focus clearance the gesture is posted on, so the pass is minted only on top of a guard that ran.
    public func clear(_ points: [MirrorWindowFrame.Point], into frame: MirrorWindowFrame, focus _: MirrorFocus.Clearance) throws(MirrorFocusRefusal) -> Pass {
        if let current = windows.first(where: { $0.windowID == frame.windowID })?.bounds, !current.matches(frame) {
            throw MirrorFocusRefusal(frontmost: MirrorFocus.appName, moment: .windowMoved)
        }
        for point in points {
            let receiver = receiver(of: point)
            guard receiver?.windowID == frame.windowID else {
                throw MirrorFocusRefusal(frontmost: receiver?.owner ?? "", moment: .pointCovered)
            }
        }
        return Pass()
    }

    /// The window a mouse event at `point` lands in: the first, front to back, that is visible, is not a full-display window of a known system surface, and contains it.
    func receiver(of point: MirrorWindowFrame.Point) -> Window? {
        windows.first { window in
            window.alpha > 0 && !isSystemSurface(window) && window.bounds.contains(point)
        }
    }

    /// Whether `window` is a raised, display-sized window owned by one of ``systemSurfaces``: a nil bundle id is never one.
    private func isSystemSurface(_ window: Window) -> Bool {
        guard window.layer > 0, displays.contains(window.bounds), let bundleID = window.bundleID else {
            return false
        }
        return Self.systemSurfaces.contains(bundleID)
    }
}

public extension MirrorWindowStack {
    /// One window as the window server lists it.
    struct Window: Equatable, Sendable {
        /// The window server's id for it.
        public let windowID: UInt32
        /// The owning app's name, empty when the list gives none.
        public let owner: String
        /// Its layer: 0 for normal app windows, higher for floating panels, the Dock and system overlays.
        public let layer: Int
        /// Its opacity, 0…1.
        public let alpha: Double
        /// Where it is, in global display points.
        public let bounds: Bounds
        /// The owning app's bundle id, `nil` when it could not be found; `nil` is never a system surface.
        public let bundleID: String?

        public init(windowID: UInt32, owner: String, layer: Int, alpha: Double, bounds: Bounds, bundleID: String? = nil) {
            self.bundleID = bundleID
            self.windowID = windowID
            self.owner = owner
            self.layer = layer
            self.alpha = alpha
            self.bounds = bounds
        }
    }

    /// A rectangle in global display points, top-left origin.
    struct Bounds: Equatable, Sendable {
        /// Its left edge.
        public let x: Double
        /// Its top edge.
        public let y: Double
        /// Its width.
        public let width: Double
        /// Its height.
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        /// Whether it is `frame`'s rectangle, to within half a point on each edge.
        func matches(_ frame: MirrorWindowFrame) -> Bool {
            abs(x - frame.x) <= 0.5 && abs(y - frame.y) <= 0.5 && abs(width - frame.width) <= 0.5 && abs(height - frame.height) <= 0.5
        }

        /// Whether `point` is inside it, half-open: its right and bottom edges belong to what lies beyond.
        func contains(_ point: MirrorWindowFrame.Point) -> Bool {
            point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
        }
    }

    /// Proof that a gesture's points were hit-tested into the Mirroring window, minted only by ``MirrorWindowStack/clear(_:into:focus:)`` passing (`init` is `fileprivate`).
    ///
    /// **Posting an event takes one** (`MirrorEvent.postToSystem`), and minting one takes a focus clearance, so no code in the driver posts an event without both the guard and the hit test having run.
    final class Pass: Sendable {
        fileprivate init() {}
    }
}
