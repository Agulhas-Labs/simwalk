//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A state's capture is read settled and refused under a system alert, in the one sequence that can make a capture (SimWalk#39 item 5).
struct SettledCaptureTests {
    private static let screen = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
    private static let appScreen = AXNode(type: "Application", frame: screen, label: "App", children: [
        AXNode(type: "Window", frame: screen, children: [AXNode(type: "Button", frame: screen, label: "Continue")]),
    ])
    private static let clearSpringboard = AXNode(type: "Application", frame: screen, children: [AXNode(type: "Window", frame: screen)])
    private static let alertSpringboard = AXNode(type: "Application", frame: screen, children: [
        AXNode(type: "Alert", frame: screen, label: "“App” Would Like to Send You Notifications"),
    ])

    /// A still app with nothing over it is captured settled, the picture bracketed by two reads and SpringBoard read after the picture.
    @Test
    func aStillScreenWithNothingOverItIsCapturedSettled() throws {
        let source = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard))

        let capture = try SettledCapture.take(from: source, quiet: 0.2, budget: 1, interval: 0.1, motion: nil)

        #expect(capture.didSettle)
        #expect(capture.tree == Self.appScreen)
        #expect(capture.screenshot == ScriptedSource.picture)
        #expect(source.calls.suffix(3) == ["screenshot", "app", "springboard"])
    }

    /// A capture carries the watch's figures (SimWalk#67): the read where the screen arrived as its settle time, the cadence it was read at, and every read the watch compared — and an unsettled one carries no settle time, and does not count the read taken after the watch gave up.
    @Test
    func aCaptureCarriesItsSettleTimeCadenceAndReads() throws {
        let arriving = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), departing: Self.departingScreen)
        let moving = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), moving: true)

        let watch = MotionWatch(lastStep: .openURL(url: "fixture://page"), landing: 0.0424)
        let settled = try SettledCapture.take(from: arriving, quiet: 0.2, budget: 1, interval: 0.1, motion: watch)
        let unsettled = try SettledCapture.take(from: moving, quiet: 0.2, budget: 0.5, interval: 0.1, motion: watch)

        #expect(settled.motion == CaptureManifest.Motion(
            settleMilliseconds: 100,
            readIntervalMilliseconds: 100,
            readCount: arriving.calls.count { $0 == "app" },
            measuredReadSpacingMilliseconds: 100,
            landingMilliseconds: 42,
            shifts: []
        ))
        #expect(unsettled.motion == CaptureManifest.Motion(
            settleMilliseconds: nil,
            readIntervalMilliseconds: 100,
            readCount: moving.calls.count { $0 == "app" } - 1,
            measuredReadSpacingMilliseconds: 100,
            landingMilliseconds: 42,
            shifts: []
        ))
    }

    /// A watch that is not asked for motion keeps no reads and makes no record — "motion not recorded" — and one asked for it runs the shift rule over the reads it kept: a banner that lands mid-watch is reported against the row it pushed, at the read that saw it.
    @Test
    func aWatchKeepsItsReadsOnlyWhenAskedAndReportsWhatTheyShowMoving() throws {
        let row = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 44), label: "Row 1")
        var pushed = row
        pushed.frame.y = 168
        let banner = AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 60), label: "Banner")
        let loaded = AXNode(type: "Application", frame: Self.screen, label: "App", children: [AXNode(type: "Window", frame: Self.screen, children: [row])])
        let bannered = AXNode(type: "Application", frame: Self.screen, label: "App", children: [AXNode(type: "Window", frame: Self.screen, children: [banner, pushed])])

        let unasked = try SettledCapture.take(from: ScriptedSource(app: bannered, springboard: .success(Self.clearSpringboard), departing: loaded), quiet: 0.2, budget: 1, interval: 0.1, motion: nil)
        let asked = try SettledCapture.take(
            from: ScriptedSource(app: bannered, springboard: .success(Self.clearSpringboard), departing: loaded),
            quiet: 0.2,
            budget: 1,
            interval: 0.1,
            motion: MotionWatch(lastStep: nil, landing: nil)
        )

        #expect(unasked.motion == nil)
        #expect(asked.motion?.landingMilliseconds == nil)
        #expect(asked.motion?.shifts?.map(\.element.label) == ["Row 1"])
        #expect(asked.motion?.shifts?.first?.movedAtMilliseconds == 100)
        #expect(asked.motion?.shifts?.first?.cause?.element.label == "Banner")
    }

    /// A capture carries the moment its picture was taken — the read a rolling window is computed back from — not when the sequence ended, settled or moving.
    @Test
    func aCaptureCarriesTheMomentItsPictureWasTaken() throws {
        let still = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), springboardCost: 5)
        let moving = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), moving: true, springboardCost: 5)

        let settled = try SettledCapture.take(from: still, quiet: 0.2, budget: 1, interval: 0.1, motion: nil)
        let unsettled = try SettledCapture.take(from: moving, quiet: 0.2, budget: 0.5, interval: 0.1, motion: nil)

        #expect(settled.didSettle)
        #expect(settled.takenAfter > 0)
        #expect(settled.takenAfter == still.pictureAt)
        #expect(still.elapsed() > settled.takenAfter)
        #expect(!unsettled.didSettle)
        #expect(unsettled.takenAfter > 0)
        #expect(unsettled.takenAfter == moving.pictureAt)
        #expect(moving.elapsed() > unsettled.takenAfter)
    }

    /// An alert in SpringBoard's tree refuses the capture, naming it: the app's tree under it is not the screen photographed.
    @Test
    func anAlertOverTheAppRefusesTheCapture() {
        let source = ScriptedSource(app: Self.appScreen, springboard: .success(Self.alertSpringboard))

        #expect(throws: SettledCapture.Refusal(description: "a system alert '“App” Would Like to Send You Notifications' covers the app")) {
            try SettledCapture.take(from: source, quiet: 0.2, budget: 1, interval: 0.1, motion: nil)
        }
    }

    /// A screen that never settles is refused under an alert too: the flag for a moving screen is no way around the check.
    @Test
    func aMovingScreenUnderAnAlertIsRefusedToo() {
        let source = ScriptedSource(app: Self.appScreen, springboard: .success(Self.alertSpringboard), moving: true)

        #expect(throws: SettledCapture.Refusal.self) {
            try SettledCapture.take(from: source, quiet: 0.2, budget: 0.5, interval: 0.1, motion: nil)
        }
        #expect(source.calls.contains("springboard"))
    }

    /// SpringBoard's tree unreadable is a refusal too: nothing can say the app is uncovered.
    @Test
    func anUnreadableSpringboardRefusesTheCapture() {
        let source = ScriptedSource(app: Self.appScreen, springboard: .failure(ScriptedSource.Unreadable()))

        #expect(throws: SettledCapture.Refusal(description: "reading SpringBoard's tree: unreadable")) {
            try SettledCapture.take(from: source, quiet: 0.2, budget: 1, interval: 0.1, motion: nil)
        }
    }

    /// A still spinner inside the app's chrome is waited on, not settled on, and filed unsettled when it never goes — so the capture the chrome-only warning names is not counted settled beside it (SimWalk#81).
    @Test
    func aStillSpinnerInTheAppsChromeIsCapturedUnsettled() throws {
        let source = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), loading: Self.spinnerScreen)

        let capture = try SettledCapture.take(from: source, quiet: 0.25, budget: 2.5, interval: 0.25, motion: nil)

        #expect(!capture.didSettle)
        #expect(capture.tree == Self.spinnerScreen)
        #expect(ScreenContentCheck.isChromeOnly(capture.tree))
        #expect(source.elapsed() > 2.5)
    }

    /// A screen loading at 10 s, past a 3 s cap and inside the 15 s one, is still captured settled — the cap is `SettleWindow.contentWait` and shortening it fails here (SimWalk#81).
    @Test
    func aScreenThatLoadsWithinTheContentWaitIsCapturedSettled() throws {
        let source = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), loading: Self.spinnerScreen, loadsAt: 10)

        let capture = try SettledCapture.take(from: source, quiet: 0.25, budget: 2.5, interval: 0.25, motion: nil)

        #expect(capture.didSettle)
        #expect(capture.tree == Self.appScreen)
    }

    /// A spinner that never goes is watched for the whole content wait before it is filed.
    @Test
    func aSpinnerThatNeverGoesIsWatchedForTheWholeContentWait() throws {
        let source = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), loading: Self.spinnerScreen)

        let capture = try SettledCapture.take(from: source, quiet: 0.25, budget: 2.5, interval: 0.25, motion: nil)

        #expect(!capture.didSettle)
        #expect(source.elapsed() >= SettleWindow.contentWait)
    }

    /// A screen that loads after its budget would have run out is still captured settled: the budget runs from when its content arrived, not from when the watch began (SimWalk#81).
    @Test
    func aScreenThatLoadsLateIsCapturedSettledOnceItArrives() throws {
        let source = ScriptedSource(app: Self.appScreen, springboard: .success(Self.clearSpringboard), loading: Self.spinnerScreen, loadsAt: 4)

        let capture = try SettledCapture.take(from: source, quiet: 0.25, budget: 2.5, interval: 0.25, motion: nil)

        #expect(capture.didSettle)
        #expect(capture.tree == Self.appScreen)
        #expect((source.pictureAt ?? 0) >= 4)
    }

    /// The first read after a push can still hold the screen being left — a navigating step lands before its transition has finished — and that passing content must not spend the spinner's wait: the budget runs from when the *current* content arrived (SimWalk#81).
    @Test
    func theScreenBeingLeftDoesNotSpendTheSpinnersWait() throws {
        let source = ScriptedSource(
            app: Self.appScreen,
            springboard: .success(Self.clearSpringboard),
            loading: Self.spinnerScreen,
            loadsAt: 4,
            departing: Self.departingScreen
        )

        let capture = try SettledCapture.take(from: source, quiet: 0.25, budget: 2.5, interval: 0.25, motion: nil)

        #expect(capture.didSettle)
        #expect(capture.tree == Self.appScreen)
    }

    /// The list a detail screen is pushed from, mid-transition: a labelled row under the navigation bar.
    private static let departingScreen = AXNode(type: "Application", frame: screen, label: "App", children: [
        AXNode(type: "Window", frame: screen, children: [
            AXNode(type: "Cell", frame: AXNode.Frame(x: 0, y: 200, width: 402, height: 44), label: "Heart Rate"),
        ]),
    ])

    /// The specimen's shape: a back button in the navigation bar, an unlabelled spinner, and the tab bar — nothing of the screen.
    private static let spinnerScreen = AXNode(type: "Application", frame: screen, label: "App", children: [
        AXNode(type: "Window", frame: screen, children: [
            AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 62, width: 402, height: 54), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 68, width: 44, height: 44), label: "Back"),
            ]),
            AXNode(type: "ActivityIndicator", frame: AXNode.Frame(x: 191, y: 427, width: 20, height: 20), value: "1"),
            AXNode(type: "TabBar", frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83), children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 20, y: 795, width: 80, height: 48), label: "Summary"),
            ]),
        ]),
    ])
}

