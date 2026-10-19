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

/// `session read`, `step`, `save` and `list` on a physical device's record (SimWalk#116 S4): one exchange per command through the token-authenticated socket, filed under the runner's number, the session's lease renewed before every request.
struct SessionDeviceExchangeTests {
    /// A read sends nothing to a file channel: the runner's response is filed under its own number and the answer is a simulator read's.
    @Test
    func aReadFilesTheExchangeUnderTheRunnersNumberAndAnswersAsASimulatorDoes() throws {
        let fixture = try Fixture()

        let answer = try fixture.read(["s1", "--match", "welcome"])

        let inspected = try InspectCommand.outcome(runnerFailure: nil, handback: nil, readingScreen: { SessionCommandTests.screen }, match: "welcome")
        let channel = fixture.channel

        #expect(answer == inspected)
        #expect(try channel.request(1)?.action == .read)
        #expect(try channel.response(to: 1)?.screen == SessionCommandTests.screen)
        #expect(fixture.sentTokens == [Fixture.token])
    }

    /// Two reads are numbered by the runner 1 and 2, and both are filed.
    @Test
    func twoReadsAreNumberedOneAndTwo() throws {
        let fixture = try Fixture()

        _ = try fixture.read(["s1"])
        _ = try fixture.read(["s1"])

        #expect(fixture.channel.layout.requestNumbers() == [1, 2])
        #expect(try fixture.channel.response(to: 2)?.n == 2)
    }

    /// A guarded step is sent with its step and guard, answered as a simulator's step is, and its landed step is in the route.
    @Test
    func aGuardedStepIsFiledAndItsLandedStepIsInTheRoute() throws {
        let fixture = try Fixture()

        let answer = try SessionStepCommand.parse(["s1", #"{"tap":{"label":"Steps"}}"#, "--guard", "1a2b3c4d"])
            .perform(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, deviceSend: fixture.send, pause: { _ in }, now: fixture.now)

        #expect(fixture.requests.first?.guardHash == "1a2b3c4d")
        #expect(try fixture.channel.request(1)?.step == .tap(label: "Steps"))
        #expect(try fixture.channel.route() == [.tap(label: "Steps")])
        #expect(answer.text.contains("tap"))
    }

    /// The lease is renewed before the request is sent: at the send, its expiry is already a full TTL from the command's clock.
    @Test
    func theLeaseIsRenewedBeforeTheRequestIsSent() throws {
        let fixture = try Fixture()

        _ = try fixture.read(["s1"])

        let expiry = try #require(fixture.expiryAtSend)

        #expect(expiry == fixture.now().addingTimeInterval(WalkLease.ttl))
    }

    /// A lease that cannot be renewed refuses before anything is sent, naming the session and the device.
    @Test
    func aFailedRenewalSendsNothing() throws {
        let fixture = try Fixture(commandClock: 7200)

        let error = try #require(throws: LiveSessionHostError.self) { try fixture.read(["s1"]) }

        guard case let .deviceLeaseNotRenewed(id, udid, _) = error else {
            Issue.record("expected deviceLeaseNotRenewed, got \(error)")
            return
        }

        #expect(id == "s1")
        #expect(udid == Fixture.udid)
        #expect(fixture.requests.isEmpty)
        #expect(fixture.channel.layout.requestNumbers().isEmpty)
    }

    /// A record with no address yet is refused as not ready, before the lease is touched or anything is sent.
    @Test
    func aRecordWithNoAddressIsNotReady() throws {
        let fixture = try Fixture(address: "")

        let error = try #require(throws: LiveSessionHostError.self) { try fixture.read(["s1"]) }

        #expect(error == .deviceNotReady(id: "s1"))
        #expect(fixture.requests.isEmpty)
    }

    /// A refused connect through the real client names the address, and one devicectl read names a changed address beside it with the way out.
    @Test
    func aRefusedConnectIsDiagnosedWithBothAddresses() throws {
        let fixture = try Fixture(tunnelAddress: "fd99::1")

        let error = try #require(throws: LiveSessionDeviceError.self) {
            try SessionReadCommand.parse(["s1"]).perform(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)
        }

        let text = "\(error)"

        #expect(text.contains("[::1]:1 on \(Fixture.udid)"))
        #expect(text.contains("the tunnel came back at fd99::1; the runner listens on ::1: end the session and start again"))
        #expect(fixture.listReads == 1)
        #expect(fixture.channel.layout.requestNumbers().isEmpty)
    }

    /// An unchanged address names the tunnel's state instead.
    @Test
    func aRefusedConnectOnAnUnchangedAddressNamesTheState() throws {
        let fixture = try Fixture(tunnelAddress: "::1")

        let error = try #require(throws: LiveSessionDeviceError.self) {
            try SessionReadCommand.parse(["s1"]).perform(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)
        }

        #expect("\(error)".contains("the tunnel is still at ::1"))
    }

