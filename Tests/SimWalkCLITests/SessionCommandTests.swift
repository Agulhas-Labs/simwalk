//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// `simwalk session …` against a fake runner process and a scripted device: no simulator, no `xcodebuild`.
struct SessionCommandTests {
    /// A ready runner: the session test is spawned with the session's directory, the app and state go in `launch.json`, and the answer names the id.
    @Test
    func startSpawnsTheSessionRunnerAndPrintsTheIdOnceReady() throws {
        let fixture = try Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(Self.ready) }

        let answer = try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])

        let command = try #require(fixture.processes.spawned.first)

        #expect(command.arguments.contains("-only-testing:SimWalkRunner/WalkRunner/testSession"))
        #expect(command.environment["TEST_RUNNER_SIMWALK_SESSION"] == fixture.store.layout(id: "s1").directory.path)
        #expect(try fixture.channel("s1").launch() == LiveSessionLaunch(appBundleID: "com.example.live", state: Walkbook.CaptureState(theme: .dark)))
        #expect(fixture.store.record(id: "s1")?.pid == fixture.processes.nextPID)
        #expect(answer.residue.first == "id: s1")
        #expect(answer.verdict == .unqualified("session s1 ready"))
    }

    /// `perform` passes `note` to the simulator build: an empty build directory is told as a cold build (SimWalk#98, #118).
    @Test
    func startOverAnEmptyBuildDirectoryTellsTheCallerItIsAColdBuild() throws {
        let fixture = try Fixture()
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(Self.ready) }
        var notes: [String] = []

        _ = try fixture.start(["--device", "UDID-1", "--app", "com.example.live"], note: { notes.append($0) })

        #expect(notes == ["building the runner (c0ffee) — a first build takes several minutes"])
    }

    /// A device whose session is alive is refused before anything is spawned.
    @Test
    func startRefusesADeviceWithALiveSession() throws {
        let fixture = try Fixture()
        _ = try fixture.store.create(id: "old")
        try fixture.store.write(LiveSessionRecord(id: "old", pid: 99, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: nil))
        fixture.processes.runner(99)

        #expect(throws: LiveSessionHostError.alreadyRunning(udid: "UDID-1", id: "old", pid: 99)) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live"])
        }

        #expect(fixture.processes.spawned.isEmpty)
    }

    /// A runner that never becomes ready is stopped, the device handed back, its diagnosis read, and its directory removed.
    @Test
    func startCleansUpARunnerThatNeverBecomesReady() throws {
        let fixture = try Fixture()

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live"])
        }

        guard case let .neverReady(reason, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }

        #expect(reason == "no ready.json within 180 s")
        #expect(fixture.processes.signalled.map(\.group) == [fixture.processes.nextPID])
        #expect(lines.contains { $0.contains("the runner wrote no result bundle") })
        #expect(fixture.script.calls.contains { $0.arguments == AccessibilityPreference.enableArguments(udid: "UDID-1")[0] })
        #expect(fixture.store.all().isEmpty)
    }

    /// `--device` with `--lease`, and neither, are refused at parse time.
    @Test
    func startTakesExactlyOneOfDeviceAndLease() {
        let both = ["--app", "a", "--device", "U", "--lease", "T"]

        #expect(throws: (any Error).self) { try SessionStartCommand.parse(both) }
        #expect(throws: (any Error).self) { try SessionStartCommand.parse(["--app", "a"]) }
    }

    /// A warm read renders exactly what `inspect` renders for the same screen, `--match` included.
    @Test
    func readRendersWhatInspectRendersForTheSameScreen() throws {
        let fixture = try Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        fixture.onPause = {
            let channel = fixture.channel("s1")
            if let request = try? channel.request(1), (try? channel.response(to: 1)) == nil {
                try? channel.respond(LiveSessionResponse(n: request.n, action: .read, screen: Self.screen))
            }
        }
        let command = try SessionReadCommand.parse(["s1", "--match", "welcome"])

        let answer = try command.perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)

        let inspected = try InspectCommand.outcome(runnerFailure: nil, handback: nil, readingScreen: { Self.screen }, match: "welcome")

        #expect(answer == inspected)
        #expect(answer.text.contains("Welcome to Health"))
    }

    /// `step` sends the walkbook step and its guard as the next request and prints the runner's answer: the landed step, the screen's hash and the delta.
    @Test
    func stepSendsTheStepWithItsGuardAndPrintsTheLandedStep() throws {
        let fixture = try Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        var sent: LiveSessionRequest?
        let tree = try #require(Self.screen.tree)
        fixture.onPause = {
            let channel = fixture.channel("s1")
            if let request = try? channel.request(1), (try? channel.response(to: 1)) == nil {
                sent = request
                let delta = ScreenDelta(from: tree, to: tree)
                try? channel.respond(LiveSessionResponse(n: 1, action: .step, screen: Self.screen, step: .landed(.tap(label: "Steps"), delta: delta)))
            }
        }

        let answer = try SessionStepCommand.parse(["s1", #"{"tap":{"label":"Steps"}}"#, "--guard", "1a2b3c4d"])
            .perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)

        #expect(sent == LiveSessionRequest(n: 1, action: .step, step: .tap(label: "Steps"), guardHash: "1a2b3c4d"))
        #expect(answer.verdict == .unqualified("landed tap 'Steps' — now on root (no identifier — no container in the content carries one)"))
        #expect(answer.residue.prefix(3) == [#"step: {"tap":{"label":"Steps"}}"#, "screen \(ScreenHash.of(tree))", "delta: nothing appeared or disappeared"])
    }

    /// SimWalk#75: a session whose pid another process has since taken has no runner to answer — `read` and `step` say so at once rather than waiting out their timeout on a live stranger.
    @Test(arguments: ["read", "step"])
    func readAndStepOnAReusedPidSayTheRunnerStopped(_ verb: String) throws {
        let fixture = try Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        fixture.processes.startTimes[77] = Date(timeIntervalSince1970: 3600)

        #expect(throws: LiveSessionError.runnerExited(number: 1, exit: nil)) {
            if verb == "read" {
                _ = try SessionReadCommand.parse(["s1"]).perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)
            } else {
                _ = try SessionStepCommand.parse(["s1", #"{"tap":{"label":"Steps"}}"#]).perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)
            }
        }
    }

    /// A step that is not a walkbook route step is refused before anything is sent.
    @Test
    func stepRefusesJSONThatIsNotARouteStep() throws {
        let fixture = try Fixture()
        try fixture.session("s1", pid: 77)

        #expect(throws: (any Error).self) {
            try SessionStepCommand.parse(["s1", #"{"poke":{}}"#]).perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)
        }
        #expect(fixture.store.layout(id: "s1").requestNumbers().isEmpty)
    }

    /// An unknown id is refused by name.
    @Test
    func readAndEndRefuseAnUnknownSession() throws {
        let fixture = try Fixture()

        #expect(throws: LiveSessionHostError.unknownSession(id: "nope")) {
            try SessionReadCommand.parse(["nope"]).perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)
        }
        #expect(throws: LiveSessionHostError.unknownSession(id: "nope")) {
            try SessionEndCommand.parse(["nope"]).perform(store: fixture.store, processes: fixture.processes, shell: Shell(script: fixture.script.run), pause: fixture.pause, now: fixture.now)
        }
    }

    /// A stale record whose pid another process has since taken is not running: `list` says the pid is not the session's runner, and `start` on its device is not refused for it.
    @Test
    func aReusedPidIsNeitherListedAsRunningNorRefusesAStart() throws {
        let fixture = try Fixture()
        try fixture.session("stale", pid: 12)
        fixture.processes.runner(12)
        fixture.processes.startTimes[12] = Date(timeIntervalSince1970: 3600)
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(Self.ready) }

        let listed = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(script: fixture.script.run), pause: fixture.pause, now: fixture.now)

        #expect(listed.verdict == .unqualified("1 session, 0 running"))
        #expect(listed.residue.count == 2)
        #expect(listed.residue.first == "stale · com.example.live · UDID-1 · exited: pid 12 is running but is not this session's runner: it started 3600 s after this session's record was written — `simwalk session end stale` cleans it up")
        #expect(listed.residue.last == "stale · accessibility: the runner stopped without `end`, its teardown switched \(AccessibilityPreference.domain) \(AccessibilityPreference.key) off, and `session list` switched it back on for UDID-1 and saw it hold")
        #expect(LiveSessionStart(store: fixture.store, processes: fixture.processes).liveSession(on: "UDID-1") == nil)
        _ = try fixture.start(["--device", "UDID-1", "--app", "com.example.live"])
        #expect(fixture.store.record(id: "s1") != nil)
    }

    /// A session whose runner is gone is listed as exited, with the command that cleans it up — and `end` does.
    @Test
    func listReportsADeadPidAndEndCleansItUp() throws {
        let fixture = try Fixture()
        try fixture.session("alive", pid: 10)
        try fixture.session("dead", pid: 11)
        fixture.processes.runner(10)

        let listed = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(script: fixture.script.run), pause: fixture.pause, now: fixture.now)

        #expect(listed.verdict == .unqualified("2 sessions, 1 running"))
        #expect(listed.residue.contains("dead · com.example.live · UDID-1 · exited: pid 11 is gone — `simwalk session end dead` cleans it up"))
        #expect(listed.residue.contains("alive · com.example.live · UDID-1 · running (pid 10)"))
        #expect(listed.residue.count == 2)
        #expect(!fixture.script.calls.contains { $0.arguments == AccessibilityPreference.enableArguments(udid: "UDID-1")[0] })

        let ended = try SessionEndCommand.parse(["dead"]).perform(store: fixture.store, processes: fixture.processes, shell: Shell(script: fixture.script.run), pause: fixture.pause, now: fixture.now)

        #expect(ended.residue.first == "the runner (pid 11) had already exited")
        #expect(fixture.store.all().map(\.id) == ["alive"])
    }

    /// A session whose runner stopped without `end` — the idle timeout here — has its device's accessibility switched back on by the next `list`, once, and every `list` says so: the XCUITest teardown switched it off after the runner's last line, when nothing on the host was running.
    @Test
    func listSwitchesAccessibilityBackOnOnceAfterAnIdleExit() throws {
        let fixture = try Fixture()
        try fixture.session("idle", pid: 11)
        try fixture.channel("idle").markExit(.idle(after: 900, served: 3, stoppedAt: Date(timeIntervalSince1970: 60)))
        let enable = AccessibilityPreference.enableArguments(udid: "UDID-1")[0]
        let list = { SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: Shell(script: fixture.script.run), pause: fixture.pause, now: fixture.now) }

        let first = list()
        let writes = fixture.script.calls.count { $0.arguments == enable }
        let second = list()

        #expect(writes == 1)
        #expect(fixture.script.calls.count { $0.arguments == enable } == 1)
        #expect(first.verdict == .unqualified("1 session, 0 running"))
        #expect(first.residue.last == "idle · accessibility: the runner stopped without `end`, its teardown switched \(AccessibilityPreference.domain) \(AccessibilityPreference.key) off, and `session list` switched it back on for UDID-1 and saw it hold")
        #expect(first.residue.count == 2)
        #expect(second.residue == first.residue)
    }

    /// A state whose theme the device is not in reboots the device into it before the runner is spawned — the cure for an appearance a simulator reports and does not draw — and the runner is still told what the device was found in, which is what it puts back.
    @Test
    func startSettlesTheDeviceWhenTheStateThemeDiffers() throws {
        let fixture = try Fixture(appearance: "light")
        var callsAtSpawn = 0
        fixture.processes.onSpawn = { _ in
            callsAtSpawn = fixture.script.calls.count
            try? fixture.channel("s1").markReady(Self.ready)
        }

        let answer = try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])

        let beforeSpawn = fixture.script.calls.prefix(callsAtSpawn).map(\.arguments)

        #expect(beforeSpawn.contains(["simctl", "ui", "UDID-1", "appearance", "dark"]))
        #expect(beforeSpawn.contains(["simctl", "shutdown", "UDID-1"]))
        #expect(beforeSpawn.contains(["simctl", "bootstatus", "UDID-1", "-b"]))
        #expect(fixture.processes.spawned.first?.environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] == "light")
        #expect(fixture.store.record(id: "s1")?.foundAppearance == .light)
        #expect(answer.residue.last == "settled: UDID-1 was light and the state is dark, so it was rebooted dark first; `session end` puts it back to light")
    }

    /// A state in the appearance the device is already in reboots nothing.
    @Test
    func startDoesNotSettleWhenTheStateThemeMatches() throws {
        let fixture = try Fixture(appearance: "dark")
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(Self.ready) }

        let answer = try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])

        #expect(!fixture.script.calls.contains { $0.arguments.starts(with: ["simctl", "shutdown"]) })
        #expect(fixture.processes.spawned.first?.environment["TEST_RUNNER_SIMWALK_DEVICE_APPEARANCE"] == "dark")
        #expect(!answer.residue.contains { $0.hasPrefix("settled:") })
    }

    /// A settle that fails starts nothing, and the refusal names the settle to run by hand.
    @Test
    func startRefusesWhenTheSettleFails() throws {
        let fixture = try Fixture(appearance: "light", failing: ["shutdown"])

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])
        }

        #expect(error == .settleFailed(
            udid: "UDID-1",
            theme: .dark,
            step: "shutting it down",
            reason: "An error was encountered processing the command (code=164)",
            command: "xcrun simctl ui UDID-1 appearance dark && xcrun simctl shutdown UDID-1 && xcrun simctl boot UDID-1 && xcrun simctl bootstatus UDID-1 -b"
        ))
        #expect(fixture.processes.spawned.isEmpty)
        #expect(fixture.store.all().isEmpty)
    }

    /// A second start on a device whose claim a live start holds is refused before it builds or settles anything.
    @Test
    func startRefusesADeviceAnotherStartHasClaimed() throws {
        let fixture = try Fixture(appearance: "light")
        fixture.processes.alive.insert(777)
        let held = try LiveSessionStart(store: fixture.store, processes: fixture.processes).claim(udid: "UDID-1", holder: 777)

        #expect(throws: LiveSessionHostError.startInProgress(udid: "UDID-1", holder: 777)) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])
        }

        #expect(!fixture.script.calls.contains { $0.arguments.contains("build-for-testing") || $0.arguments.starts(with: ["simctl", "ui"]) || $0.arguments.starts(with: ["simctl", "shutdown"]) })
        #expect(fixture.processes.spawned.isEmpty)
        #expect(FileManager.default.fileExists(atPath: held.file.path))
    }

    /// A start under `--lease T` records T, so the handback can tell its own caller's lease from a stranger's; a start by UDID records none.
    @Test
    func startUnderALeaseRecordsItsToken() throws {
        let fixture = try Fixture()
        _ = try fixture.leases.acquire(udid: "UDID-1", ttl: 1800, holderPID: getpid(), now: Date(timeIntervalSince1970: 0), token: "LEASE-1")
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(Self.ready) }

        _ = try fixture.start(["--lease", "LEASE-1", "--app", "com.example.live"])

        #expect(fixture.store.record(id: "s1")?.leaseToken == "LEASE-1")
    }

    /// A claim whose claimant has died is taken over, and a start releases its claim once its record is written.
    @Test
    func startReclaimsADeadClaimantsClaimAndReleasesItsOwn() throws {
        let fixture = try Fixture()
        let stale = try LiveSessionStart(store: fixture.store, processes: fixture.processes).claim(udid: "UDID-1", holder: 778)
        fixture.processes.onSpawn = { _ in try? fixture.channel("s1").markReady(Self.ready) }

        _ = try fixture.start(["--device", "UDID-1", "--app", "com.example.live"])

        #expect(fixture.store.record(id: "s1") != nil)
        #expect(!FileManager.default.fileExists(atPath: stale.file.path))
    }

    /// A start's claim is released once its record is written, before it waits for the runner: an `end` while the runner is still launching would otherwise take the session's own start for another holder of the device (SimWalk#128).
    @Test
    func startReleasesItsClaimBeforeWaitingForTheRunner() throws {
        let fixture = try Fixture()
        var claimedWhileWaiting: Bool?
        fixture.onPause = {
            guard claimedWhileWaiting == nil else { return }
            claimedWhileWaiting = FileManager.default.fileExists(atPath: fixture.store.claim(udid: "UDID-1").path)
            try? fixture.channel("s1").markReady(Self.ready)
        }

        _ = try fixture.start(["--device", "UDID-1", "--app", "com.example.live"])

        #expect(claimedWhileWaiting == false)
    }

    /// A start that fails after its settle puts the device back in the appearance it found, which nothing else would.
    @Test
    func startThatFailsAfterASettleHandsTheAppearanceBack() throws {
        let fixture = try Fixture(appearance: "light")
        fixture.processes.spawnError = RunnerError.walkFailed(reason: "could not start xcrun")

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])
        }

        let calls = fixture.script.calls.map(\.arguments)
        let rebooted = try #require(calls.lastIndex(of: ["simctl", "shutdown", "UDID-1"]))

        #expect(calls.suffix(from: rebooted).contains(["simctl", "ui", "UDID-1", "appearance", "light"]))
        #expect(error.description.contains("could not start xcrun"))
        #expect(fixture.store.all().isEmpty)
    }

    /// A runner that never becomes ready after a settle is refused with the settle's reboot named, since its launch of the app came straight after it (SimWalk#69), and the stop puts the found appearance back.
    @Test
    func startWhoseRunnerNeverBecomesReadyAfterASettleNamesTheReboot() throws {
        let fixture = try Fixture(appearance: "light")

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])
        }

        guard case let .neverReady(reason, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }
        let calls = fixture.script.calls.map(\.arguments)
        let rebooted = try #require(calls.lastIndex(of: ["simctl", "shutdown", "UDID-1"]))

        #expect(reason == "no ready.json within 180 s")
        #expect(lines.last == "settled: UDID-1 was rebooted dark just before this runner was started, so its launch of the app came straight after that reboot — a walk's runner has failed its launch there before (SimWalk#68), for a cause not yet established")
        #expect(calls.suffix(from: rebooted).contains(["simctl", "ui", "UDID-1", "appearance", "light"]))
        #expect(fixture.store.all().isEmpty)
    }

    /// A runner that never becomes ready on a device no settle rebooted is refused without a settle line: the line says what happened, and nothing did.
    @Test
    func startWhoseRunnerNeverBecomesReadyWithoutASettleNamesNoReboot() throws {
        let fixture = try Fixture(appearance: "dark")

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])
        }

        guard case let .neverReady(_, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }

        #expect(!fixture.script.calls.contains { $0.arguments.starts(with: ["simctl", "shutdown"]) })
        #expect(!lines.contains { $0.hasPrefix("settled:") })
    }

    /// A start whose runner never becomes ready, on a device a second start claims during the ready wait, leaves the device alone (SimWalk#128).
    @Test
    func neverReadyStartLeavesADeviceASecondStartClaimedAlone() throws {
        let fixture = try Fixture(appearance: "dark")
        let secondStart: Int32 = 9999
        fixture.processes.alive.insert(secondStart)
        var plantedAt: Int?
        var claim: LiveSessionClaim?
        fixture.onPause = {
            guard plantedAt == nil else { return }
            plantedAt = fixture.script.calls.count
            claim = try? LiveSessionClaim.take(udid: "UDID-1", in: fixture.store, holder: secondStart, isAlive: fixture.processes.isAlive)
        }

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])
        }

        guard case let .neverReady(_, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }

        #expect(claim != nil)
        #expect(lines.contains { $0.hasPrefix("did not hand UDID-1 back") })
        #expect(try fixture.script.calls.count == #require(plantedAt))
    }

    /// A start whose record cannot be written still hands the device back: its own claim, still held, is not another holder (SimWalk#128).
    @Test
    func neverReadyStartWhoseRecordCannotBeWrittenStillHandsTheDeviceBack() throws {
        let fixture = try Fixture(appearance: "dark")
        fixture.processes.alive.insert(getpid())
        // A directory where the record goes, so writing it fails after the spawn.
        fixture.processes.onSpawn = { _ in
            try? FileManager.default.createDirectory(at: fixture.store.layout(id: "s1").record, withIntermediateDirectories: true)
        }

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", "UDID-1", "--app", "com.example.live", "--state", #"{"theme":"dark"}"#])
        }

        guard case let .neverReady(reason, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }

        #expect(!reason.hasPrefix("no ready.json"))
        #expect(!lines.contains { $0.hasPrefix("did not hand UDID-1 back") })
        #expect(!fixture.script.calls.isEmpty)
    }

    /// `end` puts back the appearance `start` found, whatever the session left the device in.
    @Test
    func endPutsTheFoundAppearanceBack() throws {
        let fixture = try Fixture(appearance: "dark")
        try fixture.session("s1", pid: 11)

        let ended = try SessionEndCommand.parse(["s1"]).perform(store: fixture.store, processes: fixture.processes, shell: Shell(script: fixture.script.run), pause: fixture.pause, now: fixture.now)

        #expect(fixture.script.calls.map(\.arguments).contains(["simctl", "ui", "UDID-1", "appearance", "light"]))
        #expect(ended.verdict == .reporting(qualifications: [], detail: "ended session s1"))
    }

    /// The MCP `session` tool answers `read` and `step` word for word as the CLI does, through the same commands.
    @Test
    func theMCPSessionToolAnswersWhatTheCLIAnswersForReadAndStep() throws {
        let fixture = try Fixture()
        try fixture.session("s1", pid: 77)
        fixture.processes.runner(77)
        let tree = try #require(Self.screen.tree)
        fixture.onPause = {
            let channel = fixture.channel("s1")
            for number in channel.layout.requestNumbers() where (try? channel.response(to: number)) == nil {
                guard let request = try? channel.request(number) else { continue }
                let step = request.action == .step ? LiveSessionStepAnswer.landed(.tap(label: "Steps"), delta: ScreenDelta(from: tree, to: tree)) : nil
                try? channel.respond(LiveSessionResponse(n: number, action: request.action, screen: Self.screen, step: step))
            }
        }
        let serve: ([String: Any]) throws -> Answer = { arguments in
            let invocation = try MCPToolInvocation(tool: "session", arguments: arguments)
            return try MCPToolRunner.sessionAnswer(invocation.argumentVector, store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)
        }

        let servedRead = try serve(["action": "read", "id": "s1", "match": "welcome"])
        let printedRead = try SessionReadCommand.parse(["s1", "--match", "welcome"]).perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)
        let servedStep = try serve(["action": "step", "id": "s1", "step": ["tap": ["label": "Steps"]], "guard": ScreenHash.of(tree)])
        let printedStep = try SessionStepCommand.parse(["s1", #"{"tap":{"label":"Steps"}}"#, "--guard", ScreenHash.of(tree)])
            .perform(store: fixture.store, processes: fixture.processes, pause: fixture.pause, now: fixture.now)

        #expect(servedRead.text == printedRead.text)
        #expect(servedStep.text == printedStep.text)
        #expect(servedStep.residue.first == #"step: {"tap":{"label":"Steps"}}"#)
        #expect(try fixture.channel("s1").request(3)?.guardHash == ScreenHash.of(tree))
    }
}

