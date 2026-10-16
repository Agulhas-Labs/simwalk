//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Starts a live session's runner on a physical device and waits for its first answer (Brief, "Live sessions on a physical device", rulings 1, 2 and 5).
///
/// **The address goes in after the spawn.** The tunnel's address is good for the life of the runner's test and no earlier, so the host spawns `xcodebuild` first, then reads the address and copies `bind.json` into the runner's container, again whenever the address it reads changes and on the next turn when a copy fails (the container exists once `xcodebuild` has installed the runner). Ready is the first answer to `hello`, tried every ``pollInterval``.
///
/// **The token never leaves the session directory's `token` and `bind.json`**: the runner's command carries the session id alone, and `bind.json` is written at mode 0600 into a private directory inside the session's own, removed as soon as it is copied — and, should the start be killed while a copy retries, by the stop's removal of the session directory.
///
/// **A runner that never answers leaves nothing behind**: its diagnosis is read while its result bundle exists, then the device stop (``LiveSessionDeviceStop``) stops it, copies its exit record back, hands the appearance back, empties its container, releases a lease the session took and removes the directory.
public struct LiveSessionDeviceStart {
    public let store: LiveSessionStore
    public let processes: any LiveSessionProcesses
    public let leases: LeaseStore

    public init(store: LiveSessionStore, processes: any LiveSessionProcesses, leases: LeaseStore) {
        self.store = store
        self.processes = processes
        self.leases = leases
    }

    /// How often the tunnel is read and `hello` tried while the runner starts.
    public static var pollInterval: TimeInterval {
        0.5
    }

    /// A port for one session, drawn from the dynamic range 49152–65535.
    public static func drawPort() -> UInt16 {
        UInt16.random(in: 49152 ... 65535)
    }

    /// Spawns the runner for `launch` on `udid`, sends it where to listen and waits for its first answer, stopping it and handing the device back when there is none.
    ///
    /// **A cancel after the spawn stops the session the same way and throws ``LiveSessionHostError/startCancelled(udid:lines:)``** rather than answering ready (SimWalk#127): over MCP a cancelled request's answer is dropped, so a session that ran on would be one whose id its caller never learned.
    ///
    /// `endpoint` is the session's holdings with no address yet; the record written at the spawn carries the address sent so far (empty before any), and the one written on ready the address the runner answered on.
    public func perform(id: String, udid: String, launch: LiveSessionLaunch, endpoint: LiveSessionRecord.DeviceEndpoint, effects: Effects) throws -> (record: LiveSessionRecord, ready: LiveSessionReady) {
        if let live = LiveSessionStart(store: store, processes: processes).liveSession(on: udid) {
            throw LiveSessionHostError.alreadyRunning(udid: udid, id: live.id, pid: live.pid)
        }
        let layout = try store.create(id: id)
        let channel = LiveSessionChannel(layout: layout)
        let token: DeviceSessionToken
        let pid: Int32
        do {
            token = try DeviceSessionToken.random()
            try LiveSessionTokenFile(layout: layout).write(token)
            try channel.writeLaunch(launch)
            pid = try effects.spawning { try processes.spawn(effects.command(layout), log: layout.runnerLog) }
        } catch {
            try? FileManager.default.removeItem(at: layout.directory)
            throw error
        }
        let found = endpoint.appearance.flatMap { Walkbook.Theme(rawValue: $0.userInterfaceStyle) }
        let startedAt = effects.now()
        func record(address: String) -> LiveSessionRecord {
            let device = LiveSessionRecord.DeviceEndpoint(
                address: address,
                port: endpoint.port,
                team: endpoint.team,
                runnerBundleID: endpoint.runnerBundleID,
                leaseToken: endpoint.leaseToken,
                leaseTaken: endpoint.leaseTaken,
                appearance: endpoint.appearance
            )
            return LiveSessionRecord(id: id, pid: pid, udid: udid, app: launch.appBundleID, startedAt: startedAt, foundAppearance: found, device: device)
        }
        var wait = ReadyWait(sent: nil, reason: "")
        do {
            // Written at the spawn, so a start killed while it waits leaves a session `end` can stop.
            try store.write(record(address: ""))
            wait = awaitHello(DeviceSessionBind(session: id, address: "", port: endpoint.port, token: token), layout: layout, udid: udid, pid: pid, runnerBundleID: endpoint.runnerBundleID, effects: effects)
            // Read again after the wait: a cancel that lands while the last `hello` is answered stops the session too, since the caller that would learn its id has gone.
            if !effects.cancelled(), let ready = wait.ready, let sent = wait.sent {
                try channel.markReady(ready)
                let answered = record(address: sent)
                try store.write(answered)
                return (answered, ready)
            }
        } catch {
            wait.reason = "\(error)"
        }
        let cancelled = effects.cancelled()
        // A cancelled runner failed at nothing, so it has nothing to diagnose.
        let diagnosis = cancelled ? [] : effects.diagnose(layout)
        let stopping = record(address: wait.sent ?? "")
        let report = LiveSessionDeviceStop(record: stopping, store: store, processes: processes, leases: leases)?.perform(shell: effects.shell, pause: effects.pause, now: effects.now)
        let lines = report.map { $0.lines + $0.qualifications.map { "⚠ \($0)" } } ?? []
        if cancelled {
            throw LiveSessionHostError.startCancelled(udid: udid, lines: lines)
        }
        throw LiveSessionHostError.neverReady(reason: wait.reason, lines: lines + diagnosis)
    }

