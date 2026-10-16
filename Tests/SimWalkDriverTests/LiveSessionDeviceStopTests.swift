//
// Copyright © Agulhas Labs
//

import Darwin
import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A device session's end, against a fake runner process, a scripted `devicectl` and a stand-in for the runner's socket: every step in order, the lease only the session took, the wipe aimed at the runner's container alone, and the process guards the simulator's stop has.
struct LiveSessionDeviceStopTests {
    /// A live, ready runner: `end` is sent and filed under the runner's number, it exits, and then exit.json comes back, the appearance is handed back, the container emptied, the lease released and the directory removed — in that order.
    @Test
    func endOnALiveRunnerRunsEveryStepInOrder() throws {
        let fixture = try Fixture(leaseTaken: true)

        let report = try fixture.stop()

        #expect(fixture.events == ["end", "copy from", "appearance", "wipe"])
        #expect(fixture.filedBeforeCopy)
        #expect(fixture.processes.signalled.isEmpty)
        #expect(try fixture.leases.lease(onDevice: Fixture.udid) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
        #expect(report.exit?.reason == .ended)
        #expect(report.qualifications.isEmpty)
        try Self.expectInOrder(report.lines, [
            "sent end (request 1); the runner answered",
            "the runner (pid 4242) exited",
            "copied exit.json back from the runner's container",
            "runner: ",
            "appearance handed back: light (read back)",
            "runner container emptied",
            "released the session's lease on \(Fixture.udid)",
            "removed ",
        ])
    }

