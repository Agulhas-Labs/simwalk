//
// Copyright © Agulhas Labs
//

import CoreLocation
import SimWalkCore
import UIKit
import XCTest

/// The generic XCUITest executor: reads a walkbook, walks the app it names, writes a capture bundle.
///
/// **It has no compile-time knowledge of the app it drives.** The target application is deliberately unset on this target, so `XCUIApplication(bundleIdentifier:)` is the only handle on the app under validation and the bundle id arrives in the walkbook. That is what makes one runner serve every app and keeps SimWalk-generated code out of anybody's repo — the portability constraint the whole tool is built around (Brief §5, §7.4).
///
/// Inputs arrive as environment, because a test bundle takes no arguments: `xcodebuild test` forwards any `TEST_RUNNER_`-prefixed variable to the runner process with the prefix stripped, so the host driver passes `TEST_RUNNER_SIMWALK_WALKBOOK` and `TEST_RUNNER_SIMWALK_OUTPUT`.
///
/// `@MainActor` because XCUITest drives the app from the main thread and `snapshot()` hands back a non-`Sendable` value there. Stating it on the class keeps every step of a walk in one isolation domain instead of asserting the assumption at each call.
@MainActor
final class WalkRunner: XCTestCase {
    /// Whether any state of this walk sets a location — the device's own is read and handed back only then.
    private var setsLocation = false
    /// The location the device was simulating when the walk began, walked under by every state without its own.
    private var foundLocation: XCUILocation?
    /// The records the device walk's measure runs produced (`SIMWALK_PERFORMANCE_JSON`), filed on each capture they name (SimWalk#67, M4); empty on every other walk.
    private var measured = MeasuredPerformance()

    override func setUp() {
        super.setUp()
        // A walk is a plan; stopping at the first failure would leave a bundle claiming less than the run
        // actually learned. Screens report their own outcome instead.
        continueAfterFailure = true
    }

    /// Walks the walkbook named in the environment and writes its bundle.
    func testWalk() throws {
        let environment = ProcessInfo.processInfo.environment
        // The third mode (`simwalk inspect`, SimWalk#49), decided before a walkbook is looked for: a live read has
        // none. It lives in this test rather than a test of its own: every invocation selects its test with `-only-testing`, and the walk's selects this one.
        if environment[Input.inspect] == "1" {
            try inspect(environment)
            return
        }
        let outputPath = try XCTUnwrap(environment[Input.output], "\(Input.output) not set — the host driver passes it as TEST_RUNNER_\(Input.output)")
        let walkbook = try Self.walkbook(from: environment)
        let output = try Self.outputURL(for: outputPath, in: environment)
        // The second mode, decided before a bundle directory is prepared: a dry run writes a report, never a bundle.
        if environment[Input.dryRun] == "1" {
            try probeRoutes(of: walkbook, to: output)
            return
        }
        // Read before a bundle is prepared: the host wrote it, so a value that does not decode is a broken walk, never one without figures.
        measured = try MeasuredPerformance.read(from: environment)
        let writer = try CaptureBundleWriter(preparingAt: output)
        let started = Date()
        let app = XCUIApplication(bundleIdentifier: walkbook.appBundleID)

        // Every screen — and inside it every state — replays from a fresh launch, because a route states
        // how a screen is reached **from the launch state**. Walking them end to end would make each
        // screen's result depend on where the previous one left the app: the ambiguity
        // `WalkbookProblem.emptyRoute` refuses at authoring time, reintroduced by the runner.
        // Taken once, before any state has touched it: every state's environment is laid over this, never
        // over the one the state before it left on the shared `app`.
        let baseEnvironment = AnimationsOptIn.inserting(AnimationsOptIn.library(in: ProcessInfo.processInfo.environment), into: app.launchEnvironment)
        // The location the device was simulating before any state set one, read only when a state will: each
        // state without its own is walked under this, and the walk hands it back at the end.
        setsLocation = walkbook.screens.contains { $0.states.contains { $0.location != nil } }
        foundLocation = setsLocation ? XCUIDevice.shared.location : nil
        // The progress file the host started, taken over for `running` and each screen (`Docs/SIMWALK-PROGRESS.md`
        // §3). It only adds writes, every one of them silent when it fails: progress never fails a walk, and the
        // bundle is what it would be without it.
        let progress = environment[Input.progress].map { ProgressWriter.adopting(url: URL(fileURLWithPath: $0)) }
        let screenIDs = walkbook.screens.map(\.id)
        progress?.commit { $0.beginScreens(screenIDs) }
        var records: [CaptureManifest.ScreenRecord] = []
        for (position, screen) in walkbook.screens.enumerated() {
            let record = walk(screen, of: walkbook, in: app, over: baseEnvironment, writer: writer)
            records.append(record)
            progress?.commit { $0.finishScreen(record, at: position, of: screenIDs, in: writer.url) }
        }
        if setsLocation {
            XCUIDevice.shared.location = foundLocation
        }
        // The same reset once more after the last state, so the host's read after the walk says whether
        // the resets this walk relied on actually held — the device should be back where it was found.
        if let found = Self.deviceAppearance {
            XCUIDevice.shared.appearance = Self.style(found)
        }

        let manifest = try CaptureManifest(
            walkName: walkbook.name,
            appBundleID: walkbook.appBundleID,
            appBuildHash: environment[Input.buildHash] ?? "unknown",
            walkbookHash: WalkbookIdentity.hash(of: walkbook),
            device: Self.device(),
            startedAt: started,
            finishedAt: Date(),
            // Recorded from the quiet period the runner actually enforced, not from what the driver
            // asked for — an unparseable or non-positive `--settle` falls back to the default here, and
            // `settledTree` waits in whole `SettleWindow.interval` steps, so a request of 100ms is
            // satisfied by a capture that waited 250. A manifest restating either would report a
            // threshold no capture was taken under.
            settleQuietMilliseconds: SettleWindow.enforcedMilliseconds(forRequested: Self.settleQuiet),
            // The commit this runner was built from, as the host resolved it: the write half of the bundle
            // contract names itself, so a bundle can be traced to the runner that wrote it (SimWalk#16).
            runnerCommit: environment[Input.runnerCommit],
            // The value this walk's host generated and passed the runner, echoed back exactly as
            // `probeRoutes` echoes it into `RouteProbeReport.nonce` — what tells this bundle from one an
            // overlapping walk of the same build left (SimWalk#41). Absent when the host sent none.
            nonce: environment[Input.nonce],
            // How the host knew the build hash (`installed` for a device walk that installed the app itself); absent means read back.
            appBuildProvenance: environment[Input.buildProvenance].flatMap(CaptureManifest.AppBuildProvenance.init(rawValue:)),
            // What this runner did, from the key the host sets only when it launches the app with the library inserted.
            animations: AnimationsOptIn.recorded(in: environment),
            screens: records
        )
        // `finalise` is the confirmation: it refuses a manifest whose claims the directory does not
        // support, so a walk that returns without throwing has written a bundle that reading would
        // accept. The driver named the path, so it needs nothing announced back to it.
        do {
            try writer.finalise(manifest)
        } catch {
            log(target: walkbook.name, since: started, succeeded: false, err: "\(error)")
            throw error
        }
        log(target: walkbook.name, since: started, succeeded: true, err: nil)
    }

