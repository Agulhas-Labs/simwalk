//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk session end <id>` — stops the session's runner, hands the device back and removes the session, saying every step it took: ``LiveSessionDeviceStop`` for a physical device's session, ``LiveSessionStop`` for a simulator's.
struct SessionEndCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "end",
        abstract: "End a live session — or clean up one whose runner has already exited."
    )

    @Argument(help: "The session id `session start` printed.")
    var id: String

    func run() throws {
        try TimedCall.run(tool: "session end", target: id, defaultFailureKind: .runnerFailed) {
            try perform()
        }
    }

    func perform(
        store: LiveSessionStore = .standard(),
        processes: any LiveSessionProcesses = LiveSessionSystemProcesses(),
        leases: LeaseStore = .standard(),
        shell: Shell = Shell(),
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: () -> Date = { Date() }
    ) throws -> Answer {
        guard let record = store.record(id: id) else {
            throw LiveSessionHostError.unknownSession(id: id)
        }
        let header = "live session: \(id)  app: \(record.app)"
        if let stop = LiveSessionDeviceStop(record: record, store: store, processes: processes, leases: leases) {
            let report = stop.perform(shell: shell, pause: pause, now: now)
            return Answer(header: header, verdict: .reporting(qualifications: report.qualifications, detail: "ended session \(id)"), residue: report.lines)
        }
        let report = LiveSessionStop(record: record, store: store, processes: processes, isDeviceBusy: { now in
            // Another holder's walk or start is on the device; this session's own record is not another holder.
            LiveSessionAccessibilityHandback.isHeldByAnother(udid: record.udid, session: (record.id, record.leaseToken), store: store, processes: processes, leases: leases, now: now)
        })
        .perform(run: { try shell.run($0, $1) }, pause: pause, now: now)
        return Answer(
            header: header,
            verdict: .reporting(qualifications: report.qualifications, detail: "ended session \(id)"),
            residue: report.lines
        )
    }
}
