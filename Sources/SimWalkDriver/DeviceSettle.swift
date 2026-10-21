//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Makes an appearance the device reported and did not draw hold: set it dark, shut the device down, boot it, and put back the appearance the walk found it in (SimWalk#26).
///
/// **The one remedy measured to work, and only that one.** Three sightings in three days — a device just switched, a device created fresh whose appearance was never set, and a third builder's — each drew light under a `dark` that `simctl ui` reported set, and each was cured for good by one `appearance dark` and a reboot outside the walk; every dark state after it captured correctly, the runner switching back and forth per state as always. So the device is always booted with `dark` set (`AppearanceRetry.bootAppearance`), whatever it was found in: round 1 booted a device found dark in `light` and switched it to dark afterwards, which is the sequence sighting 2's trap followed rather than its cure. A device found light is put back to light after the boot; a device found dark is already where it was found, and nothing is switched after the boot at all — the appearance is only read back.
///
/// **Only the walk's own device, and only between two passes.** The runner is an XCUITest session on the device and a reboot ends it, so this runs on the host after one runner has finished and before the next starts. Every step goes through `simctl` with the walk's own UDID; nothing here names another device.
///
/// **Every step is bounded** (`stepTimeout`). A boot that wedged in the middle of a walk would otherwise hold the walk forever; bounded, it stops the settle at that step, which ends the walk as any other failed settle does — the first attempt standing, the verdict qualified, and the command that boots the device on the answer.
public struct DeviceSettle {
    /// How long any one step of the settle may run before it is stopped and the settle ends there, in seconds.
    ///
    /// A bound on a wedge, not a timer anything waits out: a reboot of a simulator that has booted before measured tens of seconds, and nothing in a settle is expected to come near this.
    public static let stepTimeout: TimeInterval = 300

    /// How long each call the handback makes may run after a settle that stopped short, in seconds.
    ///
    /// **A settle that failed at the shutdown, the boot or the wait for it leaves a device that may be down or wedged mid-boot, and the handback's calls go to it next** (the round-2 review). A healthy device answers `simctl ui` and `simctl spawn … defaults` in well under a second, so this bounds a wedge without being a timer anything waits out: a wedged device costs the handback a few of these — the reset read, an accessibility read and write, the appearance write — and ends as a handback that could not put things back, its commands printed, rather than a walk that never answers.
    public static let handbackBound: TimeInterval = 15

    /// Settles `udid` through `dark` and back to `found`, stopping at the first step that fails or outlives `stepTimeout`.
    ///
    /// `run` takes each command's bound as its third argument. A device that is already booted when asked to boot is what was wanted — `Simulator.boot` reads it the same way.
    public static func perform(udid: String, found: Walkbook.Theme, run: (String, [String], TimeInterval) throws -> Shell.Result) -> Outcome {
        settle(udid: udid, found: found) { try run($0, $1, stepTimeout) }
    }

    /// Whether a settle may reboot `simulator`: only a device the walk was given by its UDID, or one this walk booted itself.
    ///
    /// **A reboot is not a walk's to make on somebody else's device** (the round-2 review). With no device named, a walk takes the first booted simulator it finds, and with a name it prefers a booted device of that name — the right default for walking, since booting a second device while one sits ready is a surprise, and the wrong one for rebooting: a device found booted may be another session's, and a settle ends its XCUITest session, its `log stream` and its status-bar override. A device named by UDID was chosen, and one that was shut down when the walk resolved it was nobody's in use then; either is the walk's to reboot. Any other keeps its refusals, and the walk records and prints the settle for a person to run (`command(udid:found:)`).
    ///
    /// `isBooted` is read when the device was resolved, before this walk booted anything — which is what makes it mean "somebody else had it up".
    ///
    /// **A device walked under its lease (`--lease`) is the walk's by construction**: no walk without the token takes it, so nothing of anybody else's is on it (Brief §2.4). Without `--lease`, the walk takes a lease of its own on the device it resolved (`WalkLease.take`), so that device is held against every simwalk session for the whole walk — but not against a session that takes no leases at all (`xcodebuild`, a person at the simulator), so this implicit lease grants no reboot: ownership is judged once, at resolution (the round-3 review), from whether the device was found booted, and a UDID another session is using is rebooted by contract — naming a device by UDID is the caller's word that it is theirs to reboot.
    public static func mayReboot(_ simulator: Simulator, requested: String?, leased: Bool) -> Bool {
        leased || requested == simulator.udid || !simulator.isBooted
    }

