//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// A walkbook's `setup`, made on the device with `simctl` before the runner starts and handed back after it.
///
/// **Every change is put back, named, and judged by what reads back (SimWalk#63).** The status bar override is cleared and `simctl status_bar list` read again; an override the device had before the walk is read first and said, since the clear takes it too. Increase Contrast is read first, put back to what was read, and read again. A privacy service is reset, not restored — `simctl` cannot read a grant, so the app is asked again on next use, as a state's `resetPermissions` leaves it — and a reset nothing can read back is a handback not confirmed, which qualifies a walk and is printed under a dry run.
public struct DeviceSetup {
    /// Makes `setup` on `udid` for `bundleID`, in order: privacy, status bar, Increase Contrast.
    ///
    /// **A step that fails is a refusal before the runner runs**, naming the command; whatever earlier steps changed is handed back first, and the refusal carries that too.
    ///
    /// **A record another walk left on the device is settled first** (SimWalk#72, ``DeviceSetupJournal/claim(udid:run:)``): handed back when its walk is gone, and said in what this returns; a refusal, before any change, when its walk still runs or its handback failed.
    ///
    /// **Then each change is in `journal` before the step that makes it** (SimWalk#63), so a walk killed at any point after — mid-step included — leaves a record naming it, which the next walk to make a setup on the device hands back. A change that cannot be recorded is not made.
    public static func apply(_ setup: Walkbook.Setup, udid: String, bundleID: String, journal: DeviceSetupJournal, run: (String, [String]) throws -> Shell.Result) throws -> Made {
        var applied = Applied()
        var leftover: DeviceSetupJournal.Leftover?
        // What is about to have been made, recorded before the step that makes it; `applied` only once the step ran.
        func make(_ intent: Applied, by arguments: [String]) throws {
            try journal.record(intent, udid: udid, bundleID: bundleID)
            try step(arguments, run: run)
            applied = intent
        }
        do {
            leftover = try journal.claim(udid: udid, run: run, leaseLapsed: false)
            for (action, services) in [("grant", setup.privacy?.grant ?? []), ("revoke", setup.privacy?.revoke ?? [])] {
                for service in services {
                    var intent = applied
                    intent.privacy.append(Change(action: action, service: service))
                    try make(intent, by: ["simctl", "privacy", udid, action, service, bundleID])
                }
            }
            if setup.statusBar == .clean {
                let list = statusBarListArguments(udid: udid)
                let listing = try step(list, run: run).standardOutput
                guard let found = statusBarOverrides(in: listing) else {
                    throw DeviceSetupError.stepFailed(command: command(list), reason: "it printed '\(listing.trimmingCharacters(in: .whitespacesAndNewlines))', which is not a listing of overrides, so what the clear afterwards would take cannot be said", handback: [])
                }
                var intent = applied
                intent.statusBar = true
                intent.statusBarFound = found
                try make(intent, by: statusBarArguments(udid: udid))
            }
            if setup.increaseContrast == true {
                let read = try step(["simctl", "ui", udid, "increase_contrast"], run: run).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                guard ["enabled", "disabled"].contains(read) else {
                    throw DeviceSetupError.stepFailed(command: command(["simctl", "ui", udid, "increase_contrast"]), reason: "it printed '\(read)', so there is no prior value to hand back", handback: [])
                }
                var intent = applied
                intent.increaseContrastFound = read
                try make(intent, by: ["simctl", "ui", udid, "increase_contrast", "enabled"])
            }
        } catch let error as DeviceSetupError {
            throw error.handingBack((leftover?.lines ?? []) + handBack(applied, udid: udid, bundleID: bundleID, journal: journal, run: run).lines)
        }
        return Made(applied: applied, leftover: leftover)
    }

