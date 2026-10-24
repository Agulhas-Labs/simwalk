//
// Copyright © Agulhas Labs
//

import CoreLocation
import SimWalkCore
import UIKit
import XCTest

/// The runner's half of a live session: launches the app `launch.json` names, then answers requests from the session directory until `LiveSessionLoop` says to stop.
///
/// **Only what the runner alone can do lives here** — the launch, the read, handing the device back. Which request comes next, when the session is idle, and what goes in `exit.json` are `LiveSessionLoop`'s, in the core, where `swift test` checks them.
///
/// A launch under a state is a walk's own launch of that state: its appearance and location set on the device, then `WalkRunner.launch(_:under:over:)`. Each request is answered in ``answer(_:)``, one case per action, so a new action is a new case there. A `step` goes through `StepPerformer` with the per-step setup `WalkRunner.follow` gives it; the guard, the sheet baseline and the answer are `LiveSessionStepper`'s.
@MainActor
final class LiveSessionServer {
    private let target: Target
    private let idle: LiveSessionIdle
    private let runnerCommit: String?
    /// The device's appearance as the host found it, put back as the session stops; `nil` when the host could not read it.
    private let foundAppearance: Walkbook.Theme?
    /// The app launched, once it is.
    private var app: XCUIApplication?
    private var bundleID = ""
    /// What the session launched, which a `relaunch` launches again.
    private var launched: LiveSessionLaunch?
    /// The location the device was simulating before the launch state set its own; read only when it does.
    private var foundLocation: XCUILocation?
    private var setsLocation = false
    /// The orientation the device was in before the launch state set its own; read only when it does (SimWalk#199).
    private var foundOrientation: UIDeviceOrientation?
    private var setsOrientation = false
    /// Whether a launch turned the device to a landscape app, so the session hands the orientation back (SimWalk#222).
    private var turnedToApp = false
    /// The session's steps: the guard, the sheet baseline kept across them, and the answer — the core's, under the walk's own quiet period.
    private var stepper = LiveSessionStepper(quiet: WalkRunner.settleQuiet)
    /// The progress file `session start` began, taken over for `running`, each step and the end; `nil` when nobody is watching.
    private let progress: ProgressWriter?

    init(target: Target, idle: LiveSessionIdle, runnerCommit: String?, foundAppearance: Walkbook.Theme?, progress: ProgressWriter?) {
        self.target = target
        self.idle = idle
        self.runnerCommit = runnerCommit
        self.foundAppearance = foundAppearance
        self.progress = progress
    }

    /// Serves the session to its end and returns the exit record written for it.
    ///
    /// The heartbeat starts here, before the loop launches the app, so a runner that dies anywhere from the launch on leaves `session list` a bound on when (``LiveSessionHeartbeat``); the loop stops it once `exit.json` is down.
    ///
    /// On a device there is no heartbeat file to start (the socket's liveness is the host's to probe), so the loop takes `.onDevice`.
    func serve() -> LiveSessionExit {
        switch target {
        case let .simulator(layout):
            let channel = LiveSessionChannel(layout: layout)
            return LiveSessionLoop(channel: channel, idle: idle, progress: progress).run(
                heartbeat: LiveSessionHeartbeat.start(on: channel),
                start: start,
                answer: answer,
                handBack: handBack,
                now: { Date() },
                pause: { Thread.sleep(forTimeInterval: $0) }
            )
        case let .device(launch, session, container):
            let transport = DeviceSessionTransport(launch: launch, session: session, container: container)
            return DeviceSessionLoop(transport: transport, idle: idle, progress: progress).run(
                heartbeat: .onDevice,
                start: start,
                answer: answer,
                handBack: handBack,
                now: { Date() },
                pause: { Thread.sleep(forTimeInterval: $0) }
            )
        }
    }

    /// The session id: each read's nonce, what tells this session's reads from another's — a simulator's directory name, or the id the device was launched with.
    private var sessionID: String {
        switch target {
        case let .simulator(layout):
            layout.directory.lastPathComponent
        case let .device(_, session, _):
            session
        }
    }