    /// The whole settle as a person runs it on `udid` — for a device the walk would not reboot itself — generated from the steps a settle runs, so the instruction cannot drift from what the tool would have done.
    public static func command(udid: String, found: Walkbook.Theme) -> String {
        let putBack = found == AppearanceRetry.bootAppearance ? [] : [Step.putBack(found)]
        return (rebootSteps + putBack).map { "xcrun \($0.arguments(udid: udid).joined(separator: " "))" }.joined(separator: " && ")
    }

    /// The steps that reboot the device dark, in order — what every settle runs before it puts the found appearance back.
    private static var rebootSteps: [Step] {
        [.set(AppearanceRetry.bootAppearance), .shutdown, .boot, .bootStatus]
    }

    /// The settle itself, every command already bounded.
    private static func settle(udid: String, found: Walkbook.Theme, run bounded: (String, [String]) throws -> Shell.Result) -> Outcome {
        for step in rebootSteps {
            let result: Shell.Result
            do {
                result = try bounded(xcrun, step.arguments(udid: udid))
            } catch {
                return .failed(step, reason: "\(error)")
            }
            // A boot whose output was cut short cannot say whether the device was already booted, so it goes on to the
            // wait, which boots a device that is not and is judged by its status alone (SimWalk#30).
            guard result.succeeded || (step == .boot && (result.failureLine.contains("Booted") || result.truncated)) else {
                // `failureLine` is stderr's last line or stdout's tail — and a truncated result may have neither
                // yet, so a cut-short failure says that plainly rather than printing an empty reason (SimWalk#32).
                let reason = result.truncated || result.failureLine.isEmpty ? "output cut short" : result.failureLine
                return .failed(step, reason: reason)
            }
        }
        // The runner resets to `found` before every state and the state check keeps a light capture partly on
        // the strength of it, so a device left in another appearance would walk the second pass on a premise the
        // first did not share. Put back and read back where the boot changed it; read back alone where it did not.
        guard found != AppearanceRetry.bootAppearance else {
            let reading: DeviceAppearance.Reading
            do {
                reading = try DeviceAppearance.reading(udid: udid, run: bounded)
            } catch {
                return .failed(.readBack(found), reason: "\(error)")
            }
            switch reading {
            case .reported(found):
                return .settled
            case .cutShort:
                return .failed(.readBack(found), reason: "reading it back was cut short, so nothing confirms it")
            case .failed:
                return .failed(.readBack(found), reason: "reading it back failed, so nothing confirms it")
            case let .reported(read):
                return .failed(.readBack(found), reason: "it read back as \(read?.rawValue ?? "nothing")")
            }
        }
        // Unconfirmed stops the settle as the read-back-only branch above does: the next pass needs the appearance known, not probable (SimWalk#30).
        return switch DeviceAppearance.restore(found, udid: udid, run: bounded) {
        case .restored, .unknown:
            .settled
        case let .failed(_, reason), let .unconfirmed(_, reason):
            .failed(.putBack(found), reason: reason)
        case .leftToAnotherHolder:
            .failed(.putBack(found), reason: "another holder took the device")
        }
    }

    private static var xcrun: String {
        "/usr/bin/xcrun"
    }
}