extension SessionCommandTests {
    static let ready = LiveSessionReady(device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "UDID-1", osVersion: "26.5"), runnerCommit: nil, readyAt: Date(timeIntervalSince1970: 0))

    static let screen = LiveScreen(
        appBundleID: "com.example.live",
        device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "UDID-1", osVersion: "26.5"),
        runnerCommit: "c0ffee0000000000000000000000000000000000",
        readAt: Date(timeIntervalSince1970: 1_790_000_000),
        nonce: "session",
        appState: .foreground,
        tree: AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), label: "Live", children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 40), label: "Welcome to Health"),
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 200, width: 370, height: 40), label: "Steps"),
        ]),
        settled: true,
        screenPixels: LiveScreen.Pixels(width: 1206, height: 2622)
    )

    /// A scratch store, leases and builds; a fake runner; a scripted device; and a clock that moves only when a command pauses.
    final class Fixture {
        let directory: TemporaryDirectory
        let store: LiveSessionStore
        let processes = FakeSessionProcesses()
        let script: WalkCommandTests.WalkScript
        var onPause: () -> Void = {}
        private var elapsed: TimeInterval = 0

        /// `appearance` is the device's as `start` finds it; `failing` names `simctl` subcommands the device refuses.
        init(appearance: String = "light", failing: [String] = []) throws {
            directory = try TemporaryDirectory()
            store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
            script = WalkCommandTests.WalkScript(appPath: directory.url.path, runnerStatus: 0, appearance: appearance, failing: failing)
        }

        var pause: (TimeInterval) -> Void {
            { [self] seconds in
                elapsed += seconds
                onPause()
            }
        }

        var now: () -> Date {
            { [self] in Date(timeIntervalSince1970: elapsed) }
        }

        /// The fixture's own leases, so no test reads or writes the machine's `~/.simwalk/leases`.
        var leases: LeaseStore {
            LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true))
        }

        func channel(_ id: String) -> LiveSessionChannel {
            LiveSessionChannel(layout: store.layout(id: id))
        }

        func session(_ id: String, pid: Int32) throws {
            _ = try store.create(id: id)
            try store.write(LiveSessionRecord(id: id, pid: pid, udid: "UDID-1", app: "com.example.live", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light))
        }

        func start(_ arguments: [String], note: (String) -> Void = { _ in }) throws -> Answer {
            try SessionStartCommand.parse(arguments).perform(
                shell: Shell(script: script.run),
                pause: pause,
                now: now,
                id: { "s1" },
                runner: { RunnerSource(projectPath: "/runner/SimWalkRunner.xcodeproj", commit: "c0ffee", origin: .installed) },
                logFileURL: directory.url.appendingPathComponent("usage.jsonl"),
                builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true)),
                leases: leases,
                store: store,
                processes: processes,
                environment: [:],
                note: note
            )
        }
    }
}
