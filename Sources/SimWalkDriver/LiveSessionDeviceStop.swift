//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore

/// Ends a live session on a physical device (Brief, "Live sessions on a physical device", rulings 6–9, and "The runner app on a device", ruling 1): asks the runner to end over the socket, waits, signals it under the simulator's guards, then copies its `exit.json` back, hands the phone's appearance back, empties the runner's container, releases a lease the session took, and removes the session's directory — unless the runner is still running.
///
/// **The process is stopped exactly as a simulator's** (``LiveSessionRunnerGuard``): the same `xcodebuild` spawned the same way, so the same three guards before any signal.
///
/// **`end` is sent only to a runner that answered `hello`** (`ready.json`): before that it may never have bound, so a connect could only be refused. `session start` runs this stop on a runner that never became ready, and `end` is skipped there. **A connect that fails** — refused, unreachable, timed out — **is followed by one `devicectl list devices`**, and a tunnel that has come back at another address is named beside the one the runner listened on. Either way the runner is then waited on and, if need be, signalled: a refused connect is often a runner already on its way out.
///
/// **Everything after the process runs on every path**, each step a line: there is no heartbeat and no accessibility on a device to hand back, but the exit record is still on the phone, and the container keeps the session's files until it is emptied. **Two steps change the phone itself, so they first renew the session's lease** (ruling 8): a lease that has lapsed or passed to another holder leaves the appearance and the container as they are, each with a line saying why, and a runner still running leaves the container it is using. **A live walk claim on the phone** (``WalkClaim``, which a device walk takes under whatever lease it runs, SimWalk#128) leaves both too, each with a line saying so, because a walk under the session's own lease renews that lease and would otherwise be handed its appearance back and its container emptied mid-walk. **A lease the session took is released; a presented one is its holder's and is kept** — and so is the session's own while its runner is still running, as the directory is, so that the phone is not handed to another walk with an orphan runner on it.
public struct LiveSessionDeviceStop {
    public let record: LiveSessionRecord
    public let endpoint: LiveSessionRecord.DeviceEndpoint
    public let layout: LiveSessionLayout
    public let processes: any LiveSessionProcesses
    public let leases: LeaseStore
    /// Sends one request to the runner with the session's token and answers its response: a ``DeviceSessionClient`` on the record's address, or a test's stand-in.
    let exchange: (DeviceSessionToken, DeviceSessionRequest, TimeInterval) throws -> LiveSessionResponse

    /// The stop for `record`; `nil` when it is a simulator's, which ``LiveSessionStop`` ends.
    public init?(record: LiveSessionRecord, store: LiveSessionStore, processes: any LiveSessionProcesses, leases: LeaseStore) {
        guard let endpoint = record.device else { return nil }
        self.init(record: record, layout: store.layout(id: record.id), processes: processes, leases: leases) { token, request, timeout in
            try DeviceSessionClient(address: endpoint.address, port: endpoint.port, token: token).exchange(request, timeout: timeout)
        }
    }

    init?(
        record: LiveSessionRecord,
        layout: LiveSessionLayout,
        processes: any LiveSessionProcesses,
        leases: LeaseStore,
        exchange: @escaping (DeviceSessionToken, DeviceSessionRequest, TimeInterval) throws -> LiveSessionResponse
    ) {
        guard let endpoint = record.device else { return nil }
        self.record = record
        self.endpoint = endpoint
        self.layout = layout
        self.processes = processes
        self.leases = leases
        self.exchange = exchange
    }

    /// How long the runner is given to answer `end` and exit, and again after `SIGTERM` — the simulator's.
    public static var grace: TimeInterval {
        LiveSessionStop.grace
    }