    /// What a walk that makes no setup does with a record another walk left on `udid`, before its runner (SimWalk#73): `nil` when there is none.
    ///
    /// Without this a walk killed mid-setup left its Increase Contrast or revoked grant for the next walk without a setup to capture under, unsaid. **Every walk settles the record**, so a leftover is either handed back or qualifies the walk. Handed back as a setup walk's claim hands it back — its walk gone, and the device `owned` by this walk, since a handback changes device-wide state as a setup does. Left in place and said, never refused, when its walk still runs (the device is that walk's until it hands back) or this walk does not own the device. A handback that fails refuses, as a setup walk's does: the walk would capture under the leftover, and the commands to run are printed.
    public static func settleLeftover(udid: String, owned: Bool, leaseLapsed: Bool, journal: DeviceSetupJournal, run: (String, [String]) throws -> Shell.Result) throws -> Made? {
        try journal.claim(udid: udid, run: run, forSetup: false, mayHandBack: owned, leaseLapsed: leaseLapsed).map { Made(applied: Applied(), leftover: $0) }
    }

    /// Sets the status bar override again after a settle rebooted the device, which a `simctl status_bar` override does not survive.
    ///
    /// `nil` when it was set, else why not.
    public static func reapplyStatusBar(_ applied: Applied, udid: String, run: (String, [String]) throws -> Shell.Result) -> String? {
        guard applied.statusBar else { return nil }
        do {
            try step(statusBarArguments(udid: udid), run: run)
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// Puts back everything `applied` names and reads back what it can: each privacy service reset (nothing reads a grant back, so not confirmed), the status bar cleared and listed again, Increase Contrast set to what was read and read again.
    ///
    /// `journal`'s record of the setup is removed once every command ran and read back as it should — and only when this walk wrote it, so one another walk left stays; a command that failed or read back wrong keeps it, for the next walk to make a setup on the device to hand back again.
    public static func handBack(_ applied: Applied, udid: String, bundleID: String, journal: DeviceSetupJournal, run: (String, [String]) throws -> Shell.Result) -> Handback {
        let handback = putBack(applied, udid: udid, bundleID: bundleID, run: run)
        if handback.failed.isEmpty {
            journal.remove(udid: udid)
        }
        return handback
    }

    /// The handback's commands and read-backs, with no record touched — a walk's own handback, and a leftover's (``DeviceSetupJournal/claim(udid:run:)``).
    static func putBack(_ applied: Applied, udid: String, bundleID: String, run: (String, [String]) throws -> Shell.Result) -> Handback {
        var handback = Handback()
        for change in applied.privacy {
            let reset = ["simctl", "privacy", udid, "reset", change.service, bundleID]
            if handback.ran(reset, run: run) {
                handback.unconfirmedResets.append("\(change.service) reset — not confirmed: `simctl` cannot read a grant back, and one the device had before the walk is lost to the reset")
            }
        }
        let clear = ["simctl", "status_bar", udid, "clear"]
        if applied.statusBar, handback.ran(clear, run: run) {
            let listing = (try? run(xcrun, statusBarListArguments(udid: udid))).flatMap { $0.succeeded ? $0.standardOutput : nil }
            switch listing.flatMap(statusBarOverrides(in:)) {
            case .none:
                handback.unconfirmedReads.append("status bar override cleared — not confirmed: `\(command(statusBarListArguments(udid: udid)))` gave no listing of overrides to read back")
            case let .some(left) where !left.isEmpty:
                handback.failed.append("\(command(clear)) (it read back an override still set: \(left.joined(separator: ", ")))")
            case .some where !applied.statusBarFound.isEmpty:
                handback.unconfirmedReads.append("status bar override cleared, read back clear — not as found: the override the device had before the walk (\(applied.statusBarFound.joined(separator: ", "))) is cleared with it, not restored")
            case .some:
                handback.restored.append("status bar override cleared, read back clear")
            }
        }
        if let found = applied.increaseContrastFound, handback.ran(["simctl", "ui", udid, "increase_contrast", found], run: run) {
            let read = (try? run(xcrun, ["simctl", "ui", udid, "increase_contrast"]))?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if read == found {
                handback.restored.append("Increase Contrast put back \(found), read back")
            } else {
                handback.failed.append("\(command(["simctl", "ui", udid, "increase_contrast", found])) (it read back '\(read ?? "nothing")')")
            }
        }
        return handback
    }

    /// The override `statusBar: "clean"` sets — Apple's own screenshot bar.
    public static func statusBarArguments(udid: String) -> [String] {
        ["simctl", "status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"]
    }

    /// What reads the device's status bar overrides, before the setup's and after its handback.
    public static func statusBarListArguments(udid: String) -> [String] {
        ["simctl", "status_bar", udid, "list"]
    }

    /// The overrides a `simctl status_bar … list` names, a line each — empty when there are none; `nil` when `output` is not the listing measured on iOS 27 (a `Current Status Bar Overrides:` header over a rule of `=`, then a line per override), which can then say neither.
    static func statusBarOverrides(in output: String) -> [String]? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 2, lines[0] == "Current Status Bar Overrides:", lines[1].allSatisfy({ $0 == "=" }) else {
            return nil
        }
        return Array(lines.dropFirst(2))
    }

    /// Why a walk with a setup refuses a device it does not own, before touching it.
    public static func notOwned(udid: String) -> String {
        "the walkbook's setup changes device-wide state, and \(udid) was already booted when the walk resolved it and was neither leased to it nor named by UDID, so it may be another session's — take a lease (`simwalk lease acquire --device \(udid)`, then `--lease <token>`) or name it by UDID (`--device \(udid)`)"
    }

    @discardableResult
    private static func step(_ arguments: [String], run: (String, [String]) throws -> Shell.Result) throws -> Shell.Result {
        let result: Shell.Result
        do {
            result = try run(xcrun, arguments)
        } catch {
            throw DeviceSetupError.stepFailed(command: command(arguments), reason: "\(error)", handback: [])
        }
        guard result.succeeded else {
            throw DeviceSetupError.stepFailed(command: command(arguments), reason: result.failureLine, handback: [])
        }
        return result
    }

    static func command(_ arguments: [String]) -> String {
        (["xcrun"] + arguments).joined(separator: " ")
    }

    private static var xcrun: String {
        "/usr/bin/xcrun"
    }
}

public extension DeviceSetup {
    /// One privacy change the setup made.
    struct Change: Codable, Equatable, Sendable {
        public let action: String
        public let service: String
    }

