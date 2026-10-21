//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `discover`'s way into a live session: each read, step and relaunch sent to the resident runner as `session read` and `session step` send theirs — through the session directory on a simulator, over the device exchange on a phone.
///
/// A cancelled run sends nothing more: the next request is refused, so the crawl unwinds to the end that hands the device back.
struct LiveDiscoverySession: DiscoverySession {
    let record: LiveSessionRecord
    let store: LiveSessionStore
    let processes: any LiveSessionProcesses
    let leases: LeaseStore
    let shell: Shell
    var deviceSend: LiveSessionDeviceExchange.Send?
    let cancellation: Cancellation?
    let pause: (TimeInterval) -> Void
    let now: () -> Date

    func read() throws -> LiveScreen {
        let response = try exchange(.read, timeout: SessionReadCommand.readTimeout)
        guard let screen = response.screen else {
            throw LiveSessionHostError.runnerFailed(number: response.n, failure: response.failure ?? "it answered with no screen")
        }
        return screen
    }

    func send(_ step: Walkbook.RouteStep) throws -> LiveSessionResponse {
        try exchange(.step, step: step, timeout: SessionStepCommand.stepTimeout)
    }

    func relaunch() throws -> LiveScreen {
        let response = try exchange(.relaunch, timeout: Self.relaunchTimeout)
        guard let screen = response.screen else {
            throw LiveSessionHostError.runnerFailed(number: response.n, failure: response.failure ?? "it answered the relaunch with no screen")
        }
        return screen
    }

    /// How long a relaunch waits for its answer: the app's end and launch, the settle, and a read.
    static var relaunchTimeout: TimeInterval {
        120
    }

    private func exchange(_ action: LiveSessionRequest.Action, step: Walkbook.RouteStep? = nil, timeout: TimeInterval) throws -> LiveSessionResponse {
        if cancellation?.isCancelled == true {
            throw DiscoverError.cancelled
        }
        if let device = LiveSessionDeviceExchange(record: record, store: store, leases: leases, send: deviceSend) {
            return try device.perform(DeviceSessionRequest(action: action, step: step), timeout: timeout, processes: processes, shell: shell, now: now)
        }
        let channel = LiveSessionChannel(layout: store.layout(id: record.id))
        let number = try channel.send(action, step: step)
        return try channel.awaitResponse(to: number, timeout: timeout, isRunnerAlive: { processes.isRunning(record) }, pause: pause, now: now)
    }
}