    public func perform(shell: Shell, pause: (TimeInterval) -> Void, now: () -> Date) -> Report {
        let channel = LiveSessionChannel(layout: layout)
        let ready = (try? channel.readyRecord()) != nil
        var steps: [String] = []
        let waitedAfter = ready ? "end" : "the stop began (end was not sent)"
        let runner = LiveSessionRunnerGuard(record: record, processes: processes, grace: Self.grace, waitedAfter: waitedAfter).stop(
            steps: &steps,
            askToEnd: { ready ? askToEnd(channel, shell: shell) : "end not sent: the runner never answered hello, so it may never have listened" },
            pause: pause,
            now: now
        )
        let fetched = LiveSessionDeviceExit.fetch(record: record, layout: layout, shell: shell)
        steps.append(fetched.line)
        let exit = fetched.exit
        if let exit {
            steps.append("runner: \(exit.summary)")
        }
        let leaseLost = renewLease(now: now())
        let walked = WalkClaim.walkedDevices(in: leases, isAlive: processes.isAlive).contains(record.udid)
        let appearance = if let leaseLost {
            appearanceKept(leaseLost: leaseLost)
        } else if walked {
            appearanceKeptForWalk
        } else {
            handBackAppearance(shell: shell)
        }
        steps += appearance.lines
        let wipe = if let leaseLost {
            containerKept(leaseLost: leaseLost)
        } else if walked {
            containerKeptForWalk
        } else if runner.stillRunning {
            Self.containerKeptForRunner
        } else {
            RunnerContainerWipe(udid: record.udid, runnerBundleID: endpoint.runnerBundleID, shell: shell).empty()
        }
        steps.append(wipe.line)
        steps.append(releaseLease(runnerStillRunning: runner.stillRunning))
        var removal: String?
        if runner.stillRunning {
            steps.append("kept \(layout.directory.path): the runner is still running, so the session stays listed — end it again once it has stopped")
        } else {
            do {
                try FileManager.default.removeItem(at: layout.directory)
                steps.append("removed \(layout.directory.path)")
            } catch {
                removal = "\(layout.directory.path) could not be removed: \(error.localizedDescription)"
            }
        }
        return Report(lines: steps, exit: exit, appearance: appearance, wipe: wipe, stillRunning: runner.stillRunning, removalFailure: removal)
    }

    /// Sends `end` with the session's token and files the exchange under the number the runner gave it; the step's line.
    private func askToEnd(_ channel: LiveSessionChannel, shell: Shell) -> String {
        let token: DeviceSessionToken
        do {
            token = try LiveSessionTokenFile(layout: layout).read()
        } catch {
            return "end not sent: the session's token could not be read from \(layout.token.path): \(error.localizedDescription)"
        }
        let request = DeviceSessionRequest(action: .end)
        let response: LiveSessionResponse
        do {
            response = try exchange(token, request, Self.grace)
        } catch let failure as DeviceSessionClientError {
            return "sent end: \(LiveSessionDeviceError.diagnosing(failure, udid: record.udid, endpoint: endpoint, shell: shell))"
        } catch {
            return "sent end: \(error)"
        }
        do {
            try channel.file(request, answeredBy: response)
        } catch {
            return "sent end; the runner answered it as request \(response.n), which could not be filed: \(error)"
        }
        return "sent end (request \(response.n)); the runner answered"
    }

    /// The phone's appearance handed back as `start` found it; a qualification when it was never read.
    private func handBackAppearance(shell: Shell) -> PhysicalDeviceAppearance.Handback {
        guard let found = endpoint.appearance else {
            return PhysicalDeviceAppearance.Handback(
                lines: ["appearance not handed back: `session start` could not read it"],
                qualifications: ["the device's appearance was not read when the session started, so it could not be handed back"]
            )
        }
        return PhysicalDeviceAppearance.handBack(found: found, udid: record.udid, shell: shell)
    }