    /// What `apply` made, and a record an earlier walk left that it settled first.
    struct Made: Equatable, Sendable {
        public let applied: Applied
        public let leftover: DeviceSetupJournal.Leftover?
    }

    /// What the setup changed, and so what the handback puts back — and what a walk's ``DeviceSetupJournal`` record holds.
    struct Applied: Codable, Equatable, Sendable {
        public var privacy: [Change] = []
        public var statusBar = false
        /// The overrides `simctl status_bar list` named before the setup's own, a line each — empty when there were none, or the setup did not touch the status bar; the handback's clear takes them too.
        public var statusBarFound: [String] = []
        /// What Increase Contrast read before the setup enabled it; `nil` when the setup did not touch it.
        public var increaseContrastFound: String?

        /// Each change made, in the order made — what the manifest records.
        public var parts: [String] {
            let over = statusBarFound.isEmpty ? "" : " over an override the device already had (\(statusBarFound.joined(separator: ", "))), which the handback clears rather than restores"
            return privacy.map { "privacy \($0.action) \($0.service)" }
                + (statusBar ? ["status bar clean\(over) (set, unverified: the app's tree does not carry SpringBoard's status bar)"] : [])
                + (increaseContrastFound.map { ["\(CaptureManifest.SetupRecord.increaseContrastPrefix), found \($0) (set, unverified: nothing captured reports it)"] } ?? [])
        }

