//
// Copyright © Agulhas Labs
//

import Foundation
import SimulatorServices
import SimWalkCore

/// Builds the XCUITest runner and runs a walkbook through it.
///
/// The runner is **generic and built once** (Brief §7.4): its code never changes between walks because the walkbook arrives as environment, so the build is cached in a derived-data directory and reused. That is the whole reason the target has no Target Application — one built runner walks every app. The directory is keyed to the source and commit it builds (`RunnerSource.buildKey`), so a walk never builds into another source's products.
///
/// Inputs cross into the test process as `TEST_RUNNER_`-prefixed variables, which `xcodebuild` forwards with the prefix stripped. That indirection is not decoration: a test bundle takes no arguments, so this is the only channel there is.
public struct RunnerInvocation {
    /// Where the runner's Xcode project lives, and where its build is cached.
    public let projectPath: String
    public let derivedDataPath: String
    private let shell: Shell
    private let overrideRoot: URL
    private let profileLookup: @Sendable (String) -> ServiceProfile?

    /// `overrideRoot` is where a slim device's launchd override file lives and `profileLookup` names the runtime's service profile; both are injectable so a test reads a temporary directory and a fixture profile.
    public init(
        projectPath: String,
        derivedDataPath: String,
        shell: Shell = Shell(),
        overrideRoot: URL = DisabledServicesOverride.defaultRoot,
        profileLookup: @escaping @Sendable (String) -> ServiceProfile? = ServiceProfiles.profile(forRuntime:)
    ) {
        self.projectPath = projectPath
        self.derivedDataPath = derivedDataPath
        self.shell = shell
        self.overrideRoot = overrideRoot
        self.profileLookup = profileLookup
    }

    /// The line to print before a build that has to start from nothing, or `nil` when the build directory already holds built products (SimWalk#98).
    ///
    /// A first build takes minutes and prints nothing until it ends, so a caller watching stderr cannot tell it from a hang. "Cold" is no `*.xctestrun` under `<derivedDataPath>/Build/Products`: the file `build-for-testing` writes last, so its presence means the build is warm and takes a second or two.
    public func coldBuildNote(commit: String?) -> String? {
        let products = URL(fileURLWithPath: derivedDataPath).appendingPathComponent("Build/Products", isDirectory: true)
        let built = FileManager.default.enumerator(at: products, includingPropertiesForKeys: nil)?
            .contains { ($0 as? URL)?.pathExtension == "xctestrun" } ?? false
        guard !built else { return nil }
        let name = commit.map { " (\($0.prefix(8)))" } ?? ""
        return "building the runner\(name) — a first build takes several minutes"
    }

    /// Builds the runner for a device, reusing the cached build when nothing has changed.
    ///
    /// `xcodebuild` decides what "unchanged" means; this does not try to outsmart it. A warm build is a second or two, which is well under the cost of being wrong about staleness.
    public func build(for simulator: Simulator) throws {
        let result = try shell.run("/usr/bin/xcodebuild", [
            "build-for-testing",
            "-project", projectPath,
            "-scheme", Self.scheme,
            "-destination", "platform=iOS Simulator,id=\(simulator.udid)",
            "-derivedDataPath", derivedDataPath,
        ])
        guard result.succeeded else {
            throw RunnerError.buildFailed(reason: Self.diagnostic(from: result))
        }
    }