    /// The walkbook the host named: inline (`SIMWALK_WALKBOOK_JSON`) when the runner cannot read the host's files, as on a physical device (SimWalk#116), else the file at `SIMWALK_WALKBOOK`.
    private static func walkbook(from environment: [String: String]) throws -> Walkbook {
        if let inline = environment[Input.walkbookJSON] {
            return try WalkbookLoader.load(from: Data(inline.utf8), source: "inline walkbook")
        }
        let path = try XCTUnwrap(environment[Input.walkbook], "\(Input.walkbook) not set — the host driver passes it as TEST_RUNNER_\(Input.walkbook)")
        return try WalkbookLoader.load(contentsOf: URL(fileURLWithPath: path))
    }

    /// Where the output goes: the host path itself on a simulator, or, with `SIMWALK_OUTPUT_ROOT=container` (a physical device, SimWalk#116), that name under the runner's own `Documents/SimWalkOut`, emptied first so the device holds at most one walk's captures.
    private static func outputURL(for path: String, in environment: [String: String]) throws -> URL {
        guard environment[Input.outputRoot] == "container" else {
            return URL(fileURLWithPath: path)
        }
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/SimWalkOut", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent, isDirectory: true)
    }

    /// Serves the live session the environment names — a simulator's by its directory, a physical device's by `SIMWALK_SESSION_DEVICE` and its launch (SimWalk#116) — resident until it is sent `end`, goes idle, or fails — one launch answering many requests, where `inspect` pays a whole `xcodebuild` run for each.
    ///
    /// **Returns at once when no session is named**, so a run of the whole class is never held here; the host runs it alone, by name (`-only-testing:SimWalkRunner/WalkRunner/testSession`), and a walk runs `testWalk` alone. The session's own record of how it ended is `exit.json`; a failure is also this test's, so the result bundle carries it.
    func testSession() {
        let environment = ProcessInfo.processInfo.environment
        let target: LiveSessionServer.Target
        if let session = environment[Input.sessionDevice] {
            guard let json = environment[Input.sessionLaunchJSON],
                  let launch = try? JSONDecoder().decode(LiveSessionLaunch.self, from: Data(json.utf8))
            else {
                XCTFail("live session device launch: \(Input.sessionLaunchJSON) is missing or is not a launch record")
                return
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
            target = .device(launch: launch, session: session, container: documents.appendingPathComponent("SimWalkSession", isDirectory: true))
        } else if let directory = environment[Input.session] {
            target = .simulator(LiveSessionLayout(directory: URL(fileURLWithPath: directory, isDirectory: true)))
        } else {
            return
        }
        let isDevice = environment[Input.sessionDevice] != nil
        let exit = LiveSessionServer(
            target: target,
            idle: LiveSessionIdle(timeout: LiveSessionIdle.timeout(fromOverride: environment[LiveSessionIdle.overrideVariable])),
            runnerCommit: environment[Input.runnerCommit],
            foundAppearance: Self.deviceAppearance,
            progress: isDevice ? nil : environment[Input.progress].map { ProgressWriter.adopting(url: URL(fileURLWithPath: $0)) }
        ).serve()
        if exit.reason == .failed {
            XCTFail("live session \(exit.summary)")
        }
    }

    /// Measures one screen's route under one of its states on a physical device (SimWalk#67, M4; Brief "M4, performance on a device", rulings 2–3): the run the environment names (`MeasureRun`), into this test's result bundle, which the host reads with `xcresulttool`.
    ///
    /// **Returns at once when no run is named**, as `testSession` does without a session; the host runs it alone, by name, once per measured screen and state, because XCTest records one set of metrics per test method.
    ///
    /// **Each iteration is the route from a cold launch**: terminate, launch under the state, take the route's steps as a walk takes them (`follow`, so a label matches here as it does there), then wait the walk's settle quiet once without reading the tree. `measure` runs the block once more than the iterations asked for and does not record the first. A step that does not land fails the test naming it, and the iterations after it do nothing, so the host leaves the screen and state without a record.
    func testMeasure() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let run = try MeasureRun.named(in: environment) else { return }
        let walkbook = try Self.walkbook(from: environment)
        let screen = try XCTUnwrap(walkbook.screens.first { $0.id == run.screenID }, "measure \(run.subject): the walkbook has no screen '\(run.screenID)'")
        let state = try XCTUnwrap(screen.states.first { $0.slug == run.stateSlug }, "measure \(run.subject): screen '\(screen.id)' has no state '\(run.stateSlug)'")
        let app = XCUIApplication(bundleIdentifier: walkbook.appBundleID)
        let baseEnvironment = AnimationsOptIn.inserting(AnimationsOptIn.library(in: ProcessInfo.processInfo.environment), into: app.launchEnvironment)
        let quiet = SettleWindow.quiet(forScreenMilliseconds: screen.settle, default: Self.settleQuiet)
        let budget = SettleWindow.budget(forQuiet: quiet)
        let options = XCTMeasureOptions()
        options.iterationCount = run.iterations
        let metrics: [any XCTMetric] = [
            XCTApplicationLaunchMetric(waitUntilResponsive: true),
            XCTClockMetric(),
            XCTCPUMetric(application: app),
            XCTMemoryMetric(application: app),
            XCTOSSignpostMetric.navigationTransitionMetric,
            XCTOSSignpostMetric.scrollDecelerationMetric,
        ]
        var failed = false
        measure(metrics: metrics, options: options) {
            guard !failed else { return }
            app.terminate()
            XCUIDevice.shared.appearance = Self.style(state.theme)
            Self.launch(app, under: state, over: baseEnvironment)
            let route = follow(screen, of: walkbook, in: app, budget: budget).probe
            switch route.outcome {
            case .resolved:
                // Once, and nothing read: a read here would be the runner's cost on the app's CPU, not the screen's.
                Thread.sleep(forTimeInterval: quiet)
            case let .unreadable(_, reason):
                failed = true
                XCTFail("measure \(run.subject): route step \(route.failedStep.map(String.init(describing:)) ?? "?") could not be read: \(reason)")
            case let .drifted(_, reason, _):
                failed = true
                XCTFail("measure \(run.subject): route step \(route.failedStep.map(String.init(describing:)) ?? "?") did not land: \(reason ?? "no reason given")")
            }
        }
        // The device as the host found it, as a walk hands it back.
        if let found = Self.deviceAppearance {
            XCUIDevice.shared.appearance = Self.style(found)
        }
    }