    /// Save works from the filed exchanges with no device call, and refuses a numbering gap naming the number.
    @Test
    func saveRefusesAGapAndSavesWithoutACall() throws {
        let fixture = try Fixture()
        _ = try fixture.step(#"{"tap":{"label":"Steps"}}"#)
        fixture.number = 2
        _ = try fixture.step(#"{"tap":{"label":"Steps"}}"#)
        try FileManager.default.removeItem(at: fixture.channel.layout.request(1))
        let into = fixture.directory.url.appendingPathComponent("walkbook.json").path
        let sent = fixture.requests.count

        let error = try #require(throws: LiveSessionSaveError.self) {
            try SessionSaveCommand.parse(["s1", "--screen", "steps", "--into", into]).perform(store: fixture.store, leases: fixture.leases, now: fixture.now)
        }

        #expect(error == .unfiledRequests([1]))
        #expect("\(error)".contains("request 1 was answered"))
        #expect(fixture.requests.count == sent)
        #expect(fixture.shellCalls.isEmpty)
    }

    /// List shows a device record as a device, running by its pid, and never calls `simctl`.
    @Test
    func listShowsADeviceRecordAndNeverCallsSimctl() throws {
        let fixture = try Fixture()
        fixture.processes.runner(77)

        let answer = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)

        #expect(answer.residue == ["s1 · com.example.live · \(Fixture.udid) · device · running (pid 77)"])
        #expect(fixture.shellCalls.isEmpty)
    }

    /// List reads every session on the machine and renews none, so one agent's listing never keeps another's lease alive (Brief, ruling 8).
    @Test
    func listRenewsNoLease() throws {
        let fixture = try Fixture()
        let before = fixture.leases.entry(token: Fixture.leaseToken)?.lease.expiresAt

        _ = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)

