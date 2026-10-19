//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// `session start` on a physical device (SimWalk#116 S3): routing, the start's order, the token kept out of the runner's command, `bind.json` resent and retried, and the never-ready stop.
struct SessionStartDeviceTests {
    static var udid: String {
        "00008160-00000000000000AA"
    }

    @Test
    func aPhysicalUDIDStartsInOrderAndAnswersOnTheTunnelAddress() throws {
        let fixture = try Fixture()

        let answer = try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"])

        // The spawn is in the same log as the phone's calls, so a `bind.json` sent before it would show here.
        #expect(fixture.phone.summary.prefix(10) == ["find simctl", "simctl list", "list", "list", "lockState", "appearance", "build-for-testing", "spawn", "list", "bind"])
        #expect(fixture.hellos.first?.address == "fd00::1")
        let record = try #require(fixture.store.record(id: "s1"))
        #expect(record.device?.address == "fd00::1")
        #expect(record.device?.leaseTaken == true)
        #expect(record.foundAppearance == .light)
        #expect(answer.verdict == .unqualified("session s1 ready"))
        #expect(answer.residue.contains("device: Test Phone · iPhone 17 · iOS 27.0 · \(Self.udid)"))
        #expect(answer.residue.contains("transport: wired"))
    }

    /// `performOnDevice` passes `note` to the device build: an empty build directory is told as a cold build (SimWalk#98, #118).
    @Test
    func aDeviceStartOverAnEmptyBuildDirectoryTellsTheCallerItIsAColdBuild() throws {
        let fixture = try Fixture()
        var notes: [String] = []

        _ = try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"], note: { notes.append($0) })

        #expect(notes == ["building the runner (c0ffee) — a first build takes several minutes"])
    }

    /// The token is in the session's `token` (0600) and `bind.json` alone: never an argument or variable of the spawned runner.
    @Test
    func theTokenIsNeverInTheSpawnedCommandAndItsFileIs0600() throws {
        let fixture = try Fixture()

        _ = try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"])

        let layout = fixture.store.layout(id: "s1")
        let token = try LiveSessionTokenFile(layout: layout).read()
        let command = try #require(fixture.processes.spawned.first)
        let mode = try #require(FileManager.default.attributesOfItem(atPath: layout.token.path)[.posixPermissions] as? Int)

        #expect(!(command.arguments + Array(command.environment.values) + Array(command.environment.keys)).contains { $0.contains(token.hex) })
        #expect(mode == 0o600)
        #expect(fixture.phone.binds.first?.token == token)
        #expect(command.environment["TEST_RUNNER_SIMWALK_SESSION_DEVICE"] == "s1")
    }

    @Test
    func bindIsRetriedAfterAFailedCopyAndResentWhenTheAddressChanges() throws {
        let fixture = try Fixture()
        fixture.phone.addresses = ["fd00::1", "fd00::1", "fd00::2"]
        fixture.phone.bindFailures = 1
        fixture.refusals = 3

        _ = try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"])

        #expect(fixture.phone.binds.map(\.address) == ["fd00::1", "fd00::2"])
        #expect(fixture.phone.bindAttempts == 3)
        #expect(fixture.store.record(id: "s1")?.device?.address == "fd00::2")
    }

    /// A `--device` lease is the session's holder's — the agent's process — never this start's, which exits once the runner answers.
    @Test
    func aDeviceLeaseIsHeldByTheSessionHolder() throws {
        let fixture = try Fixture()

        _ = try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"])

        let lease = try #require(try fixture.leases.lease(onDevice: Self.udid))

        #expect(lease.holderPID == HolderProcess.sessionHolder())
        #expect(lease.holderPID != getpid())
    }

    @Test
    func aRunnerThatNeverAnswersIsStoppedThroughTheDeviceAndRefusedWithItsDiagnosis() throws {
        let fixture = try Fixture()
        fixture.refusals = .max

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"])
        }