    /// Renews the session's lease by its token, as every request to the runner does first (``LiveSessionDeviceExchange``); why it is no longer this session's, or `nil` when it still is.
    ///
    /// **The handback and the wipe act on the phone, not on this session's own files**: a lease that has lapsed may have been taken by another walk with the same runner, whose container the wipe would empty mid-run and whose theme the handback would flip. Any failure counts — a renewal that could not be confirmed is not a phone this session may still change.
    private func renewLease(now: Date) -> String? {
        do {
            _ = try LeaseError.mapping { try leases.renew(token: endpoint.leaseToken, ttl: WalkLease.ttl, now: now) }
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// The appearance left as it is because the lease is no longer this session's.
    private func appearanceKept(leaseLost reason: String) -> PhysicalDeviceAppearance.Handback {
        PhysicalDeviceAppearance.Handback(
            lines: ["appearance not handed back: the lease on \(record.udid) is no longer this session's (\(reason))"],
            qualifications: ["the device's appearance was not handed back: the lease on \(record.udid) is no longer this session's"]
        )
    }

    /// The runner's container left as it is because the lease is no longer this session's, so it may hold another walk's files.
    private func containerKept(leaseLost reason: String) -> RunnerContainerWipe.Outcome {
        RunnerContainerWipe.Outcome(emptied: false, line: "runner container left: the lease on \(record.udid) is no longer this session's, so it may be another walk's (\(reason))")
    }

    /// The appearance left as it is because a walk holds a claim on the phone, which may be a walk under this session's own lease.
    ///
    /// **The walk hands back the appearance it found, not this session's**: under this session's lease that may be the one this session's runner set, and the session's directory, the one place the appearance `start` found is kept, is removed below. So the line and the qualification name it, for the user to put back.
    private var appearanceKeptForWalk: PhysicalDeviceAppearance.Handback {
        let found = endpoint.appearance.map { "`session start` found it in \($0.userInterfaceStyle)" } ?? "`session start` could not read it"
        return PhysicalDeviceAppearance.Handback(
            lines: ["appearance not handed back: a walk holds a claim on \(record.udid), so the phone is in use — the walk hands back the appearance it found, which may not be this session's (\(found))"],
            qualifications: ["the device's appearance was not handed back: a walk holds a claim on \(record.udid), and \(found)"]
        )
    }

    /// The runner's container left as it is because a walk holds a claim on the phone, so it may be the walk's files.
    private var containerKeptForWalk: RunnerContainerWipe.Outcome {
        RunnerContainerWipe.Outcome(emptied: false, line: "runner container left: a walk holds a claim on \(record.udid), so it may be the walk's")
    }

    /// The runner's container left as it is because the runner is still running in it — the same reason the lease and the directory are kept.
    private static var containerKeptForRunner: RunnerContainerWipe.Outcome {
        RunnerContainerWipe.Outcome(emptied: false, line: "runner container left: the runner is still running in it — `end` empties it once it has stopped")
    }

    /// Releases the lease the session took, by its token, so one somebody has since taken over is never removed; the step's line.
    private func releaseLease(runnerStillRunning: Bool) -> String {
        let udid = record.udid
        guard endpoint.leaseTaken else {
            return "kept the presented lease on \(udid): it is its holder's to release"
        }
        guard !runnerStillRunning else {
            return "kept the session's lease on \(udid): the runner is still running — `end` releases it once it has stopped"
        }
        do {
            return try LeaseError.mapping { try leases.remove(udid: udid, token: endpoint.leaseToken) }
                ? "released the session's lease on \(udid)"
                : "the session's lease on \(udid) was already gone or taken over, so nothing was released"
        } catch {
            return "the session's lease on \(udid) could not be released (\(error)); it lapses on its own"
        }
    }
}

public extension LiveSessionDeviceStop {
    /// What the device's end procedure did, in the order it did it.
    struct Report {
        /// Every step, in order: the runner, its exit record, the appearance, the container, the lease, the directory.
        public let lines: [String]
        /// Why the runner stopped, in its own words; `nil` when its record could not be copied back.
        public let exit: LiveSessionExit?
        public let appearance: PhysicalDeviceAppearance.Handback
        public let wipe: RunnerContainerWipe.Outcome
        public let stillRunning: Bool
        public let removalFailure: String?

        /// What qualifies an end: a runner left running, a directory left behind, a phone not handed back as found, a container not emptied.
        public var qualifications: [String] {
            (stillRunning ? ["the runner is still running"] : []) + (removalFailure.map { [$0] } ?? []) + appearance.qualifications
                + (wipe.emptied ? [] : [wipe.line])
        }
    }
}