        #expect(before != nil)
        #expect(fixture.leases.entry(token: Fixture.leaseToken)?.lease.expiresAt == before)
    }

    /// A lapsed lease is not list's to report: it renews nothing, so the running session is one line.
    @Test
    func listSaysNothingOfALapsedLease() throws {
        let fixture = try Fixture(commandClock: 7200)

        let answer = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)

        #expect(answer.residue == ["s1 · com.example.live · \(Fixture.udid) · device · running (pid 77)"])
    }

    /// Save renews a device session's lease before it saves.
    @Test
    func saveRenewsTheLease() throws {
        let fixture = try Fixture()
        _ = try fixture.step(#"{"tap":{"label":"Steps"}}"#)
        let into = fixture.directory.url.appendingPathComponent("walkbook.json").path
        let later = fixture.start.addingTimeInterval(500)

        _ = try SessionSaveCommand.parse(["s1", "--screen", "steps", "--into", into]).perform(store: fixture.store, leases: fixture.leases, now: { later })

        #expect(fixture.leases.entry(token: Fixture.leaseToken)?.lease.expiresAt == later.addingTimeInterval(WalkLease.ttl))
    }

    /// Save refuses as `read` does when the lease cannot be renewed, and writes nothing.
    @Test
    func saveRefusesWhenTheLeaseCannotBeRenewed() throws {
        let fixture = try Fixture(commandClock: 7200)
        let into = fixture.directory.url.appendingPathComponent("walkbook.json").path

        let error = try #require(throws: LiveSessionHostError.self) {
            try SessionSaveCommand.parse(["s1", "--screen", "steps", "--into", into]).perform(store: fixture.store, leases: fixture.leases, now: fixture.now)
        }

        guard case .deviceLeaseNotRenewed = error else {
            Issue.record("expected deviceLeaseNotRenewed, got \(error)")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: into))
    }

    /// A stopped device runner is listed as exited, still without a call to `simctl`: a device has no accessibility to hand back.
    @Test
    func listOfAnExitedDeviceRecordMakesNoAccessibilityRestore() throws {
        let fixture = try Fixture()
        fixture.processes.alive = []

        let answer = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: LeaseStore(directory: fixture.directory.url.appendingPathComponent("none", isDirectory: true)), shell: fixture.shell, pause: { _ in }, now: fixture.now)

        #expect(answer.residue.count == 1)
        #expect(answer.residue.first?.contains("device · exited") == true)
        #expect(!fixture.shellCalls.contains { $0.first == "simctl" })
    }

    /// A runner that ended itself after its idle timeout: `read` answers with the runner's own reason, copied back from the phone, and `list` and `end` give the same summary.
    @Test
    func anIdleExitGivesReadAndListTheRunnersOwnReason() throws {
        let fixture = try Fixture(exitOnPhone: .idle(after: 600, served: 3, stoppedAt: Date(timeIntervalSince1970: 1000)))
        fixture.processes.alive = []

        let error = try #require(throws: LiveSessionHostError.self) { try fixture.read(["s1"]) }
        let answer = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)
        let summary = try #require(fixture.exitOnPhone).summary

        #expect(error == .deviceRunnerStopped(id: "s1", exit: fixture.exitOnPhone))
        #expect("\(error)".contains(summary))
        #expect(summary.contains("no request for"))
        #expect(answer.residue.first?.contains("exited: \(summary)") == true)
        #expect(fixture.requests.isEmpty)
    }

    /// A record left in the container by an earlier session is not this one's reason: `read` falls through to the no-record answer and nothing is kept in the session directory (SimWalk#116).
    @Test
    func anotherRunsExitRecordIsNotThisSessionsReason() throws {
        let fixture = try Fixture(exitOnPhone: .idle(after: 600, served: 3, stoppedAt: Date(timeIntervalSince1970: 1000)), exitSession: "s0")
        fixture.processes.alive = []

        let error = try #require(throws: LiveSessionHostError.self) { try fixture.read(["s1"]) }

        #expect(error == .deviceRunnerStopped(id: "s1", exit: nil))
        #expect(!FileManager.default.fileExists(atPath: fixture.channel.layout.exit.path))
    }

    /// A connect refused while the process is still alive is the runner on its way out: the record is copied back and is the refusal, not the tunnel's state.
    @Test
    func aRefusedConnectIsAnsweredFromTheCopiedExitRecord() throws {
        let fixture = try Fixture(exitOnPhone: .idle(after: 600, served: 3, stoppedAt: Date(timeIntervalSince1970: 1000)))

        let error = try #require(throws: LiveSessionHostError.self) {
            try SessionReadCommand.parse(["s1"]).perform(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)
        }

        #expect(error == .deviceRunnerStopped(id: "s1", exit: fixture.exitOnPhone))
        #expect(fixture.listReads == 0)
    }

    /// A runner that exited because the phone locked left only `kAXErrorServerNotFound`: the stopped-runner refusal reads `lockState` once and says the phone is locked, as a failed read or step does.
    @Test
    func aStoppedRunnerOnALockedPhoneSaysSo() throws {
        let fixture = try Fixture(exitOnPhone: .idle(after: 600, served: 3, stoppedAt: Date(timeIntervalSince1970: 1000)), passcodeRequired: true)
        fixture.processes.alive = []

        let error = try #require(throws: LiveSessionHostError.self) { try fixture.read(["s1"]) }

        #expect(error == .deviceRunnerStopped(id: "s1", exit: fixture.exitOnPhone, lockNote: "the phone is locked: unlock it — on Wi-Fi a lock usually ends the session, so `simwalk session end s1` and start again"))
        #expect("\(error)".contains("\nthe phone is locked: unlock it"))
    }

    /// A refused connect with the phone locked adds the one line: the phone is locked, unlock it, and a lock usually ends the session on Wi-Fi.
    @Test
    func aRefusedConnectOnALockedPhoneSaysSo() throws {
        let fixture = try Fixture(passcodeRequired: true)

        let error = try #require(throws: LiveSessionDeviceError.self) {
            try SessionReadCommand.parse(["s1"]).perform(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)
        }

        #expect("\(error)".contains("the phone is locked: unlock it"))
        #expect("\(error)".contains("`simwalk session end s1` and start again"))
        #expect(fixture.lockReads == 1)
    }

    /// An unlocked phone leaves the refusal as it was, after exactly one lockState read; so does a read that fails.
    @Test(arguments: [false, nil] as [Bool?])
    func anUnlockedOrUnreadablePhoneLeavesTheRefusalUnchanged(passcodeRequired: Bool?) throws {
        let fixture = try Fixture(passcodeRequired: passcodeRequired)

        let error = try #require(throws: LiveSessionDeviceError.self) {
            try SessionReadCommand.parse(["s1"]).perform(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)
        }

        #expect(!"\(error)".contains("locked"))
        #expect(error.lockNote == nil)
        #expect(fixture.lockReads == 1)
    }

    /// The runner's own error answer (XCTest's `kAXErrorServerNotFound` on a locked phone) gets the line too, on `read` and on `step`.
    @Test
    func aRunnersErrorAnswerOnALockedPhoneSaysSo() throws {
        let fixture = try Fixture(passcodeRequired: true, runnerFailure: "Error getting main window kAXErrorServerNotFound")

        let read = try #require(throws: LiveSessionHostError.self) { try fixture.read(["s1"]) }
        let step = try #require(throws: LiveSessionHostError.self) { try fixture.step(#"{"tap":{"label":"Steps"}}"#) }

        #expect("\(read)".contains("kAXErrorServerNotFound\nthe phone is locked: unlock it"))
        #expect("\(step)".contains("the phone is locked: unlock it"))
        #expect(fixture.lockReads == 2)
    }

    /// A read that succeeds reads no lockState.
    @Test
    func aSuccessfulReadMakesNoLockStateCall() throws {
        let fixture = try Fixture(passcodeRequired: true)

        _ = try fixture.read(["s1"])

        #expect(fixture.lockReads == 0)
    }

    /// The copy happens once: a second `read` answers from `exit.json` in the session directory.
    @Test
    func aSecondReadDoesNotCopyAgain() throws {
        let fixture = try Fixture(exitOnPhone: .idle(after: 600, served: 3, stoppedAt: Date(timeIntervalSince1970: 1000)))
        fixture.processes.alive = []

        _ = try? fixture.read(["s1"])
        let second = try #require(throws: LiveSessionHostError.self) { try fixture.read(["s1"]) }
        _ = SessionListCommand.answer(store: fixture.store, processes: fixture.processes, leases: fixture.leases, shell: fixture.shell, pause: { _ in }, now: fixture.now)

        #expect(fixture.copies == 1)
        #expect(second == .deviceRunnerStopped(id: "s1", exit: fixture.exitOnPhone))
    }
}

