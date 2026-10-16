//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Which window a mouse event at a point lands in, over scripted window-server lists: the Mirroring window must be the first visible window over every point a gesture touches.
struct MirrorWindowStackTests {
    private static let display = MirrorWindowStack.Bounds(x: 0, y: 0, width: 1728, height: 1117)
    private static let mirroring = MirrorWindowStack.Window(windowID: 1018, owner: MirrorFocus.appName, layer: 0, alpha: 1, bounds: MirrorWindowStack.Bounds(x: 672, y: 118, width: 383, height: 843))
    private static let frame = MirrorWindowFrame(windowID: 1018, x: 672, y: 118, width: 383, height: 843)
    private static let centre = MirrorWindowFrame.Point(x: 863.5, y: 539.5)

    private static func window(_ id: UInt32, _ owner: String, layer: Int, alpha: Double = 1, bundleID: String? = nil, _ bounds: MirrorWindowStack.Bounds) -> MirrorWindowStack.Window {
        MirrorWindowStack.Window(windowID: id, owner: owner, layer: layer, alpha: alpha, bounds: bounds, bundleID: bundleID)
    }

    private static func clearance() throws -> MirrorFocus.Clearance {
        try MirrorFocus.recheck(MirrorFocus.appName, at: .beforeAction)
    }

    /// The list measured live on 14 Oct passes: the Dock's and Notification Centre's full-display surfaces over everything are passed over, and the windows behind Mirroring do not count.
    @Test
    func theLiveListPassesTheCentre() throws {
        let stack = MirrorWindowStack(windows: [
            Self.window(918, "UserNotificationCenter", layer: 8, MirrorWindowStack.Bounds(x: 1680, y: 475, width: 260, height: 234)),
            Self.window(6, "Window Server", layer: 24, MirrorWindowStack.Bounds(x: 0, y: 0, width: 1728, height: 33)),
            Self.window(64, "Notification Centre", layer: 21, bundleID: "com.apple.notificationcenterui", Self.display),
            Self.window(30, "Dock", layer: 20, bundleID: "com.apple.dock", Self.display),
            Self.mirroring,
            Self.window(812, "Safari", layer: 0, MirrorWindowStack.Bounds(x: 244, y: 33, width: 1324, height: 940)),
        ], displays: [Self.display])

        _ = try stack.clear([Self.centre, MirrorWindowFrame.Point(x: 680, y: 950)], into: Self.frame, focus: Self.clearance())
    }