    /// Reads the tunnel, sends `bind.json` for each new address and tries `hello` on the last one sent, every ``pollInterval``, until the runner answers, its `xcodebuild` exits, the start is cancelled, or ``LiveSessionStart/readyTimeout`` passes.
    ///
    /// `template` is the session's `bind.json` with no address yet.
    private func awaitHello(_ template: DeviceSessionBind, layout: LiveSessionLayout, udid: String, pid: Int32, runnerBundleID: String?, effects: Effects) -> ReadyWait {
        let (session, port, token) = (template.session, template.port, template.token)
        let started = effects.now()
        let container = RunnerInvocation.deviceContainerBundleID(runnerBundleID: runnerBundleID)
        var wait = ReadyWait(sent: nil, reason: "no tunnel to \(udid) was read")
        while true {
            // Checked before each turn's calls to the phone: a cancelled start has no caller left to answer, so waiting out the rest of 180 s for one only delays the stop.
            guard !effects.cancelled() else { return wait }
            let tunnel = PhysicalDeviceTunnel.read(udid: udid, shell: effects.shell)
            if let address = tunnel.address, address != wait.sent {
                let bind = DeviceSessionBind(session: session, address: address, port: port, token: token)
                if let failure = Self.send(bind, udid: udid, container: container, scratchIn: layout.directory, shell: effects.shell) {
                    wait.reason = "bind.json for \(address) was not copied into the runner's container: \(failure)"
                } else {
                    wait.sent = address
                }
            } else if tunnel.address == nil, wait.sent == nil {
                wait.reason = "no tunnel address for \(udid) (tunnel state: \(tunnel.state ?? "not reported"))"
            }
            if let sent = wait.sent {
                do {
                    wait.ready = try effects.hello(DeviceSessionBind(session: session, address: sent, port: port, token: token))
                    return wait
                } catch DeviceSessionClientError.refused {
                    wait.reason = "the runner refused hello on \(Self.endpoint(sent, port)): it is not listening yet"
                } catch {
                    wait.reason = "hello to \(Self.endpoint(sent, port)): \(error)"
                }
            }
            guard processes.isAlive(pid) else {
                wait.reason = "xcodebuild (pid \(pid)) exited before the runner answered hello — its output is in runner.log; last: \(wait.reason)"
                return wait
            }
            guard effects.now().timeIntervalSince(started) < LiveSessionStart.readyTimeout else {
                wait.reason = "no answer to hello within \(Int(LiveSessionStart.readyTimeout)) s; last: \(wait.reason)"
                return wait
            }
            effects.pause(Self.pollInterval)
        }
    }