    /// A presented `--lease` is its holder's: `end` keeps it, and says so.
    @Test
    func aPresentedLeaseIsKept() throws {
        let fixture = try Fixture(leaseTaken: false)

        let report = try fixture.stop()

        #expect(try fixture.leases.lease(onDevice: Fixture.udid)?.token == Fixture.leaseToken)
        #expect(report.lines.contains("kept the presented lease on \(Fixture.udid): it is its holder's to release"))
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// The wipe clears a whole container, so it is aimed at the runner's own (`<runner bundle id>.xctrunner`), and so is every other container call.
    @Test
    func theWipeIsAimedOnlyAtTheRunnersContainer() throws {
        let fixture = try Fixture(leaseTaken: true)

        _ = try fixture.stop()

        let domains = fixture.calls.compactMap { call in call.firstIndex(of: "--domain-identifier").map { call[$0 + 1] } }
        let wipe = fixture.calls.first { $0.contains("--remove-existing-content") }

        #expect(wipe.flatMap { call in call.firstIndex(of: "--domain-identifier").map { call[$0 + 1] } } == "com.example.runner.xctrunner")
        #expect(domains == ["com.example.runner.xctrunner", "com.example.runner.xctrunner"])
    }

    /// A refused connect — through the real client, to an address nothing listens on — reads the tunnel once and names the address it came back at beside the one the runner listened on; the runner is still waited on, and the phone still handed back, emptied and released.
    @Test
    func aRefusedConnectReadsTheTunnelOnceAndNamesAChangedAddress() throws {
        let fixture = try Fixture(leaseTaken: true, address: "::1", port: 1)
        fixture.tunnelAddress = "fd99::1"
        fixture.exitsOnPause = true

        let report = try fixture.stop(realClient: true)

        let sent = report.lines.first { $0.hasPrefix("sent end: ") } ?? ""

        #expect(fixture.events == ["list devices", "copy from", "appearance", "wipe"])
        #expect(sent.contains("refused"))
        #expect(sent.contains("[::1]:1 on \(Fixture.udid)"))
        #expect(sent.hasSuffix("the tunnel came back at fd99::1; the runner listens on ::1: end the session and start again"))
        #expect(fixture.processes.signalled.isEmpty)
        #expect(try fixture.leases.lease(onDevice: Fixture.udid) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// A runner that answers `end` and will not exit is signalled — it passes every guard — and, still running, keeps its directory, its lease and the container it is running in.
    @Test
    func aRunnerThatWillNotExitIsSignalledAndKeptWithItsLease() throws {
        let fixture = try Fixture(leaseTaken: true)
        fixture.endStopsTheRunner = false
        fixture.processes.diesOnSignal = false

        let report = try fixture.stop()

        #expect(fixture.processes.signalled.map(\.group) == [Fixture.pid])
        #expect(fixture.processes.signalled.map(\.signal) == [SIGTERM])
        #expect(report.stillRunning)
        #expect(report.qualifications.contains("the runner is still running"))
        #expect(FileManager.default.fileExists(atPath: fixture.layout.directory.path))
        #expect(try fixture.leases.lease(onDevice: Fixture.udid) != nil)
        #expect(fixture.events == ["end", "copy from", "appearance"])
        #expect(!fixture.calls.contains { $0.contains("--remove-existing-content") })
        #expect(report.lines.contains("runner container left: the runner is still running in it — `end` empties it once it has stopped"))
    }

    /// A pid that is not `xcodebuild` is a stranger holding a reused number: never asked to end, never signalled; the phone is still handed back and the session removed.
    @Test
    func aStrangerPidIsNeverSignalledNorAskedToEnd() throws {
        let fixture = try Fixture(leaseTaken: true)
        fixture.processes.runner(Fixture.pid, name: "Safari")

        let report = try fixture.stop()

        #expect(fixture.processes.signalled.isEmpty)
        #expect(fixture.events == ["copy from", "appearance", "wipe"])
        #expect(report.lines.first?.hasPrefix("pid 4242 is running and was left alone: it is Safari, not xcodebuild") == true)
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// A runner that never answered `hello` — `session start`'s never-ready path — is not sent `end`; it is waited on and signalled, and every later step still runs.
    @Test
    func aRunnerThatNeverBecameReadyIsNotSentEnd() throws {
        let fixture = try Fixture(leaseTaken: true, ready: false)

        let report = try fixture.stop()

        #expect(fixture.events == ["copy from", "appearance", "wipe"])
        #expect(report.lines.first == "end not sent: the runner never answered hello, so it may never have listened")
        #expect(fixture.processes.signalled.map(\.group) == [Fixture.pid])
        #expect(report.lines.contains { $0.hasPrefix("pid 4242 was still running 10 s after the stop began (end was not sent): sent SIGTERM") })
        #expect(try fixture.leases.lease(onDevice: Fixture.udid) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// An exit record missing from the phone is a line, not a failure; the end goes on.
    @Test
    func aMissingExitRecordIsALine() throws {
        let fixture = try Fixture(leaseTaken: true)
        fixture.exitOnPhone = false

        let report = try fixture.stop()

        #expect(report.exit == nil)
        #expect(report.lines.contains { $0.hasPrefix("exit.json not copied back from the runner's container: ") })
        #expect(report.qualifications.isEmpty)
        #expect(fixture.events == ["end", "copy from", "appearance", "wipe"])
    }

    /// A record in the container stamped with an earlier session's id is not this session's: it is not copied in, the step says so, and the answer is the no-record one.
    @Test
    func anotherRunsExitRecordIsIgnored() throws {
        let fixture = try Fixture(leaseTaken: true)
        fixture.exitSession = "s0"

        let report = try fixture.stop()

        #expect(report.exit == nil)
        #expect(report.lines.contains("the runner's container held another run's exit record — ignored"))
        #expect(!report.lines.contains { $0.hasPrefix("runner: ") })
        #expect(fixture.events == ["end", "copy from", "appearance", "wipe"])
    }

    /// A record with no `session` (a runner older than the stamp) cannot be shown to be this session's, so it is ignored the same way.
    @Test
    func anExitRecordWithNoSessionIsIgnored() throws {
        let fixture = try Fixture(leaseTaken: true)
        fixture.exitSession = nil

        let report = try fixture.stop()

        #expect(report.exit == nil)
        #expect(report.lines.contains("the runner's container held another run's exit record — ignored"))
    }

    /// The session's own record is copied in and reported, in the words the stop always used.
    @Test
    func thisSessionsExitRecordIsCopiedBack() throws {
        let fixture = try Fixture(leaseTaken: true)

        let report = try fixture.stop()

        #expect(report.exit?.session == "s1")
        #expect(report.lines.contains("copied exit.json back from the runner's container"))
        #expect(report.lines.contains { $0.hasPrefix("runner: ended on request") })
    }

    /// An exit record already in the session directory is kept and no copy is made.
    @Test
    func anExitRecordAlreadyCopiedIsKept() throws {
        let fixture = try Fixture(leaseTaken: true)
        try LiveSessionChannel(layout: fixture.layout).markExit(LiveSessionExit(reason: .ended, detail: "sent end", served: 1, stoppedAt: Date(timeIntervalSince1970: 1)))

        let report = try fixture.stop()

        #expect(report.lines.contains("exit.json was already copied back"))
        #expect(report.exit != nil)
        #expect(!fixture.events.contains("copy from"))
    }

    /// Only a failed connect reads the tunnel; an unchanged address names its state, and a failure after the connect reads nothing.
    @Test
    func theTunnelIsReadOnlyAfterAFailedConnect() {
        let endpoint = LiveSessionRecord.DeviceEndpoint(address: "fd00::1", port: 50000, team: "T", runnerBundleID: nil, leaseToken: "L", leaseTaken: true, appearance: nil)
        var listings = 0
        let shell = Shell { _, _, _ in
            listings += 1
            return Shell.Result(status: 0, standardOutput: Fixture.listing(udid: Fixture.udid, address: "fd00::1"), standardError: "")
        }

        let unanswered = LiveSessionDeviceError.diagnosing(.noAnswer(waited: 10), udid: Fixture.udid, endpoint: endpoint, shell: shell)
        let refused = LiveSessionDeviceError.diagnosing(.refused, udid: Fixture.udid, endpoint: endpoint, shell: shell)

        #expect(unanswered.tunnel == nil)
        #expect(listings == 1)
        #expect(refused.description.hasSuffix("[fd00::1]:50000 on \(Fixture.udid); the tunnel is still at fd00::1 (state: connected)"))
        #expect(refused.usageFailureKind == .runnerFailed)
    }

    /// The token file is created at mode 0600, never over an existing one, and reads back as the token written.
    @Test
    func theTokenFileIsPrivateAndWrittenOnce() throws {
        let directory = try TemporaryDirectory()
        let file = LiveSessionTokenFile(layout: LiveSessionLayout(directory: directory.url))
        let token = try DeviceSessionToken.random()

        try file.write(token)

        let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int

        #expect(mode == 0o600)
        #expect(try file.read() == token)
        #expect(throws: (any Error).self) { try file.write(DeviceSessionToken.random()) }
    }

    /// A lease another walk has taken since `start` is not this session's phone to change: neither the appearance nor the runner's container is touched, each says why, and the session's own directory is still removed.
    @Test
    func aLeaseTakenOverLeavesTheAppearanceAndTheContainer() throws {
        let fixture = try Fixture(leaseTaken: true)
        try fixture.takeOverLease()

        let report = try fixture.stop()

        #expect(try fixture.leases.lease(onDevice: Fixture.udid)?.token == "LEASE-2")
        #expect(report.lines.contains("the session's lease on \(Fixture.udid) was already gone or taken over, so nothing was released"))
        try Self.expectPhoneLeftAlone(fixture, report)
    }

    /// A lease that lapsed with no one taking it is no longer this session's either: the phone is left as it is, the same as one taken over.
    @Test
    func aLapsedLeaseLeavesTheAppearanceAndTheContainer() throws {
        let fixture = try Fixture(leaseTaken: true)
        try fixture.lapseLease()

        let report = try fixture.stop()

        try Self.expectPhoneLeftAlone(fixture, report)
    }

    /// A walk claim on the phone (SimWalk#128) is a walk under this session's own lease as much as another's: the lease renews, and the appearance and the container are still left.
    @Test
    func aLiveWalkClaimLeavesTheAppearanceAndTheContainer() throws {
        let fixture = try Fixture(leaseTaken: false)
        fixture.processes.alive.insert(9999)
        let claim = try WalkClaim.take(udid: Fixture.udid, in: fixture.leases, holder: 9999, isAlive: fixture.processes.isAlive)
        defer { claim.release() }

        let report = try fixture.stop()

        #expect(fixture.events == ["end", "copy from"])
        #expect(!fixture.calls.contains { $0.contains("appearance") || $0.contains("--remove-existing-content") })
        try Self.expectInOrder(report.lines, [
            "appearance not handed back: a walk holds a claim on \(Fixture.udid)",
            "runner container left: a walk holds a claim on \(Fixture.udid)",
            "removed ",
        ])
        #expect(report.qualifications.contains { $0.hasSuffix("`session start` found it in light") })
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path))
    }

    /// A claim whose holder has died is no walk: the handback and the wipe run.
    @Test
    func aWalkClaimWhoseHolderIsGoneDoesNotStopTheHandback() throws {
        let fixture = try Fixture(leaseTaken: true)
        fixture.processes.alive.insert(9999)
        _ = try WalkClaim.take(udid: Fixture.udid, in: fixture.leases, holder: 9999, isAlive: fixture.processes.isAlive)
        fixture.processes.alive.remove(9999)

        let report = try fixture.stop()

        #expect(fixture.events == ["end", "copy from", "appearance", "wipe"])
        #expect(report.qualifications.isEmpty)
    }

    /// No appearance call and no wipe reached the phone, each step says why, and the session's directory is gone.
    private static func expectPhoneLeftAlone(_ fixture: Fixture, _ report: LiveSessionDeviceStop.Report, sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(fixture.events == ["end", "copy from"], sourceLocation: sourceLocation)
        #expect(!fixture.calls.contains { $0.contains("appearance") || $0.contains("--remove-existing-content") }, sourceLocation: sourceLocation)
        try expectInOrder(report.lines, [
            "appearance not handed back: the lease on \(Fixture.udid) is no longer this session's",
            "runner container left: the lease on \(Fixture.udid) is no longer this session's, so it may be another walk's",
            "removed ",
        ], sourceLocation: sourceLocation)
        #expect(!report.qualifications.isEmpty, sourceLocation: sourceLocation)
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.directory.path), sourceLocation: sourceLocation)
    }