    /// Records the run in the host's usage log, alongside the CLI's own lines.
    ///
    /// **The runner can reach the host's log at all only because it can write host paths** (see `HostReachabilityProbe`), which is what lets one file hold both halves of a walk — what the driver orchestrated and what the runner did inside the test process. Per-*screen* failures deliberately do not appear here: they are findings about the app and they belong in the manifest, where the bundle that carries them is the evidence. This line is a finding about the tool.
    ///
    /// Best-effort, like every other write to this log: a walk is not failed by failing to mention it.
    ///
    /// A failure here is always `writer.finalise(manifest)` refusing a manifest the directory does not support (``testWalk()``), a dry run's report refusing to be written (`probeRoutes`, logged as `walk.runner --dry-run`), or a live read refusing to be written (`inspect`, logged as `inspect.runner` against the bundle identifier) — the runner's own output not holding up, never an argument a caller gave — so the kind is stated directly rather than read off the caught error the way the CLI and MCP faces read theirs: this is the one call site where the meaning is fixed and known ahead of time.
    private func log(_ tool: String = "walk.runner", target: String, since started: Date, succeeded: Bool, err: String?) {
        guard let path = ProcessInfo.processInfo.environment[Input.log] else { return }
        UsageLog(fileURL: URL(fileURLWithPath: path), now: { Date() })
            .record(
                tool: tool,
                target: target,
                milliseconds: Int(Date().timeIntervalSince(started) * 1000),
                succeeded: succeeded,
                err: err,
                kind: succeeded ? nil : .runnerFailed
            )
    }

    /// Reads the app the environment names as it stands and writes one ``LiveScreen`` to the output path — `simwalk inspect` (SimWalk#49).
    ///
    /// **Never launches**: the read is ``liveScreen(of:bundleID:runnerCommit:nonce:)``, which a live session's `read` answers with too.
    private func inspect(_ environment: [String: String]) throws {
        let bundleID = try XCTUnwrap(environment[Input.appBundleID], "\(Input.appBundleID) not set — the host driver passes it as TEST_RUNNER_\(Input.appBundleID)")
        let outputPath = try XCTUnwrap(environment[Input.output], "\(Input.output) not set — the host driver passes it as TEST_RUNNER_\(Input.output)")
        let nonce = try XCTUnwrap(environment[Input.nonce], "\(Input.nonce) not set — the host driver passes it as TEST_RUNNER_\(Input.nonce)")
        let started = Date()
        let screen = try Self.liveScreen(
            of: XCUIApplication(bundleIdentifier: bundleID),
            bundleID: bundleID,
            runnerCommit: environment[Input.runnerCommit],
            nonce: nonce
        )
        do {
            try screen.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            log("inspect.runner", target: bundleID, since: started, succeeded: false, err: "\(error)")
            throw error
        }
        log("inspect.runner", target: bundleID, since: started, succeeded: true, err: nil)
    }

    /// Reads `app` as it stands into one ``LiveScreen`` — what `inspect` writes and a live session's `read` answers.
    ///
    /// **Never launches.** It attaches by bundle identifier: an app not running is read as ``LiveScreen/AppState/notRunning`` with no tree, for the host to refuse with the reason, because a launch would serve the launch screen as the screen somebody left the app on. One in the background is brought forward with `activate()`, which resumes a running app and never relaunches it.
    ///
    /// **Read twice, a settle interval apart**, keeping the second read and recording whether the two agreed, so a read taken mid-push says so rather than naming labels that are gone a moment later.
    static func liveScreen(of app: XCUIApplication, bundleID: String, runnerCommit: String?, nonce: String) throws -> LiveScreen {
        let appState: LiveScreen.AppState
        switch app.state {
        case .runningForeground:
            appState = .foreground
        case .runningBackground, .runningBackgroundSuspended:
            appState = .background
            app.activate()
            guard app.wait(for: .runningForeground, timeout: StepPerformer.timeout) else {
                throw InspectRefusal(description: "\(bundleID) was in the background and did not come forward within \(Int(StepPerformer.timeout))s of activate()")
            }
        default:
            appState = .notRunning
        }

        var tree: AXNode?
        var settled: Bool?
        if appState != .notRunning {
            let first = try AXTreeCapture.tree(of: app)
            Thread.sleep(forTimeInterval: StepPerformer.settleInterval)
            let second = try AXTreeCapture.tree(of: app)
            tree = second
            settled = ScreenIdentity.of(first) == ScreenIdentity.of(second)
        }
        let native = UIScreen.main.nativeBounds
        return LiveScreen(
            appBundleID: bundleID,
            device: Self.device(),
            runnerCommit: runnerCommit,
            readAt: Date(),
            nonce: nonce,
            appState: appState,
            tree: tree,
            settled: settled,
            screenPixels: LiveScreen.Pixels(width: Int(native.width), height: Int(native.height))
        )
    }

