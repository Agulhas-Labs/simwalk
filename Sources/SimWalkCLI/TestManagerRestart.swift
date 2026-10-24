//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// Restarts `testmanagerd` on a walked device whose walk recorded a timed-out Apple audit (SimWalk#173).
///
/// **XCTest's audit timeout stops the wait, not the audit**: the device's `testmanagerd` goes on computing it (contrast detection, about a core for each timed-out audit) for as long as the device stays booted. Killing it ends that, and launchd starts it again on demand for the next test session. Run after the device's last runner and before its lease and claim are given back, so only on a device the walk still holds, and only when one of its passes recorded a timeout.
struct TestManagerRestart {
    /// The service as `launchctl` inside the simulator names it, in the `user/foreground` domain `launchctl` asks for over `system/` (measured on iOS 27.0).
    static var service: String {
        "user/foreground/com.apple.testmanagerd"
    }

    /// `launchctl`'s exit status when the service has no process to signal (`ESRCH`): the timed-out audit's work has already ended with it, so nothing is left to stop.
    static let notRunning: Int32 = 3

    /// The bound on the restart's one call.
    static let bound: TimeInterval = 20

    /// How many screens the note names before it counts the rest.
    static let screensNamed = 3

    /// The timed-out audits the bundle `read` returned records, in manifest order; when its manifest is absent or cannot be decoded, those whose records are on disk under `directory`, the pass's output, in path order; none for any other refusal.
    ///
    /// Read when the pass's bundle is: an appearance retry's fold rewrites the bundle, and can replace a timed-out capture with one whose audit returned. **A bundle that cannot be read still holds its records** (SimWalk#190): a runner stopped or crashed after an audit timed out never finalised the manifest, and the device is still computing the audit, so the directory is read as it is when the pass ended. **Only a manifest that was never written or was torn off** (SimWalk#193): a manifest that reads and is refused as another walk's, another build's or another format's proves the records beside it are not this walk's, and restarting this device for them would stop work its own audits never started.
    static func timeouts(in read: Result<CaptureBundle, any Error>, orRecordedIn directory: URL) -> [AppleAuditScan.Failure] {
        switch read {
        case let .success(bundle):
            AppleAuditScan(bundle).timeouts
        case let .failure(error):
            leavesRecordsToRead(error) ? AppleAuditScan.timeouts(recordedIn: directory) : []
        }
    }

    /// Whether a bundle refused for `error` is one whose records are read from disk: its manifest is missing, unreadable or malformed, as a runner stopped before it finalised one leaves it.
    ///
    /// **A same-output race remains** (SimWalk#195): two walks started at once on the same empty `--output` both pass `requireFresh`; when A's runner has not yet finalised its manifest and B's crashes, B finds `manifestMissing` and reads A's records. Narrower than before SimWalk#193, which let any walk's records through.
    private static func leavesRecordsToRead(_ error: any Error) -> Bool {
        switch error as? CaptureBundleError {
        case .manifestMissing, .manifestUnreadable, .manifestMalformed:
            true
        default:
            false
        }
    }

    /// Restarts `testmanagerd` on `simulator` when any of `passes` records a timed-out audit, answering the walk's note on them; `nil`, having run nothing, when none does.
    ///
    /// The note lists each screen and state once, the first pass's first, each pass in manifest order. `shell` is one only the walk's interruption stops. A restart that fails is said in the note and changes nothing else.
    static func afterTimeouts(_ passes: [[AppleAuditScan.Failure]], on simulator: Simulator, shell: Shell) -> String? {
        var timeouts: [AppleAuditScan.Failure] = []
        for timeout in passes.joined() where !timeouts.contains(where: { $0.screenID == timeout.screenID && $0.stateSlug == timeout.stateSlug }) {
            timeouts.append(timeout)
        }
        guard !timeouts.isEmpty else { return nil }
        let head = "apple audit: \(timeouts.count) audit\(timeouts.count == 1 ? "" : "s") timed out (\(described(timeouts))); testmanagerd on \(simulator.name)"
        let failure: String
        do {
            let result = try shell.run("/usr/bin/xcrun", ["simctl", "spawn", simulator.udid, "launchctl", "kill", "SIGKILL", service], timeout: bound)
            guard !result.succeeded else {
                return head + " was restarted, since it keeps computing a timed-out audit until it stops"
            }
            guard result.status != notRunning else {
                return head + " had already stopped, so nothing was left computing it"
            }
            failure = result.failureLine
        } catch {
            failure = "\(error)".split(separator: "\n").first.map(String.init) ?? "\(error)"
        }
        return head + " could not be restarted (\(failure)); it may keep a core busy until the device shuts down"
    }

    /// The timed-out states by screen, in manifest order: `screen [state, state]`, the first ``screensNamed`` screens and a count of the rest.
    static func described(_ timeouts: [AppleAuditScan.Failure]) -> String {
        var screens: [(id: String, states: [String])] = []
        for timeout in timeouts {
            if let index = screens.firstIndex(where: { $0.id == timeout.screenID }) {
                screens[index].states.append(timeout.stateSlug)
            } else {
                screens.append((timeout.screenID, [timeout.stateSlug]))
            }
        }
        let named = screens.prefix(screensNamed).map { "\($0.id) [\($0.states.joined(separator: ", "))]" }
        let rest = screens.count - named.count
        return named.joined(separator: ", ") + (rest > 0 ? " and \(rest) more screen\(rest == 1 ? "" : "s")" : "")
    }
}