extension SessionDeviceExchangeTests {
    final class Fixture {
        static var udid: String {
            "PHONE"
        }

        static var leaseToken: String {
            "LEASE-1"
        }

        static let token = DeviceSessionToken(hex: String(repeating: "ab", count: 32))
        let directory: TemporaryDirectory
        let store: LiveSessionStore
        let leases: LeaseStore
        let processes = FakeSessionProcesses()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let commandClock: TimeInterval
        let tunnelAddress: String
        /// The runner's serving count: the next request is numbered `number`.
        var number = 1
        private(set) var requests: [DeviceSessionRequest] = []
        private(set) var sentTokens: [DeviceSessionToken] = []
        private(set) var expiryAtSend: Date?
        private(set) var listReads = 0
        private(set) var shellCalls: [[String]] = []
        /// The exit record the phone's container holds; `nil` when the runner left none.
        let exitOnPhone: LiveSessionExit?
        /// The session id the phone's record is stamped with: this session's, as its runner writes it, unless a test leaves another run's.
        let exitSession: String?
        private(set) var copies = 0
        /// What `devicectl device info lockState` reports; `nil` when the read fails.
        let passcodeRequired: Bool?
        /// A failure the runner answers every request with, instead of serving it.
        let runnerFailure: String?
        private(set) var lockReads = 0