    /// Walks one screen once per requested state and reports what honestly happened there.
    ///
    /// **Each state is its own launch**, because a state is a launch condition — appearance is set on the device, Dynamic Type and locale arrive as launch arguments, and a state's own arguments and environment arrive with them, and an app already running cannot be asked to have started differently. Capturing every state from one launch would label whatever the device happened to be set to with whatever the walkbook asked for: a bundle claiming `dark` over a light screenshot, which is exactly what the first attempt at this produced.
    ///
    /// **A screen's states are taken into memory first and written afterwards**, which is what makes `StateApplicationCheck` possible at all: the states can only be compared with each other once they all exist, and a bundle that had already filed the first two would have to reach back and unfile them. It is also what stops a refusal leaving artefacts behind — an absent directory beside a stated refusal is a fact, where an empty one reads as a capture that produced nothing. The cost is a screen's screenshots held at once, which for the three states a real walkbook asks for is a few megabytes.
    private func walk(
        _ screen: Walkbook.Screen,
        of walkbook: Walkbook,
        in app: XCUIApplication,
        over baseEnvironment: [String: String],
        writer: CaptureBundleWriter
    ) -> CaptureManifest.ScreenRecord {
        var taken: [TakenState] = []
        var lastCompleted: [Walkbook.RouteStep] = []
        var lastBound: [CaptureManifest.BoundElement] = []
        // Written as each launch applies its reset, so it reaches every record below, the refused and failed ones included.
        var launchResets: [CaptureManifest.LaunchReset] = []
        // This screen's own quiet period when its walkbook entry states one, so a tab whose content
        // streams in over a second pays for itself instead of the whole walk paying for it. Recorded on
        // the record only where it differs from the walk's, which is where a reader's question is.
        let quiet = SettleWindow.quiet(forScreenMilliseconds: screen.settle, default: Self.settleQuiet)
        let ownSettle = screen.settle == nil ? nil : SettleWindow.enforcedMilliseconds(forRequested: quiet)
        let budget = SettleWindow.budget(forQuiet: quiet)
        // The screen's own `motion`, or `--motion` for every screen: decided in the core, where a test holds it (SimWalk#67).
        let recordsMotion = MotionOptIn.records(screen, in: ProcessInfo.processInfo.environment)

        for state in screen.states {
            app.terminate()
            // Back to the appearance the host found first, so a capture is meant to be taken under either
            // its own state's appearance or that one — never under whatever an earlier state left behind.
            // Meant to: the reset uses the same setter whose failures this is guarding against, so
            // `StateApplicationCheck` treats a device found light as one reason to keep a light capture,
            // never as enough on its own, and the host checks after the walk that the reset held.
            if let found = Self.deviceAppearance {
                XCUIDevice.shared.appearance = Self.style(found)
            }
            XCUIDevice.shared.appearance = Self.style(state.theme)
            // Set on the device before the launch, so the app's first fix is the state's; a state without one
            // is walked under what the device was found simulating, never under an earlier state's.
            if setsLocation {
                XCUIDevice.shared.location = state.location.map {
                    XCUILocation(location: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                } ?? foundLocation
            }
            let reset = Self.launch(app, under: state, over: baseEnvironment)
            if !reset.isEmpty {
                launchResets.append(CaptureManifest.LaunchReset(state: state.slug, resources: reset.map(\.rawValue)))
            }

            let route = follow(screen, of: walkbook, in: app, budget: budget)
            let (followed, bound, landing) = (route.probe, route.bound, route.landing)
            lastBound = bound
            lastCompleted = followed.resolvedSteps
            switch followed.outcome {
            case .resolved:
                break
            case let .unreadable(_, reason):
                // Reading the hierarchy is how a step's arrival is checked at all, so a read that
                // fails leaves the runner unable to say whether the step landed. That is a fact
                // about the device, never about the app, which is exactly what `captureFailed` is
                // for — and the alternative, guessing "landed", is how a capture of the wrong screen
                // gets filed under a passing outcome.
                return Self.record(
                    screen,
                    outcome: .captureFailed(reason: "state '\(state.slug)': route step \(followed.failedStep.map(String.init(describing:)) ?? "?"): \(reason)"),
                    routeTaken: followed.resolvedSteps,
                    writing: taken,
                    carrying: Carried(ownSettle: ownSettle, launchResets: launchResets, boundElements: lastBound),
                    with: writer
                )
            case let .drifted(_, reason, cause):
                // The step that failed is part of what was *attempted*; what completed stops short of it.
                // Nothing is listed: a refusal that carries captures is a manifest `finalise` refuses,
                // and this returned whatever earlier states had already been written to disk — so a
                // screen that captured light and then could not reach anything under dark discarded the
                // whole walk's bundle rather than reporting one screen.
                return CaptureManifest.ScreenRecord.filed(
                    id: screen.id,
                    outcome: .unreachable(routeTried: followed.resolvedSteps + [followed.failedStep].compactMap(\.self), reason: reason, cause: cause, state: ScreenOutcome.UnreachableState(failing: state.slug, among: screen.states.map(\.slug))),
                    routeTaken: followed.resolvedSteps,
                    settleQuietMilliseconds: ownSettle,
                    launchResets: launchResets,
                    boundElements: bound
                )
            }

            do {
                // What the route did, for the watch's record: `nil` keeps no reads and files no `motion`.
                let watch = recordsMotion ? MotionWatch(lastStep: followed.resolvedSteps.last, landing: landing) : nil
                try taken.append(take(state, in: app, quiet: quiet, motion: watch, performance: measured.performance(screenID: screen.id, stateSlug: state.slug)))
            } catch {
                // Reached and could not be read — a fact about the tool or the device, never about the
                // app. What was already taken is written and listed, because the bundle states what it
                // holds and a partial capture is a partial capture rather than nothing — but it goes
                // through `record`, which refuses it first if those states cannot all have applied.
                return Self.record(
                    screen,
                    outcome: .captureFailed(reason: "state '\(state.slug)': \(error)"),
                    routeTaken: followed.resolvedSteps,
                    writing: taken,
                    carrying: Carried(ownSettle: ownSettle, launchResets: launchResets, boundElements: lastBound),
                    with: writer
                )
            }
        }

        return Self.record(screen, outcome: .captured, routeTaken: lastCompleted, writing: taken, carrying: Carried(ownSettle: ownSettle, launchResets: launchResets, boundElements: lastBound), with: writer)
    }

    /// Launches `app` under `state`'s own launch conditions — its permission resets, arguments and environment — once the device is set as the state asks and any earlier launch is gone: the tail of every state a walk launches, and of a live session's launch.
    @discardableResult
    static func launch(_ app: XCUIApplication, under state: Walkbook.CaptureState, over baseEnvironment: [String: String]) -> [ProtectedResourceName] {
        // After the previous state's app is gone and before this one launches, so a route answering a
        // permission sheet finds the sheet on every walk rather than only on a device that never saw it.
        for resource in state.resourcesToReset {
            app.resetAuthorizationStatus(for: protectedResource(resource))
        }
        // Built in the core (`CaptureState.launchArguments`), which also says why appearance is not
        // among them; the runner only hands them over.
        app.launchArguments = state.launchArguments
        app.launchEnvironment = state.launchEnvironment(over: baseEnvironment)
        app.launch()
        return state.resourcesToReset
    }

    /// Follows a screen's route in an app just launched, step by step through `StepPerformer.perform`, and answers what it came to.
    ///
    /// **The one route loop, for both modes.** A walk calls it before each state's capture and a dry run calls it and captures nothing, so the two cannot disagree about what a label matches or whether a step landed: there is no second implementation of either to drift (SimWalk#1 item 4).
    ///
    /// **Each step that landed is carried as the runner recorded it** — a `systemTap` with the tree it found the control in (`StepResult.landedAs`) — so a probe's resolved steps are exactly what a walk files as `routeTaken`; the step it stopped at and those after it stay as the walkbook states them.
    ///
    /// **It also answers how long the last step took to land** (`StepPerformer.Arrival`), for a capture's motion record: `nil` for no route, or a last step that does not wait for arrival.
    private func follow(_ screen: Walkbook.Screen, of walkbook: Walkbook, in app: XCUIApplication, budget: TimeInterval) -> FollowedRoute {
        var landed: [Walkbook.RouteStep] = []
        var bound: [CaptureManifest.BoundElement] = []
        var landing: TimeInterval?
        // The app's own screen before the step that can raise a sheet, which a `systemTap` admits nothing of;
        // when it is read is `SystemSheetBaseline`'s decision, and a route with no `systemTap` reads nothing (SimWalk#39).
        var baseline = SystemSheetBaseline(screen: screen, of: walkbook, defaultQuiet: Self.settleQuiet)
        for (index, step) in screen.route.enumerated() {
            // The quiet period of the screen this step is taken on, not the one the route leads to.
            let stepQuiet = SettleWindow.quiet(forStep: index, of: screen, in: walkbook, default: Self.settleQuiet)
            let stoppedHere = landed + screen.route[index...]
            let result: StepPerformer.StepResult
            do {
                // One per step, so a remote sheet's root found by the step's first read is read first by the rest.
                let sheetReads = SheetReads(app: app)
                let sheetScope = try baseline.scope(forStep: index, from: sheetReads)
                let performer = StepPerformer(app: app, quiet: stepQuiet, budget: budget, sheetScope: sheetScope, sheetReads: sheetReads)
                result = try performer.perform(step)
                landing = performer.arrival.landedAfter
            } catch {
                return FollowedRoute(probe: RouteProbe(screenID: screen.id, route: stoppedHere, outcome: .unreadable(step: index, reason: "\(error)")), bound: bound, landing: nil)
            }
            switch result {
            case let .blocked(reason, cause):
                return FollowedRoute(probe: RouteProbe(screenID: screen.id, route: stoppedHere, outcome: .drifted(step: index, reason: reason, cause: cause)), bound: bound, landing: nil)
            case .landed:
                baseline.landed(step, sheetClosed: false)
                landed.append(step)
            case let .landedOn(node):
                baseline.landed(step, sheetClosed: false)
                bound.append(CaptureManifest.BoundElement(step: landed.count, node: node))
                landed.append(step)
            case let .landedAs(recorded, sheetClosed):
                baseline.landed(recorded, sheetClosed: sheetClosed)
                landed.append(recorded)
            }
        }
        return FollowedRoute(probe: RouteProbe(screenID: screen.id, route: landed, outcome: .resolved), bound: bound, landing: landing)
    }

    /// Follows every screen's route and writes what each came to — `walk --dry-run`, which captures nothing.
    ///
    /// **One launch per screen, not per state**: a route is stated from the launch state and a dry run asks only whether it still leads anywhere, so the first state's launch arguments stand in for the rest — a locale changes labels, and the one a walk would try first is the honest one to try. **The device's appearance is never touched**, because it changes no label; that leaves the run nothing to put back but the accessibility the XCUITest teardown switches off, which the host restores as it does after a walk.
    private func probeRoutes(of walkbook: Walkbook, to url: URL) throws {
        let started = Date()
        let app = XCUIApplication(bundleIdentifier: walkbook.appBundleID)
        let baseEnvironment = AnimationsOptIn.inserting(AnimationsOptIn.library(in: ProcessInfo.processInfo.environment), into: app.launchEnvironment)
        let probes = walkbook.screens.map { screen in
            app.terminate()
            app.launchArguments = screen.states.first?.launchArguments ?? []
            app.launchEnvironment = screen.states.first?.launchEnvironment(over: baseEnvironment) ?? baseEnvironment
            app.launch()
            let quiet = SettleWindow.quiet(forScreenMilliseconds: screen.settle, default: Self.settleQuiet)
            return follow(screen, of: walkbook, in: app, budget: SettleWindow.budget(forQuiet: quiet)).probe
        }
        app.terminate()
        let environment = ProcessInfo.processInfo.environment
        let report = try RouteProbeReport(
            walkName: walkbook.name,
            appBundleID: walkbook.appBundleID,
            appBuildHash: environment[Input.buildHash] ?? "unknown",
            walkbookHash: WalkbookIdentity.hash(of: walkbook),
            runnerCommit: environment[Input.runnerCommit],
            device: Self.device(),
            startedAt: started,
            nonce: environment[Input.nonce] ?? "",
            probes: probes
        )
        do {
            try report.write(to: url, of: walkbook)
        } catch {
            log("walk.runner --dry-run", target: walkbook.name, since: started, succeeded: false, err: "\(error)")
            throw error
        }
        log("walk.runner --dry-run", target: walkbook.name, since: started, succeeded: true, err: nil)
    }

    /// Writes what may be filed and returns the record naming it — holding every capture to the screen's `expect` and refusing the states that cannot have applied first, and downgrading the outcome when the writing is what failed.
    ///
    /// **Both checks live here rather than at the call site that succeeded**, which is the whole point of routing every path through one function: a screen that captured light and then failed reading dark used to file the light capture unchecked — by the state check once, and by the `expect` check again a round later, filing a wrong screen's rows under the expected id through the partial path — and a partial walk is where either failure is *most* likely rather than least: whatever broke the third state was in the same environment as the first two. Checked before anything is written, so a refused state leaves no artefacts to be read as evidence of a state that never happened.
    ///
    /// **Only the refused states go (SimWalk#15).** Which ones, the outcome beside them, and what a write failure makes of both are `ScreenFiling.decide` and `Filing.foldingWriteFailure`'s decisions, in the core where a test can hold them; this writes what the filing keeps and records what it says, so a dark state the device ignored no longer takes the light one beside it out of the bundle.
    private static func record(
        _ screen: Walkbook.Screen,
        outcome: ScreenOutcome,
        routeTaken: [Walkbook.RouteStep],
        writing taken: [TakenState],
        carrying carried: Carried,
        with writer: CaptureBundleWriter
    ) -> CaptureManifest.ScreenRecord {
        let (ownSettle, launchResets, boundElements) = (carried.ownSettle, carried.launchResets, carried.boundElements)
        // Both checks, in their order, are `ScreenFiling`'s decision — in the core, where a test holds it.
        let filing = ScreenFiling.decide(
            trees: taken.map(\.tree),
            evidence: taken.map(\.evidence),
            expect: screen.expect,
            expectMenu: screen.expectMenu,
            instead: outcome,
            deviceAppearance: deviceAppearance,
            deviceLocale: deviceLocale
        )
        do {
            let captures = try taken.filter { filing.kept.contains($0.state) }.map { taken in
                // Recorded, not refused: a state asking for the device's own locale draws what its base draws (SimWalk#18).
                let base = filing.identicalToBase.first { $0.state == taken.state }?.base
                let unverified = filing.unverified.first { $0.state == taken.state }?.axes
                return try taken.write(of: screen, identicalTo: base?.slug, unverifiedAxes: unverified, with: writer)
            }
            return CaptureManifest.ScreenRecord.filed(
                id: screen.id,
                outcome: filing.outcome,
                routeTaken: routeTaken,
                captures: captures,
                settleQuietMilliseconds: ownSettle,
                refusedStates: filing.refused,
                refusedOnAppearance: filing.refusedOnAppearance,
                launchResets: launchResets,
                boundElements: boundElements
            )
        } catch {
            // The disk, not the app, and not the screen: whatever verdict was about to be recorded, what
            // actually happened is that its evidence could not be filed. A refusal already decided is kept
            // and leads, because it is still true of the states it names. The fold, and which refused
            // states it still names, is `Filing.foldingWriteFailure` — in the core, where a test holds it.
            let failed = filing.foldingWriteFailure("writing screen '\(screen.id)': \(error)")
            return CaptureManifest.ScreenRecord.filed(
                id: screen.id,
                outcome: failed.outcome,
                routeTaken: routeTaken,
                settleQuietMilliseconds: ownSettle,
                refusedStates: failed.refused,
                refusedOnAppearance: failed.refusedOnAppearance,
                launchResets: launchResets,
                boundElements: boundElements
            )
        }
    }

    /// Reads one state's two artefacts into memory, throwing so the caller can report the honest outcome rather than failing the whole walk.
    ///
    /// Reading and writing are separate because the states of a screen have to be compared with each other before any of them is filed — see `walk`.
    ///
    /// **Settling first is not a nicety.** The first version screenshotted the instant a route finished and caught a *transition* — an app sliding off screen mid-animation, captured and recorded as though it were the screen asked for. Nothing in the bundle can tell that from a real capture, so every flag a differ raised on it would be about an animation frame.
    ///
    /// **The picture is taken between two reads, and kept only if they agree.** Screenshotting after the settled tree left a window in which the screen could change between the description and the photograph, and a failed walk was found holding a pushed screen's `screen.png` beside the pre-push list's `ax-tree.json` — one capture whose halves are of different screens, which is worse than no capture (SimWalk#4). `SettledCapture.take` owns the sequence — `SettleTracker`'s decisions, and the refusal under a system alert after the picture — in the core, where a test drives it against a scripted device; this only hands it the device.
    ///
    /// **The watch keeps its reads and makes a record only where `motion` is given** (SimWalk#67): a capture without one reads as "motion not recorded", so nothing is filed unasked.
    private func take(_ state: Walkbook.CaptureState, in app: XCUIApplication, quiet: TimeInterval, motion: MotionWatch?, performance: CaptureManifest.Performance?) throws -> TakenState {
        let device = Device(app: app, springboard: XCUIApplication(bundleIdentifier: StepPerformer.springboardBundleID), started: Date())
        let capture = try SettledCapture.take(from: device, quiet: quiet, budget: SettleWindow.budget(forQuiet: quiet), interval: StepPerformer.settleInterval, motion: motion)
        return TakenState(state: state, capture: capture, readAt: device.started.addingTimeInterval(capture.takenAfter), motion: capture.motion, performance: performance)
    }

    /// The device the walk ran on, read from the runner's own process rather than passed in, so a manifest attests to where it actually executed.
    static func device() -> CaptureManifest.Device {
        let environment = ProcessInfo.processInfo.environment
        return CaptureManifest.Device(
            name: environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardwareModel ?? UIDevice.current.model,
            // A physical device cannot read its own UDID, so the host that named it passes it (SimWalk#116).
            udid: environment["SIMULATOR_UDID"] ?? environment[Input.deviceUDID] ?? "unknown",
            osVersion: UIDevice.current.systemVersion,
            locale: deviceLocale
        )
    }

    /// The hardware model (`iPhone19,7`) on a physical device, the form a simulator's `SIMULATOR_MODEL_IDENTIFIER` takes; on a simulator it names the Mac, which is why that variable is read first.
    private static var hardwareModel: String? {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return machine.isEmpty ? nil : machine
    }

    /// The device's own appearance as the host read it before the walk, or `nil` when it could not — which the state check answers by refusing both sides of a failed light/dark comparison.
    static var deviceAppearance: Walkbook.Theme? {
        ProcessInfo.processInfo.environment[Input.deviceAppearance].flatMap(Walkbook.Theme.init(rawValue:))
    }

    /// Seconds since the device booted as the host read it, or `nil` when it could not (or named a future time) — which a `systemTap` that saw no sheet answers with the answered-sheet wording rather than the boot's age (SimWalk#88).
    ///
    /// Host and runner share the Mac's clock, so the age is read against the runner's own; the parse is `DeviceBootTime.age`, pinned in `SimWalkCore`, and this call is not (SimWalk#90).
    static var deviceBootAge: TimeInterval? {
        DeviceBootTime.age(in: ProcessInfo.processInfo.environment, now: Date())
    }

    /// The slim boot the host named, or `nil` on a stock device or when the host could not tell — which leaves a `systemTap` refusal without the clause. The parse is `SlimDevice.read`, pinned in `SimWalkCore`.
    static var slimDevice: SlimDevice? {
        SlimDevice.read(in: ProcessInfo.processInfo.environment)
    }

    /// The locale the device was already in as the host read it, or `nil` when it could not — which the state check answers by treating a locale state and its base as different conditions, as it always did.
    private static var deviceLocale: String? {
        ProcessInfo.processInfo.environment[Input.deviceLocale]
    }

    static func style(_ theme: Walkbook.Theme) -> XCUIDevice.Appearance {
        theme == .dark ? .dark : .light
    }

    /// The `XCUIProtectedResource` a walkbook's `resetPermissions` name stands for — the core spells the names, since it cannot import XCTest.
    private static func protectedResource(_ name: ProtectedResourceName) -> XCUIProtectedResource {
        switch name {
        case .contacts: .contacts
        case .calendar: .calendar
        case .reminders: .reminders
        case .photos: .photos
        case .microphone: .microphone
        case .camera: .camera
        case .mediaLibrary: .mediaLibrary
        case .homeKit: .homeKit
        case .focus: .focus
        case .localNetwork: .localNetwork
        case .bluetooth: .bluetooth
        case .keyboardNetwork: .keyboardNetwork
        case .location: .location
        case .health: .health
        case .userTracking: .userTracking
        }
    }

    /// How long the hierarchy must hold still before a capture is taken, from `--settle`.
    ///
    /// Defaults to one interval, which is the original "two identical reads in a row" and leaves every existing walk timed as it was. Raising it is for content that arrives *after* the screen does — an insight card that renders its heading immediately and streams its body a second later is perfectly still while a 250ms window watches it, and captures with the body empty.
    static var settleQuiet: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment[Input.settleMilliseconds],
              let milliseconds = Double(raw), milliseconds > 0
        else {
            return StepPerformer.settleInterval
        }
        return milliseconds / 1000
    }
}

