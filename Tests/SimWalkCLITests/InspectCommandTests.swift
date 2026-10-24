//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `simwalk inspect` against a script (SimWalk#49): the runner is told it is a live read and which app, its file is read back as this run's, and a device or app that is not there to read is refused rather than started.
struct InspectCommandTests {
    /// The whole sequence: the runner is handed the mode, the app and this run's nonce, the file it writes is answered in `bundle screen`'s form, the device is handed back after it, and the file is gone afterwards.
    @Test
    func aliveReadAnswersWithTheScreenTheRunnerRead() throws {
        let directory = try TemporaryDirectory()
        let inspection = try Self.inspect(leaving: Self.screen(), in: directory)
        let (answer, script, output) = (inspection.answer, inspection.script, inspection.output)

        let runnerIndex = try #require(script.calls.firstIndex { $0.arguments.contains("test-without-building") })
        let restoreIndex = try #require(script.calls.firstIndex { $0.arguments.contains("write") })
        let environment = script.calls[runnerIndex].environment

        #expect(environment["TEST_RUNNER_SIMWALK_INSPECT"] == "1")
        #expect(environment["TEST_RUNNER_SIMWALK_APP_BUNDLE_ID"] == "com.example.live")
        #expect(environment["TEST_RUNNER_SIMWALK_NONCE"] == Self.nonce)
        #expect(environment["TEST_RUNNER_SIMWALK_OUTPUT"] == output.path)
        #expect(environment["TEST_RUNNER_SIMWALK_WALKBOOK"] == nil)
        #expect(runnerIndex < restoreIndex)
        #expect(answer.header.hasPrefix("live: app: com.example.live"))
        #expect(answer.text.contains("Welcome to Health"))
        #expect(answer.text.contains("accessibility"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    /// The runner's image is filed as `inspect-<nonce>.png` under the state's screenshots directory and the directory pruned to the newest 20.
    @Test
    func theRunnersImageIsFiledByNonceAndTheDirectoryPruned() throws {
        let directory = try TemporaryDirectory()
        let screenshots = directory.url.appendingPathComponent("screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        for index in 0 ..< ScreenshotOption.keptCount {
            let old = screenshots.appendingPathComponent("inspect-old\(index).png")
            try Data().write(to: old)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: old.path)
        }
        let runnerPNG = directory.url.appendingPathComponent("runner.png")
        try SessionCommandTests.png(width: 402, height: 874).write(to: runnerPNG)
        let tree = try #require(SessionCommandTests.screen.tree)
        let request = try #require(ScreenshotFit.Request())

        let line = ScreenshotFit.line(InspectCommand.screenshotOutcome(runnerPNG: runnerPNG, nonce: "N1", tree: tree, request: request, in: screenshots))

        let filed = screenshots.appendingPathComponent("inspect-N1.png")

        #expect(line.hasPrefix("screenshot: \(filed.path) (402×874 px, point scale"))
        #expect(FileManager.default.fileExists(atPath: filed.path))
        #expect(!FileManager.default.fileExists(atPath: screenshots.appendingPathComponent("inspect-old0.png").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: screenshots.path).count == ScreenshotOption.keptCount)
    }

    /// A runner that left no image is the line saying so, and nothing is filed.
    @Test
    func aRunnerThatLeftNoImageIsTheLineSayingSo() throws {
        let directory = try TemporaryDirectory()
        let screenshots = directory.url.appendingPathComponent("screenshots", isDirectory: true)
        let tree = try #require(SessionCommandTests.screen.tree)
        let request = try #require(ScreenshotFit.Request())

        let line = ScreenshotFit.line(InspectCommand.screenshotOutcome(runnerPNG: directory.url.appendingPathComponent("none.png"), nonce: "N2", tree: tree, request: request, in: screenshots))

        #expect(line == "screenshot: not written — the runner wrote no image")
        #expect(!FileManager.default.fileExists(atPath: screenshots.appendingPathComponent("inspect-N2.png").path))
    }