        /// The setup in one line, for the answer and the manifest.
        public var line: String {
            parts.joined(separator: "; ")
        }
    }

    /// What the handback put back and read back as found, what it put back without being able to, and the commands that failed or read back wrong.
    struct Handback: Equatable, Sendable {
        /// Put back and read back as the device was found.
        public var restored: [String] = []
        /// Put back, but not read back as found — each saying why: a privacy reset nothing can read, an override found before the walk that the clear took too.
        public var unconfirmed: [String] {
            unconfirmedResets + unconfirmedReads
        }

        /// Each privacy service reset: run, but nothing reads a grant back.
        public var unconfirmedResets: [String] = []
        /// The status bar cleared but not read back as found — no listing to read, or an override found before the walk that the clear took too.
        public var unconfirmedReads: [String] = []
        /// The commands that could not run or read back wrong, for a person to run.
        public var failed: [String] = []

        /// The lines printed under the answer.
        public var lines: [String] {
            CaptureManifest.SetupRecord.handbackLines(handedBack: restored, unconfirmed: unconfirmed, notHandedBack: failed)
        }

        /// What this qualifies the walk's answer by.
        public var qualifications: [String] {
            qualifications(countingResets: true)
        }

        /// The same, with a privacy reset nothing can read back counted or not — a dry run's are printed, not a qualification.
        public func qualifications(countingResets: Bool) -> [String] {
            (failed.isEmpty ? [] : ["a setup change not handed back"]) + ((countingResets ? unconfirmed : unconfirmedReads).isEmpty ? [] : ["a setup change handed back but not confirmed as found"])
        }

        /// Runs one handback command; a failure is recorded as a command to run, and the caller reads back only after a success.
        mutating func ran(_ arguments: [String], run: (String, [String]) throws -> Shell.Result) -> Bool {
            guard (try? DeviceSetup.step(arguments, run: run)) != nil else {
                failed.append(DeviceSetup.command(arguments))
                return false
            }
            return true
        }
    }

    /// A walk's setup from end to end: what was made, whether the status bar was set again after a settle's reboot, and what the handback put back.
    struct Report: Equatable, Sendable {
        public let applied: Applied
        /// A record an earlier walk left on the device, settled before this setup; `nil` when there was none.
        public let leftover: DeviceSetupJournal.Leftover?
        /// Why the status bar override was not set again after an appearance settle rebooted the device; `nil` when it was, or none did.
        public var statusBarNotReapplied: String?
        public var handback: Handback

        public init(applied: Applied, leftover: DeviceSetupJournal.Leftover? = nil, statusBarNotReapplied: String? = nil, handback: Handback) {
            self.applied = applied
            self.leftover = leftover
            self.statusBarNotReapplied = statusBarNotReapplied
            self.handback = handback
        }

        /// What the manifest records.
        public var record: CaptureManifest.SetupRecord {
            CaptureManifest.SetupRecord(made: applied.parts, statusBarNotReapplied: statusBarNotReapplied, handedBack: handback.restored, unconfirmed: handback.unconfirmed, notHandedBack: handback.failed, leftover: leftover?.lines ?? [])
        }

        /// The lines under an answer that has no manifest to carry the record — a refusal, a dry run, a record that could not be written.
        public var lines: [String] {
            record.lines
        }

        /// What this qualifies the walk's answer by: a change not handed back or not confirmed, a status bar the screens walked again did not have, and a leftover an earlier walk left.
        public var qualifications: [String] {
            qualifications(countingResets: true)
        }

        /// The same, with a privacy reset nothing can read back counted or not — a dry run's are printed, not a qualification (the SimWalk#63 review).
        public func qualifications(countingResets: Bool) -> [String] {
            [leftover?.qualification].compactMap(\.self)
                + handback.qualifications(countingResets: countingResets)
                + [statusBarNotReapplied.map { _ in "a status bar override not set again after the settle" }].compactMap(\.self)
        }
    }
}
