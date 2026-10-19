//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk session step <id> '<step json>' [--guard <hash>]` — one route step in the session's app, taken exactly as a walk takes it, answered with the step that replays it, the screen's hash and what changed.
///
/// The step is a walkbook route step (`{"tap":{"label":"Next"}}`), decoded by the walkbook's own strict decoder, so a step this takes is one a walkbook can hold. `--guard` is the `screen <hash>` a read printed: the runner refuses the step, without acting, when the screen no longer has it.
struct SessionStepCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "step",
        abstract: "Take one route step in a live session's app, as a walk takes it: the step that replays it, the screen's hash, and what changed."
    )

    @Argument(help: "The session id `session start` printed.")
    var id: String

    @Argument(help: #"One walkbook route step, as JSON: {"tap":{"label":"Next"}}, {"openURL":{"url":"myapp://x"}}, {"back":{}}."#)
    var step: String

    @Option(name: .customLong("guard"), help: "The `screen <hash>` a read printed; the step is refused, and nothing done, when the screen no longer has it.")
    var guardHash: String?

    func run() throws {
        try TimedCall.run(tool: "session step", target: id, defaultFailureKind: .runnerFailed) {
            try perform()
        }
    }

    /// How long a step waits for its answer: a step's own waits (a label resolved, a scroll's swipes, the arrival) and two reads.
    static var stepTimeout: TimeInterval {
        120
    }

    func perform(
        store: LiveSessionStore = .standard(),
        processes: any LiveSessionProcesses = LiveSessionSystemProcesses(),
        leases: LeaseStore = .standard(),
        shell: Shell = Shell(),
        deviceSend: LiveSessionDeviceExchange.Send? = nil,
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: () -> Date = { Date() }
    ) throws -> Answer {
        let routeStep: Walkbook.RouteStep
        do {
            routeStep = try JSONDecoder().decode(Walkbook.RouteStep.self, from: Data(step.utf8))
        } catch {
            throw ValidationError("'\(step)' is not a walkbook route step (\(error)); write one as a walkbook does, e.g. {\"tap\":{\"label\":\"Next\"}}")
        }
        guard let record = store.record(id: id) else {
            throw LiveSessionHostError.unknownSession(id: id)
        }
        let channel = LiveSessionChannel(layout: store.layout(id: id))
        let number: Int
        let response: LiveSessionResponse
        let device = LiveSessionDeviceExchange(record: record, store: store, leases: leases, send: deviceSend)
        if let device {
            response = try device.perform(DeviceSessionRequest(action: .step, step: routeStep, guardHash: guardHash), timeout: Self.stepTimeout, processes: processes, shell: shell, now: now)
            number = response.n
        } else {
            number = try channel.send(.step, step: routeStep, guardHash: guardHash)
            response = try channel.awaitResponse(to: number, timeout: Self.stepTimeout, isRunnerAlive: { processes.isRunning(record) }, pause: pause, now: now)
        }
        guard let stepAnswer = response.step else {
            let failure = response.failure ?? "it answered with no step outcome"
            throw LiveSessionHostError.runnerFailed(number: number, failure: failure + (device?.lockNote(shell: shell).map { "\n\($0)" } ?? ""))
        }
        return try LiveSessionStepQuery(sent: routeStep, answer: stepAnswer, screen: response.screen).answer()
    }
}