private extension WalkRunner {
    /// Environment keys the host driver sets, each reaching the runner with its `TEST_RUNNER_` prefix stripped.
    struct Input {
        static var walkbook: String {
            "SIMWALK_WALKBOOK"
        }

        static var output: String {
            "SIMWALK_OUTPUT"
        }

        /// The walkbook's own JSON, for a runner that cannot read the host's files (a physical device, SimWalk#116); takes the place of ``walkbook``.
        static var walkbookJSON: String {
            "SIMWALK_WALKBOOK_JSON"
        }

        /// `container`: ``output`` is a name under the runner's own data container, which the host copies out (a physical device, SimWalk#116); absent means a host path.
        static var outputRoot: String {
            "SIMWALK_OUTPUT_ROOT"
        }

        /// The live session's id on a physical device; its presence selects device mode, serving through the runner's own container and socket instead of a host directory.
        static var sessionDevice: String {
            "SIMWALK_SESSION_DEVICE"
        }

        /// The device session's `LiveSessionLaunch` as JSON, which the runner cannot read from a host path.
        static var sessionLaunchJSON: String {
            "SIMWALK_SESSION_LAUNCH_JSON"
        }

        /// The physical device's UDID as the host named it, which the device cannot read itself (SimWalk#116).
        static var deviceUDID: String {
            "SIMWALK_DEVICE_UDID"
        }

