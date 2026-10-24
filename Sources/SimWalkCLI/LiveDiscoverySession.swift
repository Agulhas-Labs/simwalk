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
    /// Where a relaunch's notes go, each as the runner worded it; the session start prints its own the same way.
    var note: (String) -> Void = { _ in }

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
        for line in response.notes ?? [] {
            note("⚠ " + line)
        }
        return screen
    }

    func scroll(_ scroll: LiveSessionScroll) throws -> LiveScreen? {
        try exchange(.scroll, scroll: scroll, timeout: SessionStepCommand.stepTimeout).screen
    }

    /// How long a relaunch waits for its answer: the app's end and launch, the settle, and a read.
    static var relaunchTimeout: TimeInterval {
        120
    }

    private func exchange(_ action: LiveSessionRequest.Action, step: Walkbook.RouteStep? = nil, scroll: LiveSessionScroll? = nil, timeout: TimeInterval) throws -> LiveSessionResponse {
        if cancellation?.isCancelled == true {
            throw DiscoverError.cancelled
        }
        if let device = LiveSessionDeviceExchange(record: record, store: store, leases: leases, send: deviceSend) {
            return try device.perform(DeviceSessionRequest(action: action, step: step, scroll: scroll), timeout: timeout, processes: processes, shell: shell, now: now)
        }
        let channel = LiveSessionChannel(layout: store.layout(id: record.id))
        let number = try channel.send(action, step: step, scroll: scroll)
        return try channel.awaitResponse(to: number, timeout: timeout, isRunnerAlive: { processes.isRunning(record) }, pause: pause, now: now)
    }
}
