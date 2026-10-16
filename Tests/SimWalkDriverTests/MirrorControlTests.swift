//
// Copyright © Agulhas Labs
//

import CoreGraphics
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// The mirror's device-control path over scripted seams: the guard refuses before any event, the poster posts the spike's sequences at the mapped points and re-checks focus after each, and the window, menu, capture and lock refuse or land as Brief §8 says.
///
/// Nothing here posts a real event.
struct MirrorControlTests {
    private static let window = MirrorWindowFrame(windowID: 1018, x: 672, y: 118, width: 383, height: 843)

    /// G3: a reader answering "Terminal" every time is refused naming it, after one activation and exactly ten reads 200 ms apart — and nothing is posted.
    @Test
    func theGuardRefusesWhenMirroringIsNotFrontmost() throws {
        let log = SeamLog(frontmost: Array(repeating: "Terminal", count: 20))
        let poster = log.poster(Self.window)

        #expect(throws: MirrorFocusRefusal(frontmost: "Terminal", moment: .beforeAction)) {
            let clearance = try log.focus.clear()
            _ = try poster.tap(at: MirrorFraction(x: 0.5, y: 0.5), clearance: clearance)
        }
        #expect(log.activations == 1)
        #expect(log.reads == 10)
        #expect(log.steps == Array(repeating: .pause(0.2), count: 10))
        #expect(log.events.isEmpty)
    }

    /// Mirroring named on the third read clears there: three reads, three waits.
    @Test
    func theGuardClearsOnTheThirdRead() throws {
        let log = SeamLog(frontmost: ["Terminal", "Terminal", MirrorFocus.appName])

        _ = try log.focus.clear()

        #expect(log.activations == 1)
        #expect(log.reads == 3)
        #expect(log.steps == Array(repeating: .pause(0.2), count: 3))
    }

    /// A tap is pointer-arrives, 60 ms, press, 70 ms, release at the mapped point, then one read of focus.
    @Test
    func aTapMovesPressesAndReleasesAtTheMappedPoint() throws {
        let log = SeamLog(frontmost: [MirrorFocus.appName])
        let poster = log.poster(Self.window)
        let point = MirrorWindowFrame.Point(x: 863.5, y: 539.5)

        _ = try poster.tap(at: MirrorFraction(x: 0.5, y: 0.5), clearance: Self.clearance())

        #expect(log.steps == [.event(.mouse(.moved, point: point)), .pause(0.06), .event(.mouse(.down, point: point)), .pause(0.07), .event(.mouse(.up, point: point))])
        #expect(log.reads == 1)
    }

    /// Focus read after a gesture's last event and found elsewhere refuses the call as moved during the gesture, the events already posted.
    @Test
    func theAfterGestureCheckRefusesWhenFocusMoved() throws {
        let log = SeamLog(frontmost: ["Safari"])
        let poster = log.poster(Self.window)

        #expect(throws: MirrorFocusRefusal(frontmost: "Safari", moment: .duringGesture)) {
            _ = try poster.tap(at: MirrorFraction(x: 0.5, y: 0.5), clearance: Self.clearance())
        }
        #expect(log.events.count == 3)
        #expect(log.activations == 0)
    }

    /// A drag presses at the start, posts 24 dragged events evenly along the line with the time split between them — the last on the target — and releases at the target.
    @Test
    func aDragInterpolatesTwentyFourStepsEndingAtTheTarget() throws {
        let log = SeamLog(frontmost: [MirrorFocus.appName])
        let window = MirrorWindowFrame(windowID: 1, x: 100, y: 200, width: 400, height: 800)
        let poster = log.poster(window)
        let start = MirrorWindowFrame.Point(x: 300, y: 920)
        let end = MirrorWindowFrame.Point(x: 300, y: 440)

        _ = try poster.drag(from: MirrorFraction(x: 0.5, y: 0.9), to: MirrorFraction(x: 0.5, y: 0.3), milliseconds: 480, clearance: Self.clearance())

        #expect(log.events.first == .mouse(.moved, point: start))
        #expect(log.events.dropFirst().first == .mouse(.down, point: start))
        #expect(log.dragged.count == 24)
        #expect(log.dragged.first == MirrorWindowFrame.Point(x: 300, y: 900))
        #expect(log.dragged.last == end)
        #expect(log.events.last == .mouse(.up, point: end))
        #expect(log.steps.filter { $0 == .pause(0.02) }.count == 24)
    }

    /// Scrolling posts one wheel line per event, 25 ms apart: positive lines turn the vertical wheel (count 1, `wheel1`) by -1, negative horizontal ones the horizontal wheel (count 2, `wheel2`) by +1.
    @Test
    func scrollPostsOneWheelLinePerEventWithTheSpikesSignAndWheel() throws {
        let log = SeamLog(frontmost: [MirrorFocus.appName, MirrorFocus.appName])
        let poster = log.poster(Self.window)
        let centre = try MirrorFraction(x: 0.5, y: 0.5)

        _ = try poster.scroll(lines: 3, horizontal: false, at: centre, clearance: Self.clearance())
        let vertical = log.events
        log.steps.removeAll()
        _ = try poster.scroll(lines: -2, horizontal: true, at: centre, clearance: Self.clearance())

        #expect(vertical.dropFirst() == Array(repeating: .wheel(count: 1, wheel1: -1, wheel2: 0), count: 3)[...])
        #expect(log.events.dropFirst() == Array(repeating: .wheel(count: 2, wheel1: 0, wheel2: 1), count: 2)[...])
        #expect(log.steps.filter { $0 == .pause(0.025) }.count == 2)
    }

    /// A tap whose point lies under a floating panel is refused before any event, naming the panel's owner as a point covered.
    @Test
    func aCoveredTapPostsNothing() throws {
        let log = SeamLog(frontmost: [MirrorFocus.appName])
        log.covering = [MirrorWindowStack.Window(windowID: 50, owner: "Raycast", layer: 3, alpha: 1, bounds: MirrorWindowStack.Bounds(x: 800, y: 500, width: 200, height: 100))]

        #expect(throws: MirrorFocusRefusal(frontmost: "Raycast", moment: .pointCovered)) {
            _ = try log.poster(Self.window).tap(at: MirrorFraction(x: 0.5, y: 0.5), clearance: Self.clearance())
        }
        #expect(log.events.isEmpty)
        #expect(log.reads == 0)
    }

    /// A drag whose start and end are clear but whose path crosses a window is refused before its first event: every interpolated step is checked.
    @Test
    func aDragCrossingAWindowPostsNothing() throws {
        let log = SeamLog(frontmost: [MirrorFocus.appName])
        log.covering = [MirrorWindowStack.Window(windowID: 50, owner: "Notes", layer: 0, alpha: 1, bounds: MirrorWindowStack.Bounds(x: 672, y: 500, width: 383, height: 40))]

        #expect(throws: MirrorFocusRefusal(frontmost: "Notes", moment: .pointCovered)) {
            _ = try log.poster(Self.window).drag(from: MirrorFraction(x: 0.5, y: 0.8), to: MirrorFraction(x: 0.5, y: 0.2), milliseconds: 300, clearance: Self.clearance())
        }
        #expect(log.events.isEmpty)
    }

    /// A scroll at a point in the window's transparent corner is refused as a bad argument before the window list is read or any event posted.
    @Test
    func aScrollInACornerIsRefusedAsInput() throws {
        let log = SeamLog(frontmost: [MirrorFocus.appName])
        let corner = try MirrorFraction(x: 0.03, y: 0.06)

        #expect(throws: MirrorWindowFrame.PassThrough(fraction: corner)) {
            _ = try log.poster(Self.window).scroll(lines: 3, horizontal: false, at: corner, clearance: Self.clearance())
        }
        #expect(log.events.isEmpty)
    }

    /// The window server's dictionary becomes a record with its alpha; one with no alpha reads as opaque, so it counts as covering.
    @Test
    func aWindowRecordReadsAlphaAndDefaultsToOpaque() {
        var info = Self.windowInfo(number: 30, owner: "Dock", layer: 20, bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117))
        let opaque = MirrorWindow.record(info)
        info["kCGWindowAlpha"] = NSNumber(value: 0.0)

        #expect(opaque == MirrorWindowStack.Window(windowID: 30, owner: "Dock", layer: 20, alpha: 1, bounds: MirrorWindowStack.Bounds(x: 0, y: 0, width: 1728, height: 1117)))
        #expect(MirrorWindow.record(info)?.alpha == 0)
    }

    /// The window is the largest layer-0 one Mirroring owns: its strips, its icon square, another app's larger window and a raised layer are passed over.
    @Test
    func theWindowIsMirroringsLargestLayerZeroWindow() throws {
        let windows: [[String: Any]] = [
            Self.windowInfo(number: 1015, owner: MirrorFocus.appName, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1728, height: 33)),
            Self.windowInfo(number: 1021, owner: MirrorFocus.appName, layer: 0, bounds: CGRect(x: 0, y: 617, width: 54, height: 54)),
            Self.windowInfo(number: 1018, owner: MirrorFocus.appName, layer: 0, bounds: CGRect(x: 672, y: 118, width: 383, height: 843)),
            Self.windowInfo(number: 2000, owner: MirrorFocus.appName, layer: 25, bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117)),
            Self.windowInfo(number: 3000, owner: "Safari", layer: 0, bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117)),
        ]

        #expect(try MirrorWindow.frame(among: windows) == Self.window)
        #expect(throws: MirrorControlError.noWindow) {
            try MirrorWindow.frame(among: Array(windows.suffix(2)))
        }
    }

    /// A failed menu click refuses naming the item; a good one clicks the enum's own title in the View menu.
    @Test
    func aFailedMenuClickRefusesNamingTheItem() throws {
        var scripts: [String] = []
        let failing = Shell(script: { _, arguments, _ in
            scripts.append(arguments.last ?? "")
            return Shell.Result(status: 1, standardOutput: "", standardError: "execution error: Can’t get menu item \"App Switcher\". (-1728)")
        })

        #expect(throws: MirrorControlError.noMenuItem(title: "App Switcher", reason: "execution error: Can’t get menu item \"App Switcher\". (-1728)")) {
            try MirrorMenu(shell: failing).click(.appSwitcher, clearance: Self.clearance())
        }
        #expect(scripts == ["tell application \"System Events\" to tell process \"iPhone Mirroring\" to click menu item \"App Switcher\" of menu \"View\" of menu bar 1"])
    }

    /// A capture is by window id; a zero exit that left no image refuses naming Screen Recording, and a non-zero one refuses with what screencapture said.
    @Test
    func aCaptureThatLeftNoImageRefusesNamingScreenRecording() throws {
        let directory = try TemporaryDirectory()
        let file = directory.url.appendingPathComponent("frame.png")
        var arguments: [String] = []
        let silent = Shell(script: { _, given, _ in
            arguments = given
            return Shell.Result(status: 0, standardOutput: "", standardError: "")
        })
        let failing = Shell(script: { _, _, _ in Shell.Result(status: 1, standardOutput: "", standardError: "could not create image from window") })

        #expect(throws: MirrorControlError.captureMissing(path: file.path)) {
            try MirrorCapture(shell: silent).capture(window: Self.window, to: file, clearance: Self.clearance())
        }
        #expect(arguments == ["-o", "-x", "-l", "1018", file.path])
        #expect(MirrorControlError.captureMissing(path: file.path).localizedDescription.contains("Screen Recording"))
        #expect(throws: MirrorControlError.captureFailed(reason: "could not create image from window")) {
            try MirrorCapture(shell: failing).capture(window: Self.window, to: file, clearance: Self.clearance())
        }
    }

    /// The lock file is `<root>/mirror/.lock`, made under the root it is given and held while the body runs.
    @Test
    func theLockFileLandsUnderTheInjectedRoot() throws {
        let directory = try TemporaryDirectory()
        let lock = MirrorCallLock(root: directory.url)

        let existed = try lock.withLock { FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("mirror/.lock").path) }

        #expect(existed)
        #expect(lock.file.path.hasPrefix(directory.url.path))
        #expect(MirrorCallLock.standard().file.path.hasSuffix("/.simwalk/mirror/.lock"))
    }

    /// A clearance minted the only way there is: the decision passing on Mirroring's name.
    private static func clearance() throws -> MirrorFocus.Clearance {
        try MirrorFocus.recheck(MirrorFocus.appName, at: .beforeAction)
    }

    /// One window as `CGWindowListCopyWindowInfo` describes it.
    private static func windowInfo(number: Int, owner: String, layer: Int, bounds: CGRect) -> [String: Any] {
        [
            "kCGWindowNumber": NSNumber(value: number),
            "kCGWindowOwnerName": owner,
            "kCGWindowLayer": NSNumber(value: layer),
            "kCGWindowBounds": bounds.dictionaryRepresentation,
        ]
    }
}