        guard case let .neverReady(reason, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }

        #expect(reason.hasPrefix("no answer to hello within 180 s"))
        #expect(lines.contains("runner container emptied"))
        #expect(lines.contains("released the session's lease on \(Self.udid)"))
        #expect(lines.contains { $0.contains("the runner wrote no result bundle") })
        #expect(fixture.store.all().isEmpty)
        #expect(try fixture.leases.lease(onDevice: Self.udid) == nil)
    }

    @Test
    func teamOnASimulatorIsRefused() throws {
        let fixture = try Fixture()

        #expect(throws: LiveSessionHostError.deviceOnly(flag: "--team")) {
            try fixture.start(["--device", "SIM-1", "--team", "TEAM", "--app", "com.example.live"])
        }
    }

    @Test(arguments: [
        ("locale", #"{"theme":"light","locale":"fr_FR"}"#),
        ("location", #"{"theme":"light","location":{"latitude":1,"longitude":2}}"#),
        ("resetPermissions", #"{"theme":"light","resetPermissions":["camera"]}"#),
    ])
    func aStateKeyADeviceCannotApplyIsRefusedByNameBeforeTheLease(key: String, state: String) throws {
        let fixture = try Fixture()

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live", "--state", state])
        }

        guard case let .unsupportedOnDevice(lines) = error else {
            Issue.record("expected unsupportedOnDevice, got \(error)")
            return
        }

        #expect(lines.count == 1)
        #expect(lines.first?.contains(key) == true)
        #expect(fixture.leases.all().isEmpty)
        // Only the preflight's and the route's own reads: no prerequisite, build or bind reached the phone.
        #expect(fixture.phone.summary == ["find simctl", "simctl list", "list"])
        #expect(fixture.store.all().isEmpty)
    }

    @Test
    func aMissingTeamOnADeviceIsRefusedAndTheLeaseTheStartTookIsReleased() throws {
        let fixture = try Fixture()

        #expect(throws: PhysicalDeviceError.noTeam) {
            try fixture.start(["--device", Self.udid, "--app", "com.example.live"])
        }

        #expect(try fixture.leases.lease(onDevice: Self.udid) == nil)
        #expect(fixture.processes.spawned.isEmpty)
        #expect(fixture.store.all().isEmpty)
    }

    @Test
    func aRunnerBundleIDOnASimulatorIsRefused() throws {
        let fixture = try Fixture()

        #expect(throws: LiveSessionHostError.deviceOnly(flag: "--runner-bundle-id")) {
            try fixture.start(["--device", "SIM-1", "--runner-bundle-id", "com.example.runner", "--app", "com.example.live"])
        }
    }

    @Test
    func aRunnerThatExitsBeforeAnsweringIsStoppedThroughTheDeviceAndRefusedWithItsDiagnosis() throws {
        let fixture = try Fixture()
        fixture.refusals = .max
        fixture.processes.onSpawn = { [processes = fixture.processes] pid in processes.alive.remove(pid) }

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"])
        }

        guard case let .neverReady(reason, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }

        #expect(reason.hasPrefix("xcodebuild (pid 4242) exited before the runner answered hello"))
        #expect(lines.contains("runner container emptied"))
        #expect(lines.contains("released the session's lease on \(Self.udid)"))
        #expect(lines.contains { $0.contains("the runner wrote no result bundle") })
        #expect(fixture.store.all().isEmpty)
        #expect(try fixture.leases.lease(onDevice: Self.udid) == nil)
    }

    /// A presented `--lease` is renewed and used, and is its holder's: neither the never-ready stop nor a failure releases it.
    @Test
    func aPresentedPhysicalLeaseIsRenewedUsedAndNeverReleasedByTheStart() throws {
        let fixture = try Fixture()
        let taken = Date(timeIntervalSince1970: 1_790_000_000)
        let lease = try fixture.leases.acquire(udid: Self.udid, ttl: 60, holderPID: getpid(), now: taken, physicalDevice: true)

        let answer = try fixture.start(["--lease", lease.token, "--team", "TEAM", "--app", "com.example.live"])

        let record = try #require(fixture.store.record(id: "s1"))
        #expect(record.device?.leaseTaken == false)
        #expect(record.device?.leaseToken == lease.token)
        #expect(try #require(fixture.leases.entry(token: lease.token)).lease.expiresAt > taken.addingTimeInterval(60))
        #expect(answer.residue.contains { $0.hasPrefix("lease: presented, renewed") })

        // A start that fails before the spawn leaves it too.
        let failing = try Fixture()
        let other = try failing.leases.acquire(udid: Self.udid, ttl: 60, holderPID: getpid(), now: taken, physicalDevice: true)
        #expect(throws: PhysicalDeviceError.noTeam) {
            try failing.start(["--lease", other.token, "--app", "com.example.live"])
        }
        #expect(failing.leases.entry(token: other.token) != nil)
    }

    @Test
    func aPresentedLeaseSurvivesANeverReadyStop() throws {
        let fixture = try Fixture()
        fixture.refusals = .max
        let lease = try fixture.leases.acquire(udid: Self.udid, ttl: 3600, holderPID: getpid(), now: Date(timeIntervalSince1970: 1_790_000_000), physicalDevice: true)

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--lease", lease.token, "--team", "TEAM", "--app", "com.example.live"])
        }

        guard case let .neverReady(_, lines) = error else {
            Issue.record("expected neverReady, got \(error)")
            return
        }

        #expect(lines.contains("runner container emptied"))
        #expect(!lines.contains { $0.contains("released the session's lease") })
        #expect(fixture.leases.entry(token: lease.token) != nil)
    }

    /// A cancel during the device build — a Ctrl-C, whose signal ends the CLI straight after it — releases the lease the start took at once, before the start's own unwinding (which the signal never lets run), and starts no runner.
    @Test
    func aCancelDuringTheDeviceBuildReleasesTheLeaseAtOnceAndStartsNoRunner() throws {
        let fixture = try Fixture()
        let cancellation = Cancellation()
        var heldBefore = false
        var releasedAtTheCancel = false
        fixture.phone.onBuild = { [leases = fixture.leases] in
            heldBefore = try leases.lease(onDevice: Self.udid) != nil
            cancellation.cancel()
            releasedAtTheCancel = try leases.lease(onDevice: Self.udid) == nil
        }

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"], cancellation: cancellation)
        }

        #expect(heldBefore)
        #expect(releasedAtTheCancel)
        #expect("\(error)".contains("cancelled before its runner was started"))
        #expect(fixture.processes.spawned.isEmpty)
        #expect(!fixture.phone.summary.contains("bind"))
        #expect(fixture.store.all().isEmpty)
        #expect(try fixture.leases.lease(onDevice: Self.udid) == nil)
    }

    /// `bind.json` (it holds the token) is written inside the session's directory, which the stop removes on every path — never `$TMPDIR`, where a start killed while a copy retries would leave it.
    @Test
    func bindJSONIsWrittenInsideTheSessionDirectoryAndRemovedOnceCopied() throws {
        let fixture = try Fixture()

        _ = try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"])

        let directory = fixture.store.layout(id: "s1").directory.path
        let sources = fixture.phone.bindSources

        #expect(!sources.isEmpty)
        #expect(sources.allSatisfy { $0.hasPrefix(directory + "/") })
        #expect(!sources.contains { FileManager.default.fileExists(atPath: $0) })
    }

    /// A cancel while the runner starts — after the spawn, past the pre-spawn release — ends the wait for `hello` and runs the device stop, rather than answering ready to a caller that has gone (SimWalk#127).
    @Test
    func aCancelDuringTheHelloWaitRunsTheDeviceStopAndIsRefusedAsCancelled() throws {
        let fixture = try Fixture()
        let cancellation = Cancellation()
        // Another process on the Mac, which no stop of this session may signal.
        fixture.processes.runner(5151)
        fixture.refusals = 1
        fixture.onHello = { cancellation.cancel() }

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"], cancellation: cancellation)
        }

        guard case let .startCancelled(udid, lines) = error else {
            Issue.record("expected startCancelled, got \(error)")
            return
        }

        #expect(udid == Self.udid)
        #expect(fixture.hellos.count == 1)
        #expect(lines.contains("runner container emptied"))
        #expect(lines.contains("released the session's lease on \(Self.udid)"))
        #expect(!fixture.processes.signalled.isEmpty)
        #expect(fixture.processes.signalled.allSatisfy { $0.group == 4242 })
        #expect(fixture.processes.isAlive(5151))
        #expect(fixture.store.all().isEmpty)
        #expect(try fixture.leases.lease(onDevice: Self.udid) == nil)
    }

    /// A cancel landing after the last check before the renewal releases the lease under it: the start answers the cancel, not a lease that could not be renewed (SimWalk#127).
    @Test
    func aCancelAtTheLeaseRenewalIsRefusedAsCancelled() throws {
        let fixture = try Fixture()
        let cancellation = Cancellation()
        var built = false
        fixture.phone.onBuild = { built = true }
        // The first clock read after the build is the renewal's.
        fixture.onNow = {
            if built {
                built = false
                cancellation.cancel()
            }
        }

        let error = try #require(throws: LiveSessionHostError.self) {
            try fixture.start(["--device", Self.udid, "--team", "TEAM", "--app", "com.example.live"], cancellation: cancellation)
        }

        #expect(error == .startCancelled(udid: Self.udid))
        #expect(fixture.processes.spawned.isEmpty)
        #expect(fixture.store.all().isEmpty)
        #expect(try fixture.leases.lease(onDevice: Self.udid) == nil)
    }
}