        static var buildHash: String {
            "SIMWALK_BUILD_HASH"
        }

        static var buildProvenance: String {
            "SIMWALK_BUILD_PROVENANCE"
        }

        /// The host's usage-log file itself — the exact path `UsageLog.standard()` resolved on the driver side, override included; absent means the walk goes unrecorded, never unrun.
        static var log: String {
            "SIMWALK_LOG"
        }

        /// How long the hierarchy must hold still before capturing, in milliseconds; absent means the default.
        static var settleMilliseconds: String {
            "SIMWALK_SETTLE_MS"
        }

        /// The device's appearance as the host found it, `light` or `dark`; absent means it could not be read.
        static var deviceAppearance: String {
            "SIMWALK_DEVICE_APPEARANCE"
        }

        /// The commit this runner was built from; absent means the host could not tell.
        static var runnerCommit: String {
            "SIMWALK_RUNNER_COMMIT"
        }

        /// The locale the device was already in, `en_GB`-style; absent means it could not be read or named no single locale.
        static var deviceLocale: String {
            "SIMWALK_DEVICE_LOCALE"
        }

        /// `1` for `walk --dry-run`: follow every route, capture nothing, write a route-probe report to the output path; absent means a walk.
        static var dryRun: String {
            "SIMWALK_DRY_RUN"
        }