    /// Copies `bind` into the runner's container as `Documents/SimWalkSession/bind.json`; why not, or `nil` once it landed.
    ///
    /// Written at mode 0600, never over an existing file, into a directory of its own (mode 0700) that is removed whatever the copy did: the token is on this Mac's disk only in the session's `token`.
    ///
    /// **That directory is inside `directory`, the session's own**, never `$TMPDIR`: a copy can retry for many seconds while `xcodebuild` installs the runner, and a start killed meanwhile never runs the `defer`, so only the stop's removal of the session directory is sure to take the file (SimWalk#116).
    static func send(_ bind: DeviceSessionBind, udid: String, container: String, scratchIn directory: URL, shell: Shell) -> String? {
        let scratch = directory.appendingPathComponent("bind-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } catch {
            return "\(error)"
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        let file = scratch.appendingPathComponent("bind.json")
        do {
            let descriptor = open(file.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else {
                return "\(file.path) could not be created: \(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))"
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: JSONEncoder().encode(bind))
            try handle.close()
            let result = try shell.run("/usr/bin/xcrun", [
                "devicectl", "device", "copy", "to",
                "--device", udid,
                "--domain-type", "appDataContainer",
                "--domain-identifier", container,
                "--source", file.path,
                "--destination", "\(LiveSessionRecord.DeviceEndpoint.containerSessionPath)/bind.json",
                "--quiet",
            ])
            return result.succeeded ? nil : result.failureLine
        } catch {
            return "\(error)"
        }
    }

    /// `[address]:port` for an IPv6 address, `address:port` for an IPv4 one.
    static func endpoint(_ address: String, _ port: UInt16) -> String {
        address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
    }
}

public extension LiveSessionDeviceStart {
    /// What `perform` reaches beyond the session's own directory — the runner's command line and diagnosis, the phone through `shell`, the runner through `hello`, and time — so a test states each.
    struct Effects {
        /// The resident runner's command line for the session's layout; never carries the token.
        public let command: (LiveSessionLayout) -> RunnerCommand
        /// The runner's own account of why it never answered, read from its result bundle.
        public let diagnose: (LiveSessionLayout) -> [String]
        /// Runs `devicectl` for the tunnel read, the `bind.json` copy and the stop.
        public let shell: Shell
        /// Sends `hello` to the address, port and token `bind.json` named, answering the runner's ready record.
        public let hello: (DeviceSessionBind) throws -> LiveSessionReady
        public let pause: (TimeInterval) -> Void
        public let now: () -> Date
        /// Runs the spawn it is handed, or refuses it by throwing.
        ///
        /// A start that can be cancelled checks the cancel and spawns under one lock, so the cancel lands wholly before the spawn or wholly after it. From a spawn that returned on, a failure is the stop's to clean up.
        public let spawning: (_ spawn: () throws -> Int32) throws -> Int32
        /// Whether the start has been cancelled since its spawn: the wait for `hello` ends, and the device stop runs as for a runner that never answered.
        public let cancelled: () -> Bool

        public init(
            command: @escaping (LiveSessionLayout) -> RunnerCommand,
            diagnose: @escaping (LiveSessionLayout) -> [String],
            shell: Shell,
            hello: @escaping (DeviceSessionBind) throws -> LiveSessionReady,
            pause: @escaping (TimeInterval) -> Void,
            now: @escaping () -> Date,
            spawning: @escaping (_ spawn: () throws -> Int32) throws -> Int32 = { try $0() },
            cancelled: @escaping () -> Bool = { false }
        ) {
            self.command = command
            self.diagnose = diagnose
            self.shell = shell
            self.hello = hello
            self.pause = pause
            self.now = now
            self.spawning = spawning
            self.cancelled = cancelled
        }
    }
}

extension LiveSessionDeviceStart {
    /// Where the wait for the runner's first answer stands: the address last sent in `bind.json`, the answer once there is one, and else why not yet.
    struct ReadyWait {
        var sent: String?
        var reason: String
        var ready: LiveSessionReady?
    }
}