extension SessionStartDeviceTests {
    /// A scripted phone and simulator list, a fake runner process, scratch stores, and a `hello` that is refused `refusals` times and then answers.
    final class Fixture {
        let directory: TemporaryDirectory
        let store: LiveSessionStore
        let leases: LeaseStore
        let processes = FakeSessionProcesses()
        let phone = Phone()
        var refusals = 0
        /// Runs as each `hello` is sent, before it is answered or refused.
        var onHello: () -> Void = {}
        /// Runs as each clock read is made.
        var onNow: () -> Void = {}
        private(set) var hellos: [DeviceSessionBind] = []
        private var elapsed: TimeInterval = 0

        init() throws {
            directory = try TemporaryDirectory()
            store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
            leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in true }
            processes.onSpawn = { [phone] _ in phone.calls.append(["spawn"]) }
        }

        func start(_ arguments: [String], cancellation: Cancellation? = nil, animationsLibrary: WalkCommand.AnimationsLibrary? = nil, note: (String) -> Void = { _ in }) throws -> Answer {
            try SessionStartCommand.parse(arguments).perform(
                shell: phone.shell,
                pause: { [self] in elapsed += $0 },
                now: { [self] in
                    onNow()
                    return Date(timeIntervalSince1970: 1_790_000_000 + elapsed)
                },
                id: { "s1" },
                runner: { RunnerSource(projectPath: "/runner/SimWalkRunner.xcodeproj", commit: "c0ffee", origin: .installed) },
                logFileURL: directory.url.appendingPathComponent("usage.jsonl"),
                builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true)),
                leases: leases,
                store: store,
                processes: processes,
                environment: [:],
                cancellation: cancellation,
                deviceHello: { [self] bind in
                    hellos.append(bind)
                    onHello()
                    guard refusals <= 0 else {
                        refusals -= 1
                        throw DeviceSessionClientError.refused
                    }
                    return LiveSessionReady(device: CaptureManifest.Device(name: "Test Phone", udid: SessionStartDeviceTests.udid, osVersion: "27.0"), runnerCommit: "c0ffee", readyAt: Date())
                },
                animationsLibrary: animationsLibrary,
                note: note
            )
        }
    }

    /// Answers `simctl list`, `devicectl` and `xcodebuild`; `addresses` are the tunnel's on successive reads (the last repeats).
    ///
    /// `calls` is shared with the fixture's runner, whose spawn it logs as `["spawn"]`.
    final class Phone {
        var calls: [[String]] = []
        /// Runs as the device build is asked for.
        var onBuild: () throws -> Void = {}
        /// Where each `bind.json` copy was sent from.
        private(set) var bindSources: [String] = []
        var addresses = ["fd00::1"]
        var bindFailures = 0
        private(set) var bindAttempts = 0
        private(set) var binds: [DeviceSessionBind] = []

        var shell: Shell {
            Shell(script: { [self] _, arguments, _ in
                calls.append(arguments)
                func ok(_ out: String = "") -> Shell.Result {
                    Shell.Result(status: 0, standardOutput: out, standardError: "")
                }
                if arguments.first == "simctl" {
                    return ok(#"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"udid":"SIM-1","name":"iPhone 17 Pro","state":"Booted"}]}}"#)
                }
                if arguments.starts(with: ["devicectl", "list", "devices"]) {
                    let address = addresses.count > 1 && calls.filter { $0.starts(with: ["devicectl", "list"]) }.count > 3 ? addresses.removeFirst() : addresses[0]
                    return ok(Self.list(address: address))
                }
                if arguments.contains("build-for-testing") {
                    try onBuild()
                }
                if arguments.contains("lockState") {
                    return ok(#"{"result":{"passcodeRequired":false}}"#)
                }
                if arguments.contains("appearance") {
                    return ok(#"{"result":{"userInterfaceStyle":"light","textSize":"Large","increaseContrast":false}}"#)
                }
                if arguments.starts(with: ["devicectl", "device", "copy", "to"]), arguments.contains("Documents/SimWalkSession/bind.json") {
                    bindAttempts += 1
                    if bindFailures > 0 {
                        bindFailures -= 1
                        return Shell.Result(status: 1, standardOutput: "", standardError: "container not found")
                    }
                    let source = try #require(arguments.firstIndex(of: "--source").map { arguments[$0 + 1] })
                    bindSources.append(source)
                    try binds.append(JSONDecoder().decode(DeviceSessionBind.self, from: Data(contentsOf: URL(fileURLWithPath: source))))
                    return ok()
                }
                if arguments.starts(with: ["devicectl", "device", "copy", "from"]) {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "no exit.json")
                }
                return ok()
            })
        }

        /// Each call reduced to what names it.
        var summary: [String] {
            calls.map { arguments in
                if arguments == ["spawn"] {
                    return "spawn"
                }
                if arguments == ["--find", "simctl"] {
                    return "find simctl"
                }
                if arguments.first == "simctl" {
                    return "simctl list"
                }
                if arguments.contains("build-for-testing") {
                    return "build-for-testing"
                }
                if arguments.contains("Documents/SimWalkSession/bind.json") {
                    return "bind"
                }
                return arguments.filter { ["list", "lockState", "appearance"].contains($0) }.joined(separator: " ")
            }
        }

        static func list(address: String) -> String {
            """
            {"result":{"devices":[{"properties":{
              "hardware":{"reality":"physical","udid":"\(SessionStartDeviceTests.udid)","marketingName":"iPhone 17","productType":"iPhone18,1"},
              "connection":{"transportType":"wired","pairingState":"paired","state":"connected","tunnelIPAddressString":"\(address)"},
              "state":{"name":"Test Phone","developerModeStatus":{"enabled":"enabled"}},
              "software":{"osVersionNumber":{"stringValue":"27.0"}}}}]}}
            """
        }
    }
}