    /// Each of `expected` begins one of `lines`, in this order.
    private static func expectInOrder(_ lines: [String], _ expected: [String], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let positions = try expected.map { prefix in
            try #require(lines.firstIndex { $0.hasPrefix(prefix) }, "no line begins \(prefix): \(lines)", sourceLocation: sourceLocation)
        }
        #expect(positions == positions.sorted(), "\(lines)", sourceLocation: sourceLocation)
    }
}

extension LiveSessionDeviceStopTests {
    /// A device session's directory with its token, record and (when `ready`) ready record; a phone answering `devicectl` from a script; a runner that exits when `end` is answered; a lease on the phone.
    final class Fixture {
        static var udid: String {
            "00008160-00000000000000AA"
        }

        static let pid: Int32 = 4242
        static var leaseToken: String {
            "LEASE-1"
        }

        let directory: TemporaryDirectory
        let store: LiveSessionStore
        let layout: LiveSessionLayout
        let leases: LeaseStore
        let processes = FakeSessionProcesses()
        let record: LiveSessionRecord
        private(set) var events: [String] = []
        private(set) var calls: [[String]] = []
        private(set) var filedBeforeCopy = false
        var tunnelAddress = "fd00::1"
        var exitOnPhone = true
        /// The session id the exit record in the phone's container is stamped with: this session's by default, another run's or none to leave a stranger's.
        var exitSession: String? = "s1"
        var endStopsTheRunner = true
        /// Whether the runner exits during the first wait, on its own.
        var exitsOnPause = false
        private var elapsed: TimeInterval = 0

