//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk session read <id> [--match <text>]` — `inspect`'s answer, from the session's resident runner.
///
/// The screen is rendered by ``InspectCommand/outcome(runnerFailure:handback:diagnosingRunnerFailure:readingScreen:match:crashReport:screenshotOutcome:)`` itself, so a warm read and a cold one cannot answer differently; `--match` is applied here, as `inspect` applies it.
struct SessionReadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read the screen a live session's app is on — inspect's answer, warm."
    )

    @Argument(help: "The session id `session start` printed.")
    var id: String

    /// `.unconditional` for the reason `inspect`'s is.
    @Option(name: .long, parsing: .unconditional, help: "Only the text elements whose label or value contains this text (case-insensitive).")
    var match: String?

    @OptionGroup var screenshot: ScreenshotOptions

    func run() throws {
        try TimedCall.run(tool: "session read", target: id, defaultFailureKind: .runnerFailed) {
            try perform()
        }
    }

    /// How long a read waits for its answer.
    static var readTimeout: TimeInterval {
        60
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
        guard let record = store.record(id: id) else {
            throw LiveSessionHostError.unknownSession(id: id)
        }
        let channel = LiveSessionChannel(layout: store.layout(id: id))
        let request = try screenshot.request()
        let number: Int
        let response: LiveSessionResponse
        let device = LiveSessionDeviceExchange(record: record, store: store, leases: leases, send: deviceSend)
        if let device {
            response = try device.perform(DeviceSessionRequest(action: .read, screenshot: request != nil), timeout: Self.readTimeout, processes: processes, shell: shell, now: now)
            number = response.n
        } else {
            number = try channel.send(.read, screenshot: request != nil)
            do {
                response = try channel.awaitResponse(to: number, timeout: Self.readTimeout, isRunnerAlive: { processes.isRunning(record) }, pause: pause, now: now)
            } catch let error as LiveSessionError {
                throw error.explained(by: store.layout(id: id), testID: SessionStartCommand.testID, shell: shell)
            }
        }
        guard let screen = response.screen else {
            let failure = response.failure ?? "it answered with no screen"
            throw LiveSessionHostError.runnerFailed(number: number, failure: failure + (device?.lockNote(shell: shell).map { "\n\($0)" } ?? ""))
        }
        let screenshotOutcome = request.map { request in
            { (tree: AXNode) in
                ScreenshotOption.outcome(
                    png: response.screenshot,
                    refusal: response.screenshotRefusal,
                    absentReason: "the runner sent no image",
                    tree: tree,
                    request: request,
                    to: store.layout(id: id).screenshot(read: number)
                )
            }
        }
        return try InspectCommand.outcome(runnerFailure: nil, handback: nil, readingScreen: { screen }, match: match, screenshotOutcome: screenshotOutcome)
    }
}
