//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// What `session start` writes about itself while it starts a live session: the progress file's `building` and `launching`, up to the hand-over to the runner (`Docs/SIMWALK-PROGRESS.md` §3, SimWalk#83).
///
/// **The slot goes with the runner.** The claim is taken from slot 2, leaving the session's own `<session>.json` to walks, and to be shared (``ProgressClaim/take(session:in:firstSlot:sharedWithChild:)``), and handed to the spawned `xcodebuild` (``RunnerInvocation/session(layout:logFilePath:runnerCommit:idleOverride:deviceAppearance:progress:on:)``), so it is held for exactly as long as the session lives — past a CLI `start` that exits once the runner is ready, and past the MCP call that started it. From the spawn on, the file's `pid` is that `xcodebuild`'s: its death is the session's, which is what a reader's `pid` rule needs.
///
/// **No backstop on going away**, unlike a walk's ``ProgressRun``: a start that succeeded has handed the file to the runner, whose `running` a backstop would overwrite with `interrupted`. Every way out of the start is a thrown error, which ``fail(_:)`` ends first.
final class SessionStartProgress {
    let writer: ProgressWriter
    /// Kept until this object goes away, after its last write; the spawned runner inherits its own hold on it.
    let claim: ProgressClaim

    /// Begins the session's file in `building`, naming the usage log at `logFileURL` — the directory the file goes beside — and, from here on, ending it `failed` / `cancelled` when `cancellation` is raised.
    ///
    /// The session is `CLAUDE_CODE_SESSION_ID` in `environment`, `default` without one. Its file is `<session>.2.json`, or the next slot when that is held: slot 1 is a walk's, which a session would otherwise hold for its whole life.
    init(environment: [String: String], logFileURL: URL, cancellation: Cancellation?, pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        claim = ProgressClaim.take(session: environment[WalkCommand.sessionVariable], in: logFileURL.deletingLastPathComponent(), firstSlot: Self.firstSlot, sharedWithChild: true)
        writer = ProgressWriter(url: claim.progressURL, clock: { Date() }, pid: pid)
        writer.begin(tool: Self.tool, phase: .building, logPath: logFileURL.path)
        cancellation?.onCancel { [writer] in writer.cancel() }
    }

    /// The `tool` a session's file names.
    static var tool: String {
        "session"
    }

    /// The slot a session's claim starts from: slot 1, the session's own name, stays a walk's (SimWalk#83).
    static var firstSlot: Int {
        2
    }

    /// The device the session runs on and the app it drives.
    func resolved(_ simulator: Simulator, app: String) {
        writer.commit { progress in
            progress.device = WalkProgress.Device(name: simulator.name, udid: simulator.udid, osVersion: simulator.osVersion)
            progress.app = app
        }
    }

    /// The runner is built: from here to the runner's `running`, the device is read and settled and the runner launched.
    func launching() {
        writer.commit { $0.phase = .launching }
    }

    /// The runner is spawned as `pid`, which the file names from now on, holding the claim's lock from here on.
    func spawned(_ pid: Int32) {
        claim.markHandedOver()
        writer.commit { $0.pid = pid }
    }

    /// Ends the start as `failed` with the text of what escaped it.
    func fail(_ error: Error) {
        writer.finish(.failed, error: String(describing: error))
    }
}
