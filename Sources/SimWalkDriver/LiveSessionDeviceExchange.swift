//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// One request to a device session's runner, from `session read` and `session step` (Brief, "Live sessions on a physical device", rulings 3, 4, 7 and 8).
///
/// **Order is the point.** The session's lease is renewed first, and a renewal that fails refuses before anything is sent: a request must not reach a phone whose lease has lapsed to another holder. Then the token is read, the one exchange is made, and the request and the response are filed under the number the runner gave them, so ``LiveSessionChannel/route()``, `save` and `list` read a device's session as they read a simulator's. A failed connect is followed by one `devicectl list devices` read (``LiveSessionDeviceError``).
///
/// **A runner that has stopped is named by its own record** (ruling 6): when `xcodebuild` has exited, or the connect is refused, the runner's `exit.json` is copied back once (``LiveSessionDeviceExit``) and the refusal is its summary (`idle`, `ended`, `failed: …`), as `end` and `list` give it. Only a refused connect with no record to read falls through to the tunnel diagnosis.
public struct LiveSessionDeviceExchange {
    public let record: LiveSessionRecord
    public let endpoint: LiveSessionRecord.DeviceEndpoint
    public let layout: LiveSessionLayout
    public let leases: LeaseStore
    public typealias Send = (DeviceSessionToken, DeviceSessionRequest, TimeInterval) throws -> LiveSessionResponse

    /// Sends one request to the runner with the session's token: a ``DeviceSessionClient`` on the record's address, or a test's stand-in.
    let exchange: Send

    /// The exchange for `record`; `nil` when it is a simulator's, which the file channel serves.
    ///
    /// `send` stands in for the socket in a test; `nil` is a ``DeviceSessionClient`` on the record's address.
    public init?(record: LiveSessionRecord, store: LiveSessionStore, leases: LeaseStore, send: Send? = nil) {
        guard let endpoint = record.device else { return nil }
        self.record = record
        self.endpoint = endpoint
        layout = store.layout(id: record.id)
        self.leases = leases
        exchange = send ?? { token, request, timeout in
            try DeviceSessionClient(address: endpoint.address, port: endpoint.port, token: token).exchange(request, timeout: timeout)
        }
    }

    /// Renews the session's lease for a full ``WalkLease/ttl`` from `now`; refuses as ``LiveSessionHostError/deviceLeaseNotRenewed(id:udid:reason:)`` when it cannot.
    public func renewLease(now: () -> Date) throws {
        do {
            _ = try leases.renew(token: endpoint.leaseToken, ttl: WalkLease.ttl, now: now())
        } catch {
            throw LiveSessionHostError.deviceLeaseNotRenewed(id: record.id, udid: record.udid, reason: "\(error)")
        }
    }

    /// The line a failed `read` or `step` adds when the phone is locked, from one `devicectl device info lockState` read; `nil` when it is unlocked or the read fails, so the refusal stays as it was.
    ///
    /// XCTest on a locked phone refuses with `kAXErrorServerNotFound`, which does not say so, and on Wi-Fi the tunnel does not come back after the unlock (Brief, "A locked phone").
    public func lockNote(shell: Shell) -> String? {
        guard (try? PhysicalDevicePrerequisites.passcodeRequired(udid: record.udid, shell: shell)) == true else { return nil }
        return "the phone is locked: unlock it — on Wi-Fi a lock usually ends the session, so `simwalk session end \(record.id)` and start again"
    }

    /// Sends `request`, waits up to `timeout` for the runner's response and files both; the response.
    public func perform(_ request: DeviceSessionRequest, timeout: TimeInterval, processes: any LiveSessionProcesses, shell: Shell, now: () -> Date) throws -> LiveSessionResponse {
        guard !endpoint.address.isEmpty else {
            throw LiveSessionHostError.deviceNotReady(id: record.id)
        }
        if (try? LiveSessionChannel(layout: layout).exitRecord()) != nil || !processes.isRunning(record) {
            throw LiveSessionHostError.deviceRunnerStopped(id: record.id, exit: LiveSessionDeviceExit.recorded(record: record, layout: layout, shell: shell), lockNote: lockNote(shell: shell))
        }
        try renewLease(now: now)
        let token: DeviceSessionToken
        do {
            token = try LiveSessionTokenFile(layout: layout).read()
        } catch {
            throw LiveSessionHostError.deviceTokenUnreadable(path: layout.token.path, reason: error.localizedDescription)
        }
        let response: LiveSessionResponse
        do {
            response = try exchange(token, request, timeout)
        } catch let failure as DeviceSessionClientError {
            if case .refused = failure, let exit = LiveSessionDeviceExit.recorded(record: record, layout: layout, shell: shell) {
                throw LiveSessionHostError.deviceRunnerStopped(id: record.id, exit: exit, lockNote: lockNote(shell: shell))
            }
            var diagnosis = LiveSessionDeviceError.diagnosing(failure, udid: record.udid, endpoint: endpoint, shell: shell)
            diagnosis.lockNote = lockNote(shell: shell)
            throw diagnosis
        }
        try LiveSessionChannel(layout: layout).file(request, answeredBy: response)
        return response
    }
}