    private var isDevice: Bool {
        if case .device = target {
            return true
        }
        return false
    }

    /// Launches the app under the launch state, as a walk launches a state — or plain, on the device as it stands, without one.
    private func start(_ launch: LiveSessionLaunch) throws -> LiveSessionReady {
        let app = XCUIApplication(bundleIdentifier: launch.appBundleID)
        self.app = app
        bundleID = launch.appBundleID
        launched = launch
        let turned = try self.launch(app, as: launch)
        return LiveSessionReady(device: WalkRunner.device(), runnerCommit: runnerCommit, readyAt: Date(), notes: turned ? [DeviceAlignment.note()] : nil)
    }

    /// Ends `app` and launches it under `launch`'s state — the start's launch, and every `relaunch`'s, so the two cannot differ.
    ///
    /// The location the device simulated before is taken once, at the first launch that sets one, so a relaunch cannot take the state's own location for it.
    @discardableResult
    private func launch(_ app: XCUIApplication, as launch: LiveSessionLaunch) throws -> Bool {
        app.terminate()
        if let state = launch.state {
            // The host refuses a location on a device, which cannot simulate one; if one arrives anyway, fail rather than set it.
            if isDevice, state.location != nil {
                throw WalkRunner.InspectRefusal(description: "a launch state's location is not honoured on a physical device")
            }
            let baseEnvironment = AnimationsOptIn.inserting(AnimationsOptIn.library(in: ProcessInfo.processInfo.environment), into: app.launchEnvironment)
            XCUIDevice.shared.appearance = WalkRunner.style(state.theme)
            if let location = state.location {
                if !setsLocation {
                    foundLocation = XCUIDevice.shared.location
                }
                setsLocation = true
                XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: location.latitude, longitude: location.longitude))
            }
            if foundOrientation == nil {
                foundOrientation = XCUIDevice.shared.orientation
            }
            if turnedToApp, state.orientation == nil, let foundOrientation {
                XCUIDevice.shared.orientation = WalkRunner.handedBack(foundOrientation)
            }
            if state.orientation != nil {
                setsOrientation = true
                XCUIDevice.shared.orientation = WalkRunner.orientation(of: state, found: foundOrientation ?? .portrait)
            }
            WalkRunner.launch(app, under: state, over: baseEnvironment)
            // A portrait-only app keeps its frame whatever the device is asked, so the start fails here rather than hand an agent a portrait app under a landscape state.
            if let stated = state.orientation {
                let frame = WalkRunner.settledFrame(of: app, stated: stated)
                if let refusal = OrientationCheck.refusal(stated: stated, frame: frame) {
                    throw WalkRunner.InspectRefusal(description: "the launch state's orientation was not applied: \(refusal)")
                }
            }
        } else {
            app.launchEnvironment = AnimationsOptIn.inserting(AnimationsOptIn.library(in: ProcessInfo.processInfo.environment), into: app.launchEnvironment)
            app.launch()
        }
        return alignedToApp(app, stated: launch.state?.orientation)
    }

    /// Turns the device to a landscape app on a device held portrait, answering whether it did (SimWalk#222).
    private func alignedToApp(_ app: XCUIApplication, stated: Walkbook.Orientation?) -> Bool {
        if foundOrientation == nil {
            foundOrientation = XCUIDevice.shared.orientation
        }
        guard let foundOrientation, WalkRunner.alignDevice(to: app, stated: stated, found: foundOrientation) else { return false }
        turnedToApp = true
        return true
    }

    /// One request's answer.
    private func answer(_ request: LiveSessionRequest) throws -> LiveSessionResponse {
        guard let app else {
            throw WalkRunner.InspectRefusal(description: "the session answered a request before its app was launched")
        }
        switch request.action {
        case .read:
            var picture: Data?
            let screen = try WalkRunner.liveScreen(of: app, bundleID: bundleID, runnerCommit: runnerCommit, nonce: sessionID, kept: { picture = $0 })
            stepper.remember(screen)
            // Only an app that was read: a screenshot of one not running fails XCTest, where the host's refusal is clean. A textless screen's picture was taken for its signature and is reused.
            let screenshot = request.screenshot && screen.tree != nil && screen.appState != .notRunning ? picture ?? WalkRunner.screenshot(of: app) : nil
            return LiveSessionResponse(n: request.n, action: .read, screen: screen, screenshot: screenshot)
        case .step:
            return try step(request, in: app)
        case .relaunch:
            guard let launched else {
                throw WalkRunner.InspectRefusal(description: "the session was asked to relaunch before it had launched")
            }
            return try stepper.relaunch(
                request,
                screen: WalkRunner.Device(app: app, springboard: XCUIApplication(bundleIdentifier: StepPerformer.springboardBundleID), started: Date()),
                launch: { try launch(app, as: launched) },
                read: { try WalkRunner.liveScreen(of: app, bundleID: bundleID, runnerCommit: runnerCommit, nonce: sessionID) }
            )
        case .scroll:
            guard let scroll = request.scroll else {
                throw WalkRunner.InspectRefusal(description: "scroll request \(request.n) names no scroll")
            }
            return try stepper.scroll(
                request,
                screen: WalkRunner.Device(app: app, springboard: XCUIApplication(bundleIdentifier: StepPerformer.springboardBundleID), started: Date()),
                drag: { try StepPerformer.drag(scroll, in: app) },
                read: { try WalkRunner.liveScreen(of: app, bundleID: bundleID, runnerCommit: runnerCommit, nonce: sessionID) }
            )
        case .end:
            // The loop has already handed the device back; this is the acknowledgement, and the exit record follows it.
            return LiveSessionResponse(n: request.n, action: .end)
        }
    }

    /// Takes a `step` request's step with `StepPerformer`, set up as `WalkRunner.follow` sets up each step — a new `SheetReads`, the sheet scope `LiveSessionStepper` found — and answers with the step as it landed and the screen it landed on.
    private func step(_ request: LiveSessionRequest, in app: XCUIApplication) throws -> LiveSessionResponse {
        let sheetReads = WalkRunner.SheetReads(app: app)
        let quiet = stepper.quiet
        let budget = stepper.budget
        return try stepper.answer(
            request,
            screen: WalkRunner.Device(app: app, springboard: XCUIApplication(bundleIdentifier: StepPerformer.springboardBundleID), started: Date()),
            sheetReads: sheetReads,
            pixels: { WalkRunner.pixelSignature(for: $0, of: app) },
            perform: { step, scope in
                switch try StepPerformer(app: app, quiet: quiet, budget: budget, sheetScope: scope, sheetReads: sheetReads).perform(step) {
                case .landed:
                    .landed(step, sheetClosed: false, bound: nil)
                case let .landedOn(node):
                    .landed(step, sheetClosed: false, bound: node)
                case let .landedAs(recorded, sheetClosed):
                    .landed(recorded, sheetClosed: sheetClosed, bound: nil)
                case let .blocked(reason, cause):
                    .blocked(reason: reason ?? cause.map { "cause: \($0.rawValue)" })
                }
            },
            read: { try WalkRunner.liveScreen(of: app, bundleID: bundleID, runnerCommit: runnerCommit, nonce: sessionID) }
        )
    }

    /// Puts back what the launch changed on the device — the appearance, as a walk does at its end, and the location when the state set one.
    private func handBack() {
        if let foundAppearance {
            XCUIDevice.shared.appearance = WalkRunner.style(foundAppearance)
        }
        if setsLocation {
            XCUIDevice.shared.location = foundLocation
        }
        if setsOrientation || turnedToApp, let foundOrientation {
            XCUIDevice.shared.orientation = WalkRunner.handedBack(foundOrientation)
        }
    }
}

extension LiveSessionServer {
    /// Where the session is served: a simulator's session directory, or a physical device's own container and socket (SimWalk#116).
    enum Target {
        case simulator(LiveSessionLayout)
        case device(launch: LiveSessionLaunch, session: String, container: URL)
    }
}