public extension DeviceSettle {
    /// One step of the settle, in the order they run.
    enum Step: Equatable, Sendable {
        /// `simctl ui <udid> appearance dark` — the appearance the one measured cure boots the device in.
        case set(Walkbook.Theme)
        /// `simctl shutdown <udid>`.
        case shutdown
        /// `simctl boot <udid>`.
        case boot
        /// `simctl bootstatus <udid> -b` — until the device is usable, which a runner launch needs.
        case bootStatus
        /// The found appearance set again and read back — for a device found in another appearance than the one it was booted in.
        case putBack(Walkbook.Theme)
        /// The appearance read back after the boot — for a device found in the one it was booted in, where nothing is switched.
        case readBack(Walkbook.Theme)

        /// The `simctl` arguments this step runs.
        public func arguments(udid: String) -> [String] {
            switch self {
            case let .set(theme), let .putBack(theme):
                DeviceAppearance.setArguments(theme, udid: udid)
            case .readBack:
                DeviceAppearance.readArguments(udid: udid)
            case .shutdown:
                ["simctl", "shutdown", udid]
            case .boot:
                ["simctl", "boot", udid]
            case .bootStatus:
                ["simctl", "bootstatus", udid, "-b"]
            }
        }

        /// What a person runs to leave the device usable after this step failed, or `nil` when nothing it did needs undoing.
        ///
        /// Failing to set changes nothing. From the shutdown on the device may be down, and a failed put-back or read-back leaves it in an appearance nobody confirmed — the handback will try the found one again, but the line says what finishes the job either way.
        public func remedy(udid: String) -> String? {
            switch self {
            case .set:
                nil
            case .shutdown, .boot, .bootStatus:
                "xcrun simctl boot \(udid)"
            case let .putBack(theme), let .readBack(theme):
                DeviceAppearance.command(theme, udid: udid)
            }
        }

        /// The step as a reader names it.
        public var name: String {
            switch self {
            case let .set(theme): "setting it \(theme.rawValue)"
            case .shutdown: "shutting it down"
            case .boot: "booting it"
            case .bootStatus: "waiting for it to finish booting"
            case let .putBack(theme): "putting it back to \(theme.rawValue)"
            case let .readBack(theme): "reading it back as \(theme.rawValue)"
            }
        }
    }

    /// What the settle came to.
    enum Outcome: Equatable, Sendable {
        /// Every step ran and the found appearance read back.
        case settled
        /// A step failed and the ones after it did not run; the payload is which, and what `simctl` said.
        case failed(Step, reason: String)

        /// The line printed under a walk's answer when the settle did not complete, or `nil` when it did — a completed one is in the manifest.
        public func note(udid: String) -> String? {
            guard case let .failed(step, reason) = self else { return nil }
            let remedy = step.remedy(udid: udid).map { " — run: \($0)" } ?? ""
            return "appearance settle: screens had a state refused on appearance on \(udid), and settling the device failed \(step.name) (\(reason)), so they were not walked again and their refusals stand\(remedy)"
        }

        /// The command that leaves the device usable after the settle stopped short, as a line under the answer — or `nil` when it completed or stopped where nothing needs undoing.
        ///
        /// What happened is in the manifest (`appearanceSettle.settleFailure`); this is the half a file read later cannot carry — the device's UDID and what to run on it now.
        public func remedyNote(udid: String) -> String? {
            guard case let .failed(step, _) = self, let remedy = step.remedy(udid: udid) else { return nil }
            return "appearance settle: the settle stopped \(step.name), so \(udid) may not be as the walk found it — run: \(remedy)"
        }

        /// What this qualifies the walk's answer by, or `nil` when the settle completed.
        ///
        /// A step not taken is a qualification, not a silent skip: the walk meant to recover these screens and did not, and the device may not be where the walk found it.
        public var qualification: String? {
            guard case .failed = self else { return nil }
            return "an appearance settle that did not complete"
        }
    }
}