        init(address: String = "::1", commandClock: TimeInterval = 10, tunnelAddress: String = "::1", exitOnPhone: LiveSessionExit? = nil, exitSession: String? = "s1", passcodeRequired: Bool? = false, runnerFailure: String? = nil) throws {
            self.exitSession = exitSession
            self.exitOnPhone = exitOnPhone.map { LiveSessionExit(reason: $0.reason, detail: $0.detail, served: $0.served, stoppedAt: $0.stoppedAt, session: exitSession) }
            self.passcodeRequired = passcodeRequired
            self.runnerFailure = runnerFailure
            processes.runner(77)
            directory = try TemporaryDirectory()
            self.commandClock = commandClock
            self.tunnelAddress = tunnelAddress
            store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
            leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in true }
            _ = try leases.acquire(udid: Self.udid, ttl: 60, holderPID: 1, now: start, physicalDevice: true, token: Self.leaseToken)
            let layout = try store.create(id: "s1")
            try LiveSessionTokenFile(layout: layout).write(#require(Self.token))
            try LiveSessionChannel(layout: layout).writeLaunch(LiveSessionLaunch(appBundleID: "com.example.live", state: nil))
            let endpoint = LiveSessionRecord.DeviceEndpoint(address: address, port: 1, team: "TEAM", runnerBundleID: nil, leaseToken: Self.leaseToken, leaseTaken: true, appearance: nil)
            try store.write(LiveSessionRecord(id: "s1", pid: 77, udid: Self.udid, app: "com.example.live", startedAt: start, foundAppearance: .light, device: endpoint))
        }

        var channel: LiveSessionChannel {
            LiveSessionChannel(layout: store.layout(id: "s1"))
        }

        var now: () -> Date {
            { [self] in start.addingTimeInterval(commandClock) }
        }

        /// The stand-in for the runner's socket: serves the request as number `number`, then counts it.
        var send: LiveSessionDeviceExchange.Send {
            { [self] token, request, _ in
                sentTokens.append(token)
                requests.append(request)
                expiryAtSend = leases.entry(token: Self.leaseToken)?.lease.expiresAt
                defer { number += 1 }
                if let runnerFailure {
                    return LiveSessionResponse(n: number, action: request.action, failure: runnerFailure)
                }
                switch request.action {
                case .step:
                    let tree = try #require(SessionCommandTests.screen.tree)
                    return try LiveSessionResponse(n: number, action: .step, screen: SessionCommandTests.screen, step: .landed(#require(request.step), delta: ScreenDelta(from: tree, to: tree)))
                default:
                    return LiveSessionResponse(n: number, action: request.action, screen: SessionCommandTests.screen)
                }
            }
        }

        var shell: Shell {
            Shell { [self] _, arguments, _ in
                shellCalls.append(arguments)
                if arguments.starts(with: ["devicectl", "device", "copy", "from"]) {
                    copies += 1
                    guard let exitOnPhone, let destination = arguments.firstIndex(of: "--destination").map({ arguments[$0 + 1] }) else {
                        return Shell.Result(status: 1, standardOutput: "", standardError: "ERROR: The file couldn't be found.")
                    }
                    try LiveSessionChannel(layout: LiveSessionLayout(directory: URL(fileURLWithPath: destination).deletingLastPathComponent())).markExit(exitOnPhone)
                    return Shell.Result(status: 0, standardOutput: "", standardError: "")
                }
                if arguments.starts(with: ["devicectl", "device", "info", "lockState"]) {
                    lockReads += 1
                    guard let passcodeRequired else { return Shell.Result(status: 1, standardOutput: "", standardError: "ERROR: no route to host") }
                    return Shell.Result(status: 0, standardOutput: #"{"result":{"passcodeRequired":\#(passcodeRequired)}}"#, standardError: "")
                }
                guard arguments.starts(with: ["devicectl", "list", "devices"]) else {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "unexpected")
                }
                listReads += 1
                let listing = #"{"result":{"devices":[{"connectionProperties":{"tunnelState":"connected","tunnelIPAddress":"\#(tunnelAddress)"},"properties":{"hardware":{"udid":"\#(Self.udid)"},"connection":{}}}]}}"#
                return Shell.Result(status: 0, standardOutput: listing, standardError: "")
            }
        }

        func read(_ arguments: [String]) throws -> Answer {
            try SessionReadCommand.parse(arguments).perform(store: store, processes: processes, leases: leases, shell: shell, deviceSend: send, pause: { _ in }, now: now)
        }

        func step(_ json: String) throws -> Answer {
            try SessionStepCommand.parse(["s1", json]).perform(store: store, processes: processes, leases: leases, shell: shell, deviceSend: send, pause: { _ in }, now: now)
        }
    }
}