    /// Runs one walk, returning nothing — the bundle on disk is the result, or with `dryRun` the route-probe report.
    ///
    /// A failed run is reported with the runner's own diagnostic rather than xcodebuild's exit code, because "the walk could not start" and "the walk ran and refused" are different answers and the caller has to be able to tell them apart.
    public func walk(
        walkbookPath: String,
        outputPath: String,
        buildHash: String,
        logFilePath: String?,
        settleMilliseconds: Int? = nil,
        motion: Bool = false,
        appleAudit: Bool = false,
        animationsOffLibrary: String? = nil,
        deviceAppearance: Walkbook.Theme? = nil,
        deviceLocale: String? = nil,
        runnerCommit: String? = nil,
        dryRun: Bool = false,
        nonce: String? = nil,
        resultBundlePath: String? = nil,
        progressPath: String? = nil,
        on simulator: Simulator
    ) throws {
        var environment = [
            "TEST_RUNNER_SIMWALK_WALKBOOK": walkbookPath,
            "TEST_RUNNER_SIMWALK_OUTPUT": outputPath,
            "TEST_RUNNER_SIMWALK_BUILD_HASH": buildHash,
        ]
        if let logFilePath {
            environment["TEST_RUNNER_SIMWALK_LOG"] = logFilePath
        }
        // The device's own appearance as the host read it: the runner returns the device to it before every
        // state, and `StateApplicationCheck` decides which side of a failed light/dark comparison to keep from
        // it. Absent means unknown, and the check refuses both sides rather than guessing.
        if let deviceAppearance {
            environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] = deviceAppearance.rawValue
        }
        // The locale the device was already in, so a state asking for it is not refused for drawing what the
        // plain state draws (SimWalk#18). Absent means unknown, and the identity rule refuses as it always did.
        if let deviceLocale {
            environment["TEST_RUNNER_SIMWALK_DEVICE_LOCALE"] = deviceLocale
        }
        // Which commit the runner was built from, so the manifest can say which runner produced the bundle
        // (SimWalk#16). Absent when it cannot be told, and the manifest then says nothing rather than guessing.
        if let runnerCommit {
            environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] = runnerCommit
        }
        if let settleMilliseconds {
            environment["TEST_RUNNER_SIMWALK_SETTLE_MS"] = String(settleMilliseconds)
        }
        // `--motion`: every screen's captures record what the watch before them saw (SimWalk#67). Absent means each screen's
        // own `motion` decides, so every existing invocation is unchanged.
        if motion {
            environment[MotionOptIn.hostEnvironmentKey] = MotionOptIn.walkWideValue
        }
        // `--apple-audit`: the runner audits every state after its capture. Absent means the walkbook's own
        // `appleAudit` decides, so every existing invocation is unchanged.
        if appleAudit {
            environment[AppleAuditOptIn.hostEnvironmentKey] = AppleAuditOptIn.walkWideValue
        }
        // The animations-off library's path (SimWalk#154), which the runner inserts into the app's launch environment. Absent means the
        // app launches as it is: `--animations`, a walk that records motion, and every device walk.
        if let animationsOffLibrary {
            environment[AnimationsOptIn.hostEnvironmentKey] = animationsOffLibrary
        }
        // The runner's second mode (`walk --dry-run`, SimWalk#1 item 4): every route followed through the same step
        // code a walk runs, nothing captured, and a route-probe report written to `outputPath` in place of a bundle.
        // Absent means a walk, so every existing invocation is unchanged.
        if dryRun {
            environment["TEST_RUNNER_SIMWALK_DRY_RUN"] = "1"
        }
        // The value this run's host generated, so what the runner writes can be told from one an
        // overlapping run of the same build left (SimWalk#36, SimWalk#41). Absent means the caller generated
        // none — every walk and dry run passes one now.
        if let nonce {
            environment["TEST_RUNNER_SIMWALK_NONCE"] = nonce
        }
        // The progress file the host started, for the runner to take over between `launching` and `matching`
        // (`Docs/SIMWALK-PROGRESS.md` §3). Absent means nobody is watching, and the runner writes none.
        if let progressPath {
            environment["TEST_RUNNER_SIMWALK_PROGRESS"] = progressPath
        }
        // When the device booted, read now that it is booted — after this walk's own boot, or a settle's reboot before
        // a second pass — so a `systemTap` that saw no sheet can say the device is too freshly booted for HealthKit to
        // raise one (SimWalk#88). Absent means unknown, and the refusal keeps its answered-sheet wording.
        addDeviceBootedAt(to: &environment, on: simulator)
        // Whether the device booted slim, so a `systemTap` that saw no sheet can say a service that is off never raises one.
        addSlimDevice(to: &environment, on: simulator)

        try runBuilt(environment: environment, resultBundlePath: resultBundlePath, on: simulator)
    }

    /// Adds how many launchd services are off on `simulator` and which capabilities they serve to `environment`; left out where none are off or the override cannot be read.
    private func addSlimDevice(to environment: inout [String: String], on simulator: Simulator) {
        guard let off = try? DisabledServicesOverride(root: overrideRoot).labels(for: simulator.udid), !off.isEmpty else { return }
        let profile = simulator.runtimeIdentifier.flatMap(profileLookup)
        let capabilities = profile.map { profile in
            Capability.allCases.filter { !off.isDisjoint(with: profile.labels(for: $0)) }.map(\.rawValue)
        } ?? []
        environment[SlimDevice.hostEnvironmentKey] = SlimDevice(servicesOff: off.count, capabilities: capabilities).environmentValue
    }

    /// Adds when `simulator` booted to `environment`, where the host can read it (SimWalk#88); left out otherwise.
    private func addDeviceBootedAt(to environment: inout [String: String], on simulator: Simulator) {
        if let bootedAt = simulator.bootedAt(now: Date(), shell: shell) {
            environment[DeviceBootTime.hostEnvironmentKey] = String(bootedAt.timeIntervalSince1970)
        }
    }

    /// The runner's bundle identifier when it is not overridden: a UI test runner installed on a device is `<this>.xctrunner`.
    static var defaultRunnerBundleID: String {
        "com.agulhaslabs.simwalk.runner"
    }

    /// Builds the runner for a physical device and signs it, which a simulator build does not.
    ///
    /// `runnerBundleID` replaces the project's committed identifier, for a team that cannot register `com.agulhaslabs.simwalk.runner`; absent, the project's own is kept.
    public func buildForDevice(udid: String, team: String, runnerBundleID: String? = nil) throws {
        var arguments = [
            "build-for-testing",
            "-project", projectPath,
            "-scheme", Self.scheme,
            "-destination", "platform=iOS,id=\(udid)",
            "-derivedDataPath", derivedDataPath,
            "-allowProvisioningUpdates",
            "DEVELOPMENT_TEAM=\(team)",
            "CODE_SIGN_STYLE=Automatic",
        ]
        if let runnerBundleID {
            arguments.append("PRODUCT_BUNDLE_IDENTIFIER=\(runnerBundleID)")
        }
        let result = try shell.run("/usr/bin/xcodebuild", arguments)
        guard result.succeeded else {
            throw RunnerError.buildFailed(reason: Self.diagnostic(from: result))
        }
    }

    /// The bundle identifier of the installed runner app, whose data container the runner writes its bundle into.
    public static func deviceContainerBundleID(runnerBundleID: String?) -> String {
        (runnerBundleID ?? defaultRunnerBundleID) + ".xctrunner"
    }

    /// Where the runner writes a device walk's bundle inside its container.
    ///
    /// For ``DeviceBundleTransfer/fetch(source:to:copier:fileManager:)``. Beside the runner's own `outputURL(for:in:)`, which must agree.
    public static func deviceOutputSource(outputName: String) -> String {
        "Documents/SimWalkOut/\(outputName)"
    }

    /// Runs one walk on a physical device.
    ///
    /// The walkbook crosses as JSON text and the bundle is written under the runner's own container (`outputName` is a bare `<name>.simwalk`), because the device can reach no host path.
    ///
    /// None of the host-path keys a simulator walk sets (log, progress, booted-at) are passed: the device cannot write them and `simctl` cannot read it.
    public func walkOnDevice(
        walkbookJSON: String,
        outputName: String,
        buildHash: String,
        buildProvenance: CaptureManifest.AppBuildProvenance? = nil,
        udid: String,
        nonce: String,
        settleMilliseconds: Int? = nil,
        motion: Bool = false,
        appleAudit: Bool = false,
        deviceAppearance: Walkbook.Theme? = nil,
        runnerCommit: String? = nil,
        performance: MeasuredPerformance = MeasuredPerformance(),
        resultBundlePath: String? = nil
    ) throws {
        var environment = [
            "TEST_RUNNER_SIMWALK_WALKBOOK_JSON": walkbookJSON,
            "TEST_RUNNER_SIMWALK_OUTPUT": outputName,
            "TEST_RUNNER_SIMWALK_OUTPUT_ROOT": "container",
            "TEST_RUNNER_SIMWALK_BUILD_HASH": buildHash,
            "TEST_RUNNER_SIMWALK_DEVICE_UDID": udid,
            "TEST_RUNNER_SIMWALK_NONCE": nonce,
        ]
        if let buildProvenance {
            environment["TEST_RUNNER_SIMWALK_BUILD_PROVENANCE"] = buildProvenance.rawValue
        }
        if let deviceAppearance {
            environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] = deviceAppearance.rawValue
        }
        if let runnerCommit {
            environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] = runnerCommit
        }
        // The same two variables a simulator walk sets (`--settle`, `--motion`): each is a runner variable with no host path.
        if let settleMilliseconds {
            environment["TEST_RUNNER_SIMWALK_SETTLE_MS"] = String(settleMilliseconds)
        }
        if motion {
            environment[MotionOptIn.hostEnvironmentKey] = MotionOptIn.walkWideValue
        }
        // `--apple-audit`: the runner audits every state after its capture. Absent means the walkbook's own
        // `appleAudit` decides, so every existing invocation is unchanged.
        if appleAudit {
            environment[AppleAuditOptIn.hostEnvironmentKey] = AppleAuditOptIn.walkWideValue
        }
        // The measure runs' records, which the runner files on each capture: the manifest stays its single write (SimWalk#67, M4).
        if !performance.isEmpty {
            environment[MeasuredPerformance.hostEnvironmentKey] = try performance.json()
        }
        let arguments = testArguments(only: "testWalk", resultBundlePath: resultBundlePath, destination: "platform=iOS,id=\(udid)")
        let result = try shell.run("/usr/bin/xcodebuild", arguments, environment: environment)
        guard result.succeeded else {
            throw RunnerError.walkFailed(reason: Self.diagnostic(from: result))
        }
    }

    /// Runs one measure run on a physical device (SimWalk#67, M4): the runner's `testMeasure` alone, for one screen and state, into its own result bundle, which the caller reads with `xcresulttool` and deletes.
    ///
    /// The walkbook crosses as JSON, as a device walk's does, with the device's appearance (handed back by the runner at the end) and the walk's settle; nothing is written to the runner's container.
    ///
    /// - Throws: ``RunnerError/measureFailed(reason:)`` with the runner's own diagnostic when `xcodebuild` fails, a step that did not land among it.
    public func measureOnDevice(
        _ run: MeasureRun,
        walkbookJSON: String,
        udid: String,
        settleMilliseconds: Int? = nil,
        deviceAppearance: Walkbook.Theme? = nil,
        runnerCommit: String? = nil,
        resultBundlePath: String
    ) throws {
        var environment = run.hostEnvironment
        environment["TEST_RUNNER_SIMWALK_WALKBOOK_JSON"] = walkbookJSON
        environment["TEST_RUNNER_SIMWALK_DEVICE_UDID"] = udid
        if let deviceAppearance {
            environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] = deviceAppearance.rawValue
        }
        if let runnerCommit {
            environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] = runnerCommit
        }
        if let settleMilliseconds {
            environment["TEST_RUNNER_SIMWALK_SETTLE_MS"] = String(settleMilliseconds)
        }
        let arguments = testArguments(only: "testMeasure", resultBundlePath: resultBundlePath, destination: "platform=iOS,id=\(udid)")
        let result = try shell.run("/usr/bin/xcodebuild", arguments, environment: environment)
        guard result.succeeded else {
            throw RunnerError.measureFailed(reason: Self.diagnostic(from: result))
        }
    }

    /// Runs one live read (`simwalk inspect`, SimWalk#49): the runner attaches to `appBundleID` as it stands — launching nothing — and writes one `LiveScreen` to `outputPath`, carrying `nonce` back.
    ///
    /// The same built runner and the same test a walk runs, told by the environment which mode it is in; a failure is reported as a walk's is, with the runner's own diagnostic.
    public func inspect(
        appBundleID: String,
        outputPath: String,
        logFilePath: String?,
        runnerCommit: String?,
        nonce: String,
        resultBundlePath: String? = nil,
        on simulator: Simulator
    ) throws {
        var environment = [
            "TEST_RUNNER_SIMWALK_INSPECT": "1",
            "TEST_RUNNER_SIMWALK_APP_BUNDLE_ID": appBundleID,
            "TEST_RUNNER_SIMWALK_OUTPUT": outputPath,
            "TEST_RUNNER_SIMWALK_NONCE": nonce,
        ]
        if let logFilePath {
            environment["TEST_RUNNER_SIMWALK_LOG"] = logFilePath
        }
        if let runnerCommit {
            environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] = runnerCommit
        }
        try runBuilt(environment: environment, resultBundlePath: resultBundlePath, on: simulator)
    }

    /// The command line of a live session's resident runner: the one `testSession` test, spawned in the background by the host rather than run to completion here.
    ///
    /// The session's directory (`layout`) is the only input the runner needs beyond its commit and log — what it launches is in `launch.json` there, and its result bundle goes there too. `idleOverride` is the host's `SIMWALK_SESSION_IDLE_SECONDS`, passed on verbatim so both sides read it with ``LiveSessionIdle/timeout(fromOverride:)``.
    ///
    /// `animationsOffLibrary` is the path of the animations-off library, which the runner inserts into the app it launches; `nil` leaves animations on.
    ///
    /// `deviceAppearance` is the device's appearance as `start` found it, before any settle: the runner puts it back on every exit, including an idle one no host command sees, as a walk's runner does before every state. Absent means unknown, and the runner then leaves the appearance as the session left it.
    public func session(
        layout: LiveSessionLayout,
        logFilePath: String?,
        runnerCommit: String?,
        idleOverride: String?,
        deviceAppearance: Walkbook.Theme?,
        progress: ProgressClaim? = nil,
        animationsOffLibrary: String? = nil,
        on simulator: Simulator
    ) -> RunnerCommand {
        var environment = ["TEST_RUNNER_SIMWALK_SESSION": layout.directory.path]
        // The progress file `session start` began, which the runner takes over at `running` (SimWalk#83); the claim on it goes
        // with the process, so the slot stays this session's for exactly as long as its `xcodebuild` lives.
        environment["TEST_RUNNER_SIMWALK_PROGRESS"] = progress?.progressURL.path
        environment["TEST_RUNNER_SIMWALK_LOG"] = logFilePath
        environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] = runnerCommit
        environment["TEST_RUNNER_" + LiveSessionIdle.overrideVariable] = idleOverride
        environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] = deviceAppearance?.rawValue
        // The library that switches UIKit animations off in the app the runner launches; absent leaves them on (SimWalk#154).
        environment[AnimationsOptIn.hostEnvironmentKey] = animationsOffLibrary
        // A live session's steps are `systemTap`s too, so they name a fresh boot as a walk's do (SimWalk#88).
        addDeviceBootedAt(to: &environment, on: simulator)
        return RunnerCommand(
            executable: "/usr/bin/xcodebuild",
            arguments: testArguments(only: "testSession", resultBundlePath: layout.resultBundle.path, destination: Self.destination(of: simulator)),
            environment: environment,
            inheritedDescriptor: progress?.descriptorForChild
        )
    }

    /// The command line of a live session's resident runner on a physical device (SimWalk#116): `testSession` against the device, told its session by id (`layout`'s directory name) and what to launch as JSON, since the device can reach no host path; its result bundle goes in the session's directory on the Mac.
    ///
    /// **Never the session's token**: it reaches the runner only through `bind.json` in its container, deleted once read (Brief, "Live sessions on a physical device", ruling 2). An environment can end up in a log or a result bundle; the token must not. The id selects device mode and is each read's nonce.
    public func deviceSession(
        layout: LiveSessionLayout,
        launchJSON: String,
        udid: String,
        runnerCommit: String?,
        idleOverride: String?,
        deviceAppearance: Walkbook.Theme?
    ) -> RunnerCommand {
        var environment = [
            "TEST_RUNNER_SIMWALK_SESSION_DEVICE": layout.directory.lastPathComponent,
            "TEST_RUNNER_SIMWALK_SESSION_LAUNCH_JSON": launchJSON,
            "TEST_RUNNER_SIMWALK_DEVICE_UDID": udid,
        ]
        environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] = deviceAppearance?.rawValue
        environment["TEST_RUNNER_SIMWALK_RUNNER_COMMIT"] = runnerCommit
        environment["TEST_RUNNER_" + LiveSessionIdle.overrideVariable] = idleOverride
        return RunnerCommand(
            executable: "/usr/bin/xcodebuild",
            arguments: testArguments(only: "testSession", resultBundlePath: layout.resultBundle.path, destination: "platform=iOS,id=\(udid)"),
            environment: environment
        )
    }

    /// Where one run's result bundle goes: under this build's own `Logs/Test`, where `xcodebuild` files one unasked, but at a path named in advance, so a failure's refusal can read it without searching (SimWalk#50).
    ///
    /// One per run — the launch time for a reader listing the directory, and `id` because two walks of one build can launch in the same second. `xcodebuild` refuses a result bundle path that already exists, so a name must never be reused.
    public func resultBundlePath(launchedAt: Date, id: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        return URL(fileURLWithPath: derivedDataPath)
            .appendingPathComponent("Logs/Test", isDirectory: true)
            .appendingPathComponent("simwalk-\(formatter.string(from: launchedAt))-\(id.prefix(8)).xcresult")
            .path
    }

    /// Runs the built runner's `testWalk` with `environment`, the tail a walk and a live read share.
    ///
    /// **`testWalk` by name, never the whole class**: the class also holds `testSession`, a live session's resident server, which must never start inside a walk's run. It returns at once without a session named, but a walk should not pay for it or depend on that.
    ///
    /// **`-collect-test-diagnostics never`** (SimWalk#54): on a runner that stalls — behind a system alert, say — `xcodebuild` otherwise starts `simctl diagnose --timeout=600` after the failure has already happened, and the walk's verdict waits up to ten more minutes on a sysdiagnose nobody reads. The failure's own account is the result bundle's (#50).
    private func runBuilt(environment: [String: String], resultBundlePath: String?, on simulator: Simulator) throws {
        let result = try shell.run("/usr/bin/xcodebuild", testArguments(only: "testWalk", resultBundlePath: resultBundlePath, destination: Self.destination(of: simulator)), environment: environment)

        guard result.succeeded else {
            throw RunnerError.walkFailed(reason: Self.diagnostic(from: result))
        }
    }

    /// The `test-without-building` command line that runs one of the runner's tests, which a walk, a live read and a session share: only the test named, no diagnostics collected, and the result bundle where one is named.
    private func testArguments(only test: String, resultBundlePath: String?, destination: String) -> [String] {
        [
            "test-without-building",
            "-project", projectPath,
            "-scheme", Self.scheme,
            "-destination", destination,
            "-derivedDataPath", derivedDataPath,
            "-only-testing:\(Self.scheme)/WalkRunner/\(test)",
            "-collect-test-diagnostics", "never",
        ] + (resultBundlePath.map { ["-resultBundlePath", $0] } ?? [])
    }

    private static func destination(of simulator: Simulator) -> String {
        "platform=iOS Simulator,id=\(simulator.udid)"
    }

    static var scheme: String {
        "SimWalkRunner"
    }

    /// The lines worth showing from an `xcodebuild` failure.
    ///
    /// Its output runs to megabytes and its last line is usually `** TEST FAILED **`, which names nothing. The assertion and error lines are the part a human can act on, so those are lifted out and the rest dropped.
    private static func diagnostic(from result: Shell.Result) -> String {
        let interesting = (result.standardOutput + "\n" + result.standardError)
            .split(separator: "\n")
            .filter { line in
                line.contains("error:") || line.contains("XCTAssert") || line.contains("failed —") || line.contains("Failing tests:")
            }
            .suffix(6)
        guard interesting.isEmpty else {
            return interesting.joined(separator: "\n  ")
        }
        return result.failureLine
    }
}
