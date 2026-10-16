//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// The runner's exit record, fetched from the phone for `read`, `step`, `list` and `end` (Brief, "Live sessions on a physical device", ruling 6): a host that finds the runner gone copies `exit.json` back once, so `end`, `read` and `list` give the same reason a simulator session would.
///
/// **Once** is the file's presence: a copy that succeeded leaves `exit.json` in the session directory, and every later command answers from it without another `devicectl` call. A copy that failed leaves nothing, so the next command tries again.
///
/// **Only this session's record is kept**: the container path is the same for every session and no runner clears an old record when it starts, so the copy may be another run's (SimWalk#116). It is read from a scratch directory of its own and moved into the session directory only when its `session` is this session's id.
public struct LiveSessionDeviceExit {
    /// The runner's exit record for `record`'s session: the one already in the session directory, else the one copied back from the runner's container; `nil` when the runner left none to read.
    public static func recorded(record: LiveSessionRecord, layout: LiveSessionLayout, shell: Shell) -> LiveSessionExit? {
        fetch(record: record, layout: layout, shell: shell).exit
    }

    /// ``recorded(record:layout:shell:)`` with the step line saying how the record was come by.
    public static func fetch(record: LiveSessionRecord, layout: LiveSessionLayout, shell: Shell) -> Fetch {
        let channel = LiveSessionChannel(layout: layout)
        if let exit = try? channel.exitRecord() {
            return Fetch(exit: exit, line: "exit.json was already copied back")
        }
        guard let endpoint = record.device, !FileManager.default.fileExists(atPath: layout.exit.path) else {
            return Fetch(exit: nil, line: "exit.json was already copied back")
        }
        let scratch = layout.directory.appendingPathComponent("exit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let container = RunnerInvocation.deviceContainerBundleID(runnerBundleID: endpoint.runnerBundleID)
        let copied: LiveSessionExit?
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
            let source = "\(LiveSessionRecord.DeviceEndpoint.containerSessionPath)/exit.json"
            let destination = LiveSessionLayout(directory: scratch)
            try DevicectlContainerCopy(udid: record.udid, containerBundleID: container, shell: shell).copy(source: source, to: destination.exit)
            copied = try LiveSessionChannel(layout: destination).exitRecord()
        } catch {
            return Fetch(exit: nil, line: "exit.json not copied back from the runner's container: \(error)")
        }
        guard let copied, copied.session == record.id else {
            return Fetch(exit: nil, line: "the runner's container held another run's exit record — ignored")
        }
        do {
            try FileManager.default.moveItem(at: LiveSessionLayout(directory: scratch).exit, to: layout.exit)
        } catch {
            return Fetch(exit: nil, line: "exit.json not copied back from the runner's container: \(error)")
        }
        return Fetch(exit: copied, line: "copied exit.json back from the runner's container")
    }
}

public extension LiveSessionDeviceExit {
    /// What a fetch found, with the line `end` files for it.
    struct Fetch {
        public let exit: LiveSessionExit?
        public let line: String
    }
}