private extension SettledCaptureTests {
    /// A device replayed from a script: `departing` on the first read, if given; then the app's tree still, or changing at every read, or `loading` until the clock reaches `loadsAt`; SpringBoard's tree, or a failure to read it, taking `springboardCost` of the clock to read.
    final class ScriptedSource: CaptureSource {
        static let picture = Data([0x89, 0x50, 0x4E, 0x47])

        private let app: AXNode
        private let springboard: Result<AXNode, Unreadable>
        private let moving: Bool
        private let springboardCost: TimeInterval
        private let loading: AXNode?
        private let loadsAt: TimeInterval
        private let departing: AXNode?
        private var clock: TimeInterval = 0
        private var reads = 0
        private(set) var calls: [String] = []
        /// The clock at the last picture taken.
        private(set) var pictureAt: TimeInterval?

        init(
            app: AXNode,
            springboard: Result<AXNode, Unreadable>,
            moving: Bool = false,
            springboardCost: TimeInterval = 0,
            loading: AXNode? = nil,
            loadsAt: TimeInterval = .infinity,
            departing: AXNode? = nil
        ) {
            self.app = app
            self.springboard = springboard
            self.moving = moving
            self.springboardCost = springboardCost
            self.loading = loading
            self.loadsAt = loadsAt
            self.departing = departing
        }

        func appTree() throws -> AXNode {
            calls.append("app")
            reads += 1
            if let departing, reads == 1 {
                return departing
            }
            if let loading, clock < loadsAt {
                return loading
            }
            guard moving else { return app }
            var changed = app
            changed.label = "App \(reads)"
            return changed
        }

        func springboardTree() throws -> AXNode {
            calls.append("springboard")
            clock += springboardCost
            return try springboard.get()
        }

        func screenshot() -> Data {
            calls.append("screenshot")
            pictureAt = clock
            return Self.picture
        }

        func elapsed() -> TimeInterval {
            clock
        }

        func pause(_ interval: TimeInterval) {
            clock += interval
        }
    }
}

extension SettledCaptureTests.ScriptedSource {
    struct Unreadable: Error, CustomStringConvertible {
        var description: String {
            "unreadable"
        }
    }
}