        /// `1` for `simwalk inspect`: read the app named by ``appBundleID`` as it stands, launching nothing, and write one live read to the output path; absent means a walk.
        static var inspect: String {
            "SIMWALK_INSPECT"
        }

        /// The app `inspect` reads; a walk takes its app from the walkbook and never sets it.
        static var appBundleID: String {
            "SIMWALK_APP_BUNDLE_ID"
        }

        /// The value this dry run's host generated for `RouteProbeReport.nonce` — echoed back in the report so an overlapping run of the same build cannot be mistaken for this one (SimWalk#36), and a live read's, echoed back into `LiveScreen.nonce` (SimWalk#49); absent (a walk never sets it) reads as the empty string.
        static var nonce: String {
            "SIMWALK_NONCE"
        }

        /// The progress file the host started, which the runner writes `running` and each screen into — or, in a live session, `running`, each step and the end; absent means nobody is watching and no progress is written, never a failure.
        static var progress: String {
            "SIMWALK_PROGRESS"
        }

        /// A live session's directory (`LiveSessionLayout`), which only `testSession` reads.
        ///
        /// Its last component is the session id, carried back as each read's nonce. The idle override arrives as `LiveSessionIdle.overrideVariable`.
        static var session: String {
            "SIMWALK_SESSION"
        }
    }
}

extension WalkRunner {
    /// The device a state's capture is read from: only the reads, the picture and the wait, while `SettledCapture.take` decides what to do with them — the refusal under a system alert included, which a test holds there (SimWalk#39 item 5).
    ///
    /// A route's `SystemSheetBaseline` reads the app's tree from it too, and decides when a read waits for the screen to settle.
    ///
    /// `@MainActor` as the rest of the runner is, for `snapshot()`; the conformance is `@preconcurrency` because the core's protocols are isolation-free, and every call to them comes from `take` or the route loop, on the main actor.
    @MainActor
    struct Device: @preconcurrency CaptureSource {
        let app: XCUIApplication
        let springboard: XCUIApplication
        let started: Date

        func appTree() throws -> AXNode {
            try AXTreeCapture.tree(of: app)
        }

        func springboardTree() throws -> AXNode {
            try AXTreeCapture.tree(of: springboard)
        }

        func screenshot() -> Data {
            XCUIScreen.main.screenshot().pngRepresentation
        }

        func elapsed() -> TimeInterval {
            Date().timeIntervalSince(started)
        }

        func pause(_ interval: TimeInterval) {
            Thread.sleep(forTimeInterval: interval)
        }
    }