extension MirrorControlTests {
    /// Everything the seams were asked to do, in order: events posted and waits taken, with the guard's activations and reads counted.
    final class SeamLog {
        var steps: [Step] = []
        private(set) var activations = 0
        private(set) var reads = 0
        private var frontmost: [String]

        init(frontmost: [String]) {
            self.frontmost = frontmost
        }

        /// The events alone.
        var events: [MirrorEvent] {
            steps.compactMap(\.event)
        }

        /// The points of the dragged events, in order.
        var dragged: [MirrorWindowFrame.Point] {
            events.compactMap(\.draggedPoint)
        }

        /// A guard over this log: activation counted, reads answered from the script in order, waits recorded.
        var focus: MirrorFocusGuard {
            MirrorFocusGuard(activate: { self.activations += 1 }, readFrontmost: { self.read() }, pause: { self.pause($0) })
        }

        /// Windows the scripted window server lists in front of the poster's own.
        var covering: [MirrorWindowStack.Window] = []

        /// A poster over this log: the window list is `covering` then the window itself, events and waits recorded.
        func poster(_ window: MirrorWindowFrame) -> MirrorPoster {
            let own = MirrorWindowStack.Window(windowID: window.windowID, owner: MirrorFocus.appName, layer: 0, alpha: 1, bounds: MirrorWindowStack.Bounds(x: window.x, y: window.y, width: window.width, height: window.height))
            return MirrorPoster(window: window, focus: focus, stack: { MirrorWindowStack(windows: self.covering + [own], displays: []) }, post: { event, _ in self.post(event) }, pause: { self.pause($0) })
        }

        func post(_ event: MirrorEvent) {
            steps.append(.event(event))
        }

        func pause(_ seconds: TimeInterval) {
            steps.append(.pause(seconds))
        }

        private func read() -> String {
            reads += 1
            return frontmost.isEmpty ? "" : frontmost.removeFirst()
        }
    }
}

extension MirrorControlTests.SeamLog {
    /// An event posted or a wait taken.
    enum Step: Equatable {
        case event(MirrorEvent)
        case pause(TimeInterval)

        /// The event, `nil` for a wait.
        var event: MirrorEvent? {
            if case let .event(event) = self {
                return event
            }
            return nil
        }
    }
}

private extension MirrorEvent {
    /// Where a dragged event was posted, `nil` for any other event.
    var draggedPoint: MirrorWindowFrame.Point? {
        if case let .mouse(.dragged, point) = self {
            return point
        }
        return nil
    }
}
