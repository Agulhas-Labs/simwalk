//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk session list` — every session on the machine, running or not; one whose runner has exited says so, and why when it left a record.
///
/// A running device session has its lease renewed here, as every session command renews it; a lease that cannot be renewed is reported on the session's own line and the listing goes on.
///
/// A device session whose runner has stopped has its `exit.json` copied back from the phone once, so it gives the reason `end` gives.
///
/// A session whose runner stopped without `end` has its device's accessibility switched back on here, once (``LiveSessionAccessibilityHandback``): the XCUITest teardown switched it off after the runner's last line, and nothing else on the host runs after an idle exit.
struct SessionListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the machine's live sessions, running and exited; switch accessibility back on for one that stopped without `end`."
    )

    func run() throws {
        try TimedCall.run(tool: "session list", target: nil, defaultFailureKind: .toolError) {
            Self.answer(store: .standard(), processes: LiveSessionSystemProcesses())
        }
    }

    static func answer(
        store: LiveSessionStore,
        processes: any LiveSessionProcesses,
        leases: LeaseStore = .standard(),
        shell: Shell = Shell(),
        pause: (TimeInterval) -> Void = Thread.sleep(forTimeInterval:),
        now: () -> Date = { Date() }
    ) -> Answer {
        let handbacks = LiveSessionAccessibilityHandback.perform(store: store, processes: processes, leases: leases, run: { try shell.run($0, $1) }, pause: pause, now: now)
        var running = 0
        let entries = store.all()
        let lines = entries.flatMap { entry in
            guard let record = entry.record else {
                return ["\(entry.id) · no readable session.json — remove \(store.layout(id: entry.id).directory.path.tildedPath)"]
            }
            let layout = store.layout(id: entry.id)
            var exit = try? LiveSessionChannel(layout: layout).exitRecord()
            let head = "\(entry.id) · \(record.app) · \(record.udid)" + (record.device == nil ? "" : " · device")
            if processes.isRunning(record), exit == nil {
                running += 1
                // `list` reads every session on the machine and renews none: renewing here would keep another agent's idle lease alive (Brief, ruling 8).
                return ["\(head) · running (pid \(record.pid))"]
            }
            if record.device != nil, exit == nil, !processes.isRunning(record) {
                exit = LiveSessionDeviceExit.recorded(record: record, layout: layout, shell: shell)
            }
            let reused = processes.reuse(of: record).map { "pid \(record.pid) is running but is not this session's runner: \($0)" }
            let why = exit.map(\.summary) ?? reused ?? "pid \(record.pid) is gone"
            let handback = handbacks[entry.id].map { ["\(entry.id) · \(LiveSessionAccessibilityHandback.line($0))"] } ?? []
            return ["\(head) · exited: \(why) — `simwalk session end \(entry.id)` cleans it up"] + handback
        }
        var qualifications: [String] = []
        for qualification in handbacks.values.sorted(by: { $0.udid < $1.udid }).compactMap(\.qualification) where !qualifications.contains(qualification) {
            qualifications.append(qualification)
        }
        return Answer(
            header: "sessions: \(store.directory.path.tildedPath)",
            verdict: .reporting(qualifications: qualifications, detail: entries.isEmpty ? "no sessions" : "\(entries.count) session\(entries.count == 1 ? "" : "s"), \(running) running"),
            residue: lines
        )
    }
}
