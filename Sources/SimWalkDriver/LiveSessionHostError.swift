//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a live session could not be started, found or read, on the host's side of the channel.
public enum LiveSessionHostError: Error, Equatable, CustomStringConvertible {
    case unknownSession(id: String)
    case alreadyRunning(udid: String, id: String, pid: Int32)
    /// Another `session start` (process `holder`) holds the device's claim: it is building, settling or spawning, and has no record yet.
    case startInProgress(udid: String, holder: Int32)
    /// The device must be named by UDID or taken by lease: a session holds it for up to the idle timeout.
    case deviceNotOwned(requested: String, udid: String)
    case notBooted(name: String, udid: String)
    /// The runner stopped, or never said it was ready; `lines` are the end procedure's and the diagnosis's.
    case neverReady(reason: String, lines: [String])
    /// The runner answered a request with a failure of its own.
    case runnerFailed(number: Int, failure: String)
    case unreadableState(reason: String)
    /// A state asked for an appearance the device was not in, and rebooting the device into it (`DeviceSettle`) stopped at `step`, so nothing was started.
    ///
    /// `command` is the whole settle as a person runs it.
    case settleFailed(udid: String, theme: Walkbook.Theme, step: String, reason: String, command: String)
    /// `--team` or `--runner-bundle-id` on a session whose device is a simulator: both are a physical device's (SimWalk#116).
    case deviceOnly(flag: String)
    /// A `--state` asking for what a physical device cannot be given (`DeviceTargetSupport`), one line per key.
    case unsupportedOnDevice(lines: [String])
    /// A device session whose record has no address yet: `session start` has not got the runner to answer.
    case deviceNotReady(id: String)
    /// The session's lease on its phone could not be renewed, so no request was sent.
    case deviceLeaseNotRenewed(id: String, udid: String, reason: String)
    /// The token a device session authenticates with could not be read from its directory.
    case deviceTokenUnreadable(path: String, reason: String)
    /// A device session's runner has stopped, so nothing was sent; `exit` is the runner's own record, copied back from the phone, `nil` when it left none.
    ///
    /// `lockNote` is the line a locked phone adds (one `lockState` read), as a failed `read` or `step` adds it: a runner that exited because the phone locked says only `kAXErrorServerNotFound`.
    case deviceRunnerStopped(id: String, exit: LiveSessionExit?, lockNote: String? = nil)
    /// A device start cancelled (a Ctrl-C, a SIGTERM, an MCP client's cancel): before its runner was spawned, nothing was started on `udid` and `lines` is empty; while it waited for the runner's `hello`, the device stop ran and `lines` is its report (SimWalk#127).
    ///
    /// Either way a lease the start took is released, and no session is left for a caller that will never learn its id.
    case startCancelled(udid: String, lines: [String] = [])

    public var description: String {
        switch self {
        case let .deviceNotReady(id):
            "session \(id) is not ready: its runner has not answered `hello`, so it has no address — `simwalk session list` shows whether it is still starting"
        case let .deviceLeaseNotRenewed(id, udid, reason):
            "session \(id)'s lease on \(udid) could not be renewed (\(reason)), so nothing was sent — end the session (`simwalk session end \(id)`) and start again"
        case let .deviceTokenUnreadable(path, reason):
            "the session's token could not be read from \(path): \(reason)"
        case let .deviceRunnerStopped(id, exit, lockNote):
            "session \(id)'s runner has stopped, so nothing was sent: \(exit?.summary ?? "it left no exit record") — end the session (`simwalk session end \(id)`) and start again" + (lockNote.map { "\n\($0)" } ?? "")
        case let .startCancelled(udid, lines) where lines.isEmpty:
            "the session start on \(udid) was cancelled before its runner was started: nothing runs on the device, and a lease the start took is released"
        case let .startCancelled(udid, lines):
            (["the session start on \(udid) was cancelled while its runner started: the runner was stopped and the device handed back"] + lines).joined(separator: "\n  ")
        case let .unknownSession(id):
            "no live session \(id) — `simwalk session list` shows the machine's sessions"
        case let .alreadyRunning(udid, id, pid):
            "\(udid) already has a live session, \(id) (runner pid \(pid)) — read it with `simwalk session read \(id)`, or end it with `simwalk session end \(id)`"
        case let .startInProgress(udid, holder):
            "another `simwalk session start` (pid \(holder)) is starting a session on \(udid) — nothing was built or settled; `simwalk session list` shows its session once it is ready"
        case let .deviceNotOwned(requested, udid):
            "\(requested) names a device by name; a session holds its device, so name it by UDID (--device \(udid)) or take a lease (`simwalk lease acquire`)"
        case let .notBooted(name, udid):
            "\(name) (\(udid)) is not booted — a session never boots one; boot it first (xcrun simctl boot \(udid))"
        case let .neverReady(reason, lines):
            (["the session's runner never became ready: \(reason)"] + lines).joined(separator: "\n  ")
        case let .runnerFailed(number, failure):
            "the session's runner could not serve request \(number): \(failure)"
        case let .unreadableState(reason):
            "--state is not a capture state: \(reason)"
        case let .settleFailed(udid, theme, step, reason, command):
            "the state is \(theme.rawValue) and \(udid) was not, so the session settles it first — and settling it failed \(step) (\(reason)), so no session was started; settle it by hand, then start again: \(command)"
        case let .deviceOnly(flag):
            "\(flag) is a physical device's: it names the signing team or the runner an iPhone or iPad is built under, and this session is on a simulator — drop it, or pass --device <physical udid>"
        case let .unsupportedOnDevice(lines):
            (["--state asks for what a physical device cannot be given, so no session was started (SimWalk#116):"] + lines.map { "  - \($0)" }).joined(separator: "\n")
        }
    }
}

extension LiveSessionHostError: UsageFailureClassifiable {
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .unknownSession, .deviceNotReady, .deviceLeaseNotRenewed, .alreadyRunning, .startInProgress, .deviceNotOwned, .notBooted, .unreadableState, .deviceOnly, .unsupportedOnDevice, .startCancelled: .inputRefused
        case .neverReady, .runnerFailed, .deviceTokenUnreadable, .deviceRunnerStopped: .runnerFailed
        case .settleFailed: .deviceLeftBad
        }
    }
}