    /// A visible window over one of the points refuses, naming its owner as a point covered; one behind Mirroring does not.
    @Test
    func aWindowOverAPointRefusesNamingItsOwner() throws {
        let panel = Self.window(50, "Raycast", layer: 3, MirrorWindowStack.Bounds(x: 700, y: 900, width: 100, height: 40))
        let stack = MirrorWindowStack(windows: [panel, Self.mirroring], displays: [Self.display])

        #expect(throws: MirrorFocusRefusal(frontmost: "Raycast", moment: .pointCovered)) {
            try stack.clear([Self.centre, MirrorWindowFrame.Point(x: 750, y: 920)], into: Self.frame, focus: Self.clearance())
        }
        _ = try stack.clear([Self.centre], into: Self.frame, focus: Self.clearance())
    }

    /// A window drawn at alpha 0 is passed over; the same window at any opacity covers.
    @Test
    func anInvisibleWindowIsPassedOver() throws {
        let bounds = MirrorWindowStack.Bounds(x: 800, y: 500, width: 100, height: 100)
        let hidden = MirrorWindowStack(windows: [Self.window(9, "Overlay", layer: 25, alpha: 0, bounds), Self.mirroring], displays: [Self.display])
        let faint = MirrorWindowStack(windows: [Self.window(9, "Overlay", layer: 25, alpha: 0.05, bounds), Self.mirroring], displays: [Self.display])

        _ = try hidden.clear([Self.centre], into: Self.frame, focus: Self.clearance())

        #expect(throws: MirrorFocusRefusal(frontmost: "Overlay", moment: .pointCovered)) {
            try faint.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        }
    }

    /// Only a raised window the size of a whole display is a system surface: a display-sized app window at layer 0, and a raised one a point smaller, both cover.
    @Test
    func onlyARaisedFullDisplayWindowIsASurface() throws {
        let appWindow = MirrorWindowStack(windows: [Self.window(5, "Keynote", layer: 0, Self.display), Self.mirroring], displays: [Self.display])
        let smaller = MirrorWindowStack(windows: [Self.window(6, "Panel", layer: 3, MirrorWindowStack.Bounds(x: 0, y: 0, width: 1728, height: 1116)), Self.mirroring], displays: [Self.display])

        #expect(throws: MirrorFocusRefusal(frontmost: "Keynote", moment: .pointCovered)) {
            try appWindow.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        }
        #expect(throws: MirrorFocusRefusal(frontmost: "Panel", moment: .pointCovered)) {
            try smaller.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        }
    }

    /// A point under no window at all, or a list without the Mirroring window, refuses; the message names what was there.
    @Test
    func aPointUnderNoWindowRefuses() throws {
        let empty = MirrorWindowStack(windows: [], displays: [Self.display])

        #expect(throws: MirrorFocusRefusal(frontmost: "", moment: .pointCovered)) {
            try empty.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        }
        #expect(MirrorFocusRefusal(frontmost: "", moment: .pointCovered).localizedDescription.contains("under no window"))
        #expect(MirrorFocusRefusal(frontmost: "Dock", moment: .pointCovered).localizedDescription.contains("a window of 'Dock'"))
    }

    /// Only a known system surface, matched by bundle id, is passed over: another app's display-sized raised window, or one with no known bundle id, covers the point.
    @Test
    func onlyAKnownSurfaceIsSkipped() throws {
        let presentify = MirrorWindowStack(windows: [Self.window(7, "Presentify", layer: 25, bundleID: "com.presentify.app", Self.display), Self.mirroring], displays: [Self.display])
        let unknown = MirrorWindowStack(windows: [Self.window(8, "Mystery", layer: 25, Self.display), Self.mirroring], displays: [Self.display])
        let surfaces = MirrorWindowStack(windows: [
            Self.window(64, "Notification Center", layer: 21, bundleID: "com.apple.notificationcenterui", Self.display),
            Self.window(30, "Dock", layer: 20, bundleID: "com.apple.dock", Self.display),
            Self.mirroring,
        ], displays: [Self.display])

        #expect(throws: MirrorFocusRefusal(frontmost: "Presentify", moment: .pointCovered)) {
            try presentify.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        }
        #expect(throws: MirrorFocusRefusal(frontmost: "Mystery", moment: .pointCovered)) {
            try unknown.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        }
        _ = try surfaces.clear([Self.centre], into: Self.frame, focus: Self.clearance())
    }

    /// The points came from a frame measured before a long read: a Mirroring window offset by 5 pt in the list refuses, the same bounds pass.
    @Test
    func aMovedWindowRefuses() throws {
        let moved = MirrorWindowStack.Window(windowID: 1018, owner: MirrorFocus.appName, layer: 0, alpha: 1, bounds: MirrorWindowStack.Bounds(x: 677, y: 118, width: 383, height: 843))
        let offset = MirrorWindowStack(windows: [moved], displays: [Self.display])
        let same = MirrorWindowStack(windows: [Self.mirroring], displays: [Self.display])

        #expect(throws: MirrorFocusRefusal(frontmost: MirrorFocus.appName, moment: .windowMoved)) {
            try offset.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        }
        _ = try same.clear([Self.centre], into: Self.frame, focus: Self.clearance())
        #expect(MirrorFocusRefusal(frontmost: MirrorFocus.appName, moment: .windowMoved).localizedDescription.contains("moved or resized"))
    }

    /// Bounds are half-open: a window's right and bottom edges belong to what lies beyond.
    @Test
    func boundsAreHalfOpen() {
        let bounds = MirrorWindowStack.Bounds(x: 10, y: 10, width: 10, height: 10)

        #expect(bounds.contains(MirrorWindowFrame.Point(x: 10, y: 10)))
        #expect(bounds.contains(MirrorWindowFrame.Point(x: 19.9, y: 19.9)))
        #expect(!bounds.contains(MirrorWindowFrame.Point(x: 20, y: 15)))
        #expect(!bounds.contains(MirrorWindowFrame.Point(x: 15, y: 20)))
    }
}