    /// The app's tree as a `systemTap` judges it: one `app.snapshot()`, with a remote sheet's content put back where the snapshot stops (SimWalk#48).
    ///
    /// On a relaunch with the sheet's host process alive, the snapshot ends where the sheet is hosted while the live query still reaches its controls. `RemoteContentGraft` decides each live read — whether to look at all, which element next, where the content goes — and this makes the reads: a count, or an element's own `snapshot()`, by index path from the app — `exists` first for a known root, which may have gone since the read that found it. An element whose snapshot cannot be taken is answered as unreadable, never read property by property, since a query that no longer matches is recorded as a test failure (SimWalk#47).
    ///
    /// **Only `systemTap`'s reads**: the baseline its scope is made from, its polls, and the reads that judge whether its control and its sheet went away. A capture reads the snapshot alone and pays nothing. One per route step, so the root's live path that the step's first read found is read first by the rest of it: its `exists` and its `snapshot()` in place of the walk, with no child count. A walk that found no root is not made again while the tree keeps its shape (SimWalk#56).
    ///
    /// `@MainActor` and `@preconcurrency` for the reason `Device` is.
    @MainActor
    final class SheetReads: @preconcurrency TreeSource {
        private let app: XCUIApplication
        private let started = Date()
        private var recall = RemoteContentGraft.Recall.unknown

        init(app: XCUIApplication) {
            self.app = app
        }

        func appTree() throws -> AXNode {
            var graft = try RemoteContentGraft(tree: AXTreeCapture.tree(of: app), recall: recall)
            var step = graft.start()
            while true {
                switch step {
                case .countDescendants:
                    step = graft.next(.count(app.descendants(matching: .any).count))
                case let .countChildren(path):
                    step = graft.next(.count(liveChildren(of: element(at: path), isApp: path.isEmpty)))
                case let .read(path, known):
                    let element = element(at: path)
                    guard !known || element.exists, let snapshot = try? AXTreeCapture.tree(of: element) else {
                        step = graft.next(.unreadable)
                        continue
                    }
                    step = graft.next(.element(snapshot))
                case let .done(tree, found):
                    recall = found
                    return tree
                }
            }
        }

        func elapsed() -> TimeInterval {
            Date().timeIntervalSince(started)
        }

        func pause(_ interval: TimeInterval) {
            Thread.sleep(forTimeInterval: interval)
        }

        /// How many live children `element` has, `0` where it is gone — asked only where `RemoteContentGraft` passes through it, never of a known root.
        ///
        /// Counting under an element that no longer matches is recorded as a test failure ("No matches found"), and one can go between any two reads — a sheet dismissing under the step's polls. So `exists` is asked first, and the count, which the element can still vanish ahead of, runs as a non-strict expected failure: a failure there is marked expected rather than recorded against the walk, and none is no issue at all.
        private func liveChildren(of element: XCUIElement, isApp: Bool) -> Int {
            guard isApp || element.exists else { return 0 }
            return XCTExpectFailure("a live element can go between its exists and its count (SimWalk#48)", strict: false) {
                element.children(matching: .any).count
            }
        }

        /// The live element at `path`, each step a child by index — bound, not yet looked up.
        private func element(at path: [Int]) -> XCUIElement {
            path.reduce(app as XCUIElement) { $0.children(matching: .any).element(boundBy: $1) }
        }
    }

    /// A live read refused because the app it was to read would not come forward; nothing is written, and the host reports the runner's failure.
    struct InspectRefusal: Error, CustomStringConvertible {
        let description: String
    }

    /// One state's capture, held in memory between being read off the device and being filed in the bundle.
    struct TakenState {
        let state: Walkbook.CaptureState
        /// The artefacts, which only `SettledCapture.take` makes — so nothing is filed that did not pass its system-alert check (SimWalk#39 item 5).
        let capture: SettledCapture
        /// When the kept picture was taken — the capture's `capturedAt`, carried from the read rather than stamped when the screen's states are filed together after the last of them, which can be several relaunches later.
        let readAt: Date
        /// What the watch before the capture saw, where the walk asked for it; `nil` files no `motion` record.
        let motion: CaptureManifest.Motion?
        /// The figures this screen and state's measure run recorded, from launches of their own; `nil` files no `performance` record.
        let performance: CaptureManifest.Performance?

        var screenshot: Data {
            capture.screenshot
        }

        var tree: AXNode {
            capture.tree
        }

        var didSettle: Bool {
            capture.didSettle
        }

        /// Whether the capture holds a screen at all, or only the frame the app draws around one.
        ///
        /// Computed from the tree in hand rather than tracked through the capture, so it is a fact about the artefact that is about to be filed and not about the moment it was taken.
        var hasContent: Bool {
            !ScreenContentCheck.isChromeOnly(tree)
        }

        /// What `StateApplicationCheck` compares this state against its siblings by.
        var evidence: StateApplicationCheck.Evidence {
            StateApplicationCheck.Evidence(state: state, screenshot: screenshot, tree: tree)
        }

        /// Files both artefacts and returns the record naming them — and, where the state check found this one honestly identical to another, the slug of that base.
        func write(of screen: Walkbook.Screen, identicalTo base: String?, unverifiedAxes: [String]?, with writer: CaptureBundleWriter) throws -> CaptureManifest.StateCapture {
            try writer.prepareDirectory(screenID: screen.id, state: state)
            let capture = CaptureManifest.StateCapture(
                screenID: screen.id,
                state: state,
                axTreeSettled: didSettle,
                axTreeHasContent: hasContent,
                identicalTo: base,
                unverifiedAxes: unverifiedAxes,
                capturedAt: readAt,
                motion: motion,
                performance: performance
            )
            // Resolved through the layout, never composed here. The runner is the *write* side of the
            // bundle contract, so it is where a second path speller would do the most damage.
            try screenshot.write(to: CaptureBundleLayout.url(forRelativePath: capture.screenshotPath, in: writer.url))
            // Compact, not pretty-printed. This tree is the differ's input rather than something read by
            // eye, and indentation was 70% of its bytes — a capture that costs more to store than the
            // screenshot it describes is the opposite of the point.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(tree).write(to: CaptureBundleLayout.url(forRelativePath: capture.axTreePath, in: writer.url))
            return capture
        }
    }
}

extension WalkRunner {
    /// What a screen's record holds whatever its outcome: its own settle, and the resets its launches applied.
    private struct Carried {
        let ownSettle: Int?
        let launchResets: [CaptureManifest.LaunchReset]
        let boundElements: [CaptureManifest.BoundElement]
    }
}

private extension WalkRunner {
    /// What `follow` came to: the probe, the elements its label steps bound (SimWalk#93), and how long its last step took to land (SimWalk#67).
    struct FollowedRoute {
        let probe: RouteProbe
        let bound: [CaptureManifest.BoundElement]
        let landing: TimeInterval?
    }
}