    /// An app found not running is refused with the launch command that would fix it, exit 1, logged as a refusal of what was asked rather than a runner failure — and the handback note still reaches the reader.
    @Test
    func anAppNotRunningIsRefusedNamingTheLaunchCommand() throws {
        let directory = try TemporaryDirectory()
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        var errors: [String] = []
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])

        let thrown = #expect(throws: ExitCode.self) {
            try command.run(log: log, emit: { _ in }, emitError: { errors.append($0) }, read: {
                try Self.inspect(leaving: Self.screen(state: .notRunning), in: directory).answer
            })
        }

        let entry = try #require(UsageReport.entries(at: log.fileURL).entries.first)
        let refusal = try #require(errors.first)

        #expect(thrown == ExitCode(AnswerVerdict.refusedExitCode))
        #expect(refusal.contains("xcrun simctl launch UDID-1 com.example.live"))
        #expect(refusal.contains("accessibility"))
        #expect(entry.tool == "inspect")
        #expect(entry.kind == .inputRefused)
    }

    /// A device that is not booted is refused before any runner is built or run, and is never booted.
    @Test
    func adeviceThatIsNotBootedIsRefusedAndNeverBooted() throws {
        let directory = try TemporaryDirectory()
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 0, booted: false)
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])

        #expect(throws: SimulatorError.notBooted(name: "iPhone 17 Pro", udid: "UDID-1")) {
            try command.perform(shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { Self.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), scratch: directory.url)
        }
        #expect(!script.calls.contains { $0.arguments.contains("boot") || $0.arguments.contains("test-without-building") || $0.arguments.contains("build-for-testing") })
    }

    /// `perform` passes `note` to the build: an empty build directory is told as a cold build (SimWalk#98, #118).
    @Test
    func anInspectOverAnEmptyBuildDirectoryTellsTheCallerItIsAColdBuild() throws {
        let directory = try TemporaryDirectory()
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 1)
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])
        var notes: [String] = []

        _ = try? command.perform(shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { Self.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), scratch: directory.url, note: { notes.append($0) })

        #expect(notes == ["building the runner (c0ffee00) — a first build takes several minutes"])
    }

    /// With no `--device` given and nothing booted, `Simulator.resolve` picks a device nobody asked for (`devices[0]`) — the refusal must not name it as though it were chosen, and instead says no simulator is booted at all (SimWalk#51.2).
    @Test
    func withNoDeviceGivenAndNothingBootedTheRefusalNamesNoDeviceAtAll() throws {
        let directory = try TemporaryDirectory()
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 0, booted: false)
        let command = try InspectCommand.parse(["--app", "com.example.live"])

        #expect(throws: SimulatorError.noSimulatorBooted) {
            try command.perform(shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { Self.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), scratch: directory.url)
        }
    }

    /// A runner failure's refusal names its result bundle (SimWalk#50), which only reaches the reader because `perform` wires its real `diagnosingRunnerFailure` through to `Self.outcome` — this exercises `perform` itself, not `outcome` directly, so it is red if that wiring is ever dropped (SimWalk#51.3a).
    @Test
    func arunnerFailureIsDiagnosedFromTheResultBundlePerformActuallyNamed() throws {
        let directory = try TemporaryDirectory()
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 1)
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])

        let thrown = #expect(throws: WalkCommand.Refusal.self) {
            try command.perform(shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { Self.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: Self.leases(in: directory), scratch: directory.url)
        }

        let refusal = try #require(thrown)
        // No `.xcresult` was ever written at the path `perform` named, so a real `RunnerFailureDiagnosis.read`
        // answers `.unreadable` with this line — the default `{ nil }` `outcome` would fall back to answers
        // with none of it, which is exactly the gap the removed wiring leaves.
        #expect(refusal.runnerDiagnosis.contains { $0.contains("the runner wrote no result bundle") })
    }

    /// An inspect holds a claim on its simulator from its appearance read through the runner, and none after (SimWalk#128).
    @Test
    func anInspectHoldsAClaimFromItsAppearanceReadThroughTheRunnerAndNoneAfter() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let staged = directory.url.appendingPathComponent("staged-live.json")
        let output = directory.url.appendingPathComponent("simwalk-inspect-\(Self.nonce).json")
        try Self.screen().write(to: staged)
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 0, writes: (staged, output))
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])
        var walkedAtAppearanceRead: Set<String>?
        var walkedDuringRunner: Set<String> = []
        let shell = Shell { executable, arguments, environment in
            if walkedAtAppearanceRead == nil, arguments.starts(with: ["simctl", "ui"]) {
                walkedAtAppearanceRead = WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive)
            }
            if arguments.contains("test-without-building") {
                walkedDuringRunner = WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive)
            }
            return try script.run(executable, arguments, environment)
        }

        _ = try command.perform(shell: shell, pause: { _ in }, now: script.now, nonce: { Self.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases, scratch: directory.url)

        #expect(walkedAtAppearanceRead == ["UDID-1"])
        #expect(walkedDuringRunner == ["UDID-1"])
        #expect(WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).isEmpty)
    }

    /// An inspect refused after it took its claim — here the runner fails — leaves none behind (SimWalk#128).
    @Test
    func anInspectRefusedAfterTakingItsClaimLeavesNoClaim() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 1)
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])
        var walkedDuringRunner: Set<String> = []
        let shell = Shell { executable, arguments, environment in
            if arguments.contains("test-without-building") {
                walkedDuringRunner = WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive)
            }
            return try script.run(executable, arguments, environment)
        }

        #expect(throws: WalkCommand.Refusal.self) {
            try command.perform(shell: shell, pause: { _ in }, now: script.now, nonce: { Self.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases, scratch: directory.url)
        }

        #expect(walkedDuringRunner == ["UDID-1"])
        #expect(WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).isEmpty)
    }

    /// A claim that cannot be written is the lease store failing, so the usage log records `tool-error`, not the call site's default `runner-failed` (SimWalk#128).
    @Test
    func anInspectWhoseClaimCannotBeWrittenIsLoggedAsAToolError() throws {
        let directory = try TemporaryDirectory()
        let leases = Self.leases(in: directory)
        try FileManager.default.createDirectory(at: leases.directory, withIntermediateDirectories: true)
        try Data().write(to: leases.directory.appendingPathComponent(".walks"))
        let log = UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 0)
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])

        #expect(throws: ExitCode.self) {
            try command.run(log: log, emit: { _ in }, emitError: { _ in }, read: {
                try command.perform(shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { Self.nonce }, runner: { Self.runner }, builds: Self.builds(in: directory), leases: leases, scratch: directory.url)
            })
        }

        let entry = try #require(UsageReport.entries(at: log.fileURL).entries.first)

        #expect(entry.kind == .toolError)
    }

    /// The accessibility line on an inspect names the inspect, not a walk.
    @Test
    func theAccessibilityLineOnAnInspectNamesTheInspect() throws {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .restored(.light)
        )

        let answer = try InspectCommand.outcome(runnerFailure: nil, handback: handback, readingScreen: { Self.screen() }, match: nil)

        #expect(answer.text.contains("this inspect switched it back on"))
        #expect(!answer.text.contains("this walk"))
    }

    /// SimWalk#159: the appearance line on an inspect names the inspect too, not a walk.
    @Test
    func theAppearanceLineOnAnInspectNamesTheInspect() throws {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .failed(found: .light, reason: "boom")
        )

        let answer = try InspectCommand.outcome(runnerFailure: nil, handback: handback, readingScreen: { Self.screen() }, match: nil)

        #expect(answer.text.contains("UDID-1 was light before this inspect started and could not be put back"))
        #expect(!answer.text.contains("before this walk"))
    }

    /// SimWalk#214: a refused inspect's handback names the inspect too, not a walk.
    @Test
    func theAccessibilityLineOnARefusedInspectNamesTheInspect() throws {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .restored(.light)
        )

        let thrown = #expect(throws: WalkCommand.Refusal.self) {
            try InspectCommand.outcome(runnerFailure: nil, handback: handback, readingScreen: { throw LiveScreenError.missing(path: "/nowhere", reason: "boom") }, match: nil)
        }

        let text = try "\(#require(thrown))"

        #expect(text.contains("this inspect switched it back on"))
        #expect(!text.contains("this walk"))
    }

    /// SimWalk#218: an inspect of an app that was not running is refused with a handback that names the inspect too, not a walk.
    @Test
    func theAccessibilityLineOnAnInspectOfAClosedAppNamesTheInspect() throws {
        let handback = DeviceHandback(
            accessibility: AccessibilityPreference.Restoration(udid: "UDID-1", state: .restored),
            appearance: .restored(.light)
        )

        let thrown = #expect(throws: WalkCommand.Refusal.self) {
            try InspectCommand.outcome(runnerFailure: nil, handback: handback, readingScreen: { Self.screen(state: .notRunning) }, match: nil)
        }

        let text = try "\(#require(thrown))"

        #expect(text.contains("this inspect switched it back on"))
        #expect(!text.contains("this walk"))
    }

    /// SimWalk#243: an app that is not running because it crashed is refused naming the crash and its report, still as the device the caller left; with no report it is plain not running.
    @Test
    func anAppThatCrashedIsRefusedNamingTheCrashReport() throws {
        let directory = try TemporaryDirectory()
        let report = directory.url.appendingPathComponent("Live-2026-10-23-233232.ips")
        let header = #"{"app_name":"Live","timestamp":"2026-10-23 23:32:32.00 +0100","bundleID":"com.example.live","bug_type":"309"}"#
        let body = #"{"procPath":"/Users/USER/Library/Developer/CoreSimulator/Devices/UDID-1/data/Containers/Bundle/Application/X/Live.app/Live"}"#
        try Data((header + "\n" + body).utf8).write(to: report)
        let lookup = { AppCrashReport.latest(bundleID: "com.example.live", udid: "UDID-1", since: nil, in: directory.url) }

        let crashed = #expect(throws: LiveScreenError.self) {
            try InspectCommand.outcome(runnerFailure: nil, handback: nil, readingScreen: { Self.screen(state: .notRunning) }, match: nil, crashReport: lookup)
        }
        let plain = #expect(throws: LiveScreenError.self) {
            try InspectCommand.outcome(runnerFailure: nil, handback: nil, readingScreen: { Self.screen(state: .notRunning) }, match: nil, crashReport: { nil })
        }

        let text = try "\(#require(crashed))"

        // The temporary directory is listed back through `/private`, so the report is matched by its directory's name and its own.
        #expect(text.hasPrefix("com.example.live is not running on UDID-1: it crashed at 2026-10-23T22:32:32Z (crash report /"))
        #expect(text.contains("\(directory.url.lastPathComponent)/\(report.lastPathComponent)) — "))
        #expect(text.contains("xcrun simctl launch UDID-1 com.example.live"))
        #expect(crashed?.usageFailureKind == .inputRefused)
        #expect(plain == .appNotRunning(bundleID: "com.example.live", udid: "UDID-1"))
    }

    /// A live read of `screen`, which the scripted runner leaves where the command told it to write.
    private static func inspect(leaving screen: LiveScreen, in directory: TemporaryDirectory) throws -> Inspection {
        let staged = directory.url.appendingPathComponent("staged-live.json")
        let output = directory.url.appendingPathComponent("simwalk-inspect-\(nonce).json")
        if !FileManager.default.fileExists(atPath: staged.path) {
            try screen.write(to: staged)
        }
        let script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 0, writes: (staged, output))
        let command = try InspectCommand.parse(["--device", "UDID-1", "--app", "com.example.live"])
        let answer = try command.perform(shell: Shell(script: script.run), pause: { _ in }, now: script.now, nonce: { nonce }, runner: { runner }, builds: builds(in: directory), leases: Self.leases(in: directory), scratch: directory.url)
        return Inspection(answer: answer, script: script, output: output)
    }

    private static func screen(state: LiveScreen.AppState = .foreground) -> LiveScreen {
        let tree = state == .notRunning ? nil : AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            label: "Live",
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 40), label: "Welcome to Health"),
            ]
        )
        return LiveScreen(
            appBundleID: "com.example.live",
            device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "UDID-1", osVersion: "26.5"),
            runnerCommit: runner.commit,
            readAt: Date(timeIntervalSince1970: 1_790_000_000),
            nonce: nonce,
            appState: state,
            tree: tree,
            settled: tree == nil ? nil : true,
            screenPixels: LiveScreen.Pixels(width: 1206, height: 2622)
        )
    }

    private static var nonce: String {
        "NONCE-1"
    }

    private static var runner: RunnerSource {
        RunnerSource(
            projectPath: "/Users/x/.simwalk/runner/snapshots/c0ffee/Runner/SimWalkRunner.xcodeproj",
            commit: "c0ffee0000000000000000000000000000000000",
            origin: .installed
        )
    }

    /// The leases these reads see — the test's own scratch store, never the machine's `~/.simwalk/leases`.
    private static func leases(in directory: TemporaryDirectory) -> LeaseStore {
        LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
    }

    private static func builds(in directory: TemporaryDirectory) -> RunnerBuilds {
        RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
    }
}

private extension InspectCommandTests {
    /// What a live read left for a test to look at: the answer, the scripted shell that ran it, and where the runner was told to write.
    struct Inspection {
        let answer: Answer
        let script: WalkCommandTests.WalkScript
        let output: URL
    }
}