        init(leaseTaken: Bool, ready: Bool = true, address: String = "fd00::1", port: UInt16 = 50000) throws {
            directory = try TemporaryDirectory()
            store = LiveSessionStore(directory: directory.url.appendingPathComponent("sessions", isDirectory: true))
            layout = try store.create(id: "s1")
            leases = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true)) { _ in true }
            _ = try leases.acquire(udid: Self.udid, ttl: 1800, holderPID: 1, now: Date(), physicalDevice: true, token: Self.leaseToken)
            let appearance = PhysicalDeviceAppearance(userInterfaceStyle: "light", textSize: "Large", increaseContrast: false)
            let device = LiveSessionRecord.DeviceEndpoint(
                address: address, port: port, team: "TEAM", runnerBundleID: "com.example.runner", leaseToken: Self.leaseToken, leaseTaken: leaseTaken, appearance: appearance
            )
            record = LiveSessionRecord(id: "s1", pid: Self.pid, udid: Self.udid, app: "com.example.app", startedAt: Date(timeIntervalSince1970: 0), foundAppearance: .light, device: device)
            try store.write(record)
            try LiveSessionTokenFile(layout: layout).write(DeviceSessionToken.random())
            if ready {
                try LiveSessionChannel(layout: layout).markReady(
                    LiveSessionReady(device: CaptureManifest.Device(name: "iPhone", udid: Self.udid, osVersion: "27.0.1"), runnerCommit: nil, readyAt: Date(timeIntervalSince1970: 0))
                )
            }
            processes.runner(Self.pid)
        }

        /// Another walk takes the phone: the session's lease is released and a new one, `LEASE-2`, acquired by another holder.
        func takeOverLease() throws {
            _ = try leases.remove(udid: Self.udid, token: Self.leaseToken)
            _ = try leases.acquire(udid: Self.udid, ttl: 1800, holderPID: 2, now: Date(), physicalDevice: true, token: "LEASE-2")
        }

        /// The session's lease lapses and no one takes it: it is put back expiring long before the stop's clock.
        func lapseLease() throws {
            _ = try leases.remove(udid: Self.udid, token: Self.leaseToken)
            _ = try leases.acquire(udid: Self.udid, ttl: 1, holderPID: 1, now: Date(timeIntervalSince1970: 0), physicalDevice: true, token: Self.leaseToken)
        }

        func stop(realClient: Bool = false, sourceLocation: SourceLocation = #_sourceLocation) throws -> LiveSessionDeviceStop.Report {
            let shell = Shell { [self] _, arguments, _ in try answer(arguments) }
            let pause: (TimeInterval) -> Void = { [self] seconds in
                elapsed += seconds
                if exitsOnPause {
                    processes.alive.remove(Self.pid)
                }
            }
            let now = { [self] in Date(timeIntervalSince1970: 1000 + elapsed) }
            let stop = realClient
                ? LiveSessionDeviceStop(record: record, store: store, processes: processes, leases: leases)
                : LiveSessionDeviceStop(record: record, layout: layout, processes: processes, leases: leases) { [self] _, request, _ in
                    events.append("\(request.action)")
                    if endStopsTheRunner {
                        processes.alive.remove(Self.pid)
                    }
                    return LiveSessionResponse(n: 1, action: .end)
                }
            return try #require(stop, sourceLocation: sourceLocation).perform(shell: shell, pause: pause, now: now)
        }

        /// What the phone answers each `devicectl` call with.
        private func answer(_ arguments: [String]) throws -> Shell.Result {
            calls.append(arguments)
            let answered = { (output: String) in Shell.Result(status: 0, standardOutput: output, standardError: "") }
            if arguments.starts(with: ["devicectl", "list", "devices"]) {
                events.append("list devices")
                return answered(Self.listing(udid: Self.udid, address: tunnelAddress))
            }
            if arguments.contains("appearance") {
                events.append("appearance")
                return answered(#"{"result":{"userInterfaceStyle":"light","textSize":"Large","increaseContrast":false}}"#)
            }
            if arguments.contains("--remove-existing-content") {
                events.append("wipe")
                return answered("")
            }
            if arguments.starts(with: ["devicectl", "device", "copy", "from"]) {
                events.append("copy from")
                filedBeforeCopy = (try? LiveSessionChannel(layout: layout).response(to: 1))?.action == .end
                    && FileManager.default.fileExists(atPath: layout.request(1).path)
                guard exitOnPhone, let destination = arguments.firstIndex(of: "--destination").map({ arguments[$0 + 1] }) else {
                    return Shell.Result(status: 1, standardOutput: "", standardError: "ERROR: The file couldn't be found.")
                }
                let exit = LiveSessionExit(reason: .ended, detail: "ended", served: 1, stoppedAt: Date(timeIntervalSince1970: 1000), session: exitSession)
                try LiveSessionChannel(layout: LiveSessionLayout(directory: URL(fileURLWithPath: destination).deletingLastPathComponent())).markExit(exit)
                return answered("")
            }
            return Shell.Result(status: 1, standardOutput: "", standardError: "unexpected call: \(arguments)")
        }

        static func listing(udid: String, address: String) -> String {
            #"{"result":{"devices":[{"connectionProperties":{"tunnelState":"connected","tunnelIPAddress":"\#(address)"},"properties":{"hardware":{"udid":"\#(udid)"},"connection":{}}}]}}"#
        }
    }
}
