//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore

/// The simulator a walk runs on, and the few things SimWalk asks `simctl` for.
///
/// Deliberately thin. SimWalk orchestrates build/boot/install rather than reimplementing them (Brief §7.5), so this covers exactly what a walk needs to be honest about — which device, is it booted, is the app actually installed, and which binary is installed — and nothing else.
public struct Simulator: Equatable, Sendable {
    /// The device's UDID, which is the identity a fleet lease is taken against (Brief §2.4).
    public let udid: String
    /// The device's model name, as the manifest will record it.
    public let name: String
    /// The OS version it runs.
    public let osVersion: String
    /// Whether it was booted when it was resolved.
    public let isBooted: Bool
    /// The runtime `simctl` lists the device under, such as `com.apple.CoreSimulator.SimRuntime.iOS-27-0`; nil where the device was not read from a device list.
    public let runtimeIdentifier: String?

    public init(udid: String, name: String, osVersion: String, isBooted: Bool, runtimeIdentifier: String? = nil) {
        self.udid = udid
        self.name = name
        self.osVersion = osVersion
        self.isBooted = isBooted
        self.runtimeIdentifier = runtimeIdentifier
    }
}

public extension Simulator {
    /// Every available device, newest runtime first, as `simctl` reports them.
    static func available(shell: Shell = Shell()) throws -> [Simulator] {
        let result = try shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"])
        guard result.succeeded else {
            throw SimulatorError.simctlFailed(command: "list devices", reason: result.failureLine)
        }
        return try parseDevices(Data(result.standardOutput.utf8))
    }

    /// Every device that exists, including one whose runtime is missing, which `available` leaves out: a device on a runtime that was uninstalled still holds its data and may come back, so "does it exist" is a wider question than "can it be walked".
    static func existing(shell: Shell = Shell()) throws -> [Simulator] {
        let result = try shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
        guard result.succeeded else {
            throw SimulatorError.simctlFailed(command: "list devices", reason: result.failureLine)
        }
        return try parseDevices(Data(result.standardOutput.utf8))
    }

    /// Resolves the device a walk should run on: the leased one when a lease token is given, else the one named, or a booted one, or the newest available — never a device another caller holds a lease on (Brief §2.4).
    ///
    /// Preferring an already-booted device when nothing is named is not a convenience — booting takes tens of seconds, and a walk that silently boots a *second* device while one sits ready is the kind of surprise that makes a tool feel unpredictable.
    ///
    /// **A leased device is refused before anything touches it.** With nothing named, leased devices are not candidates at all; named without its token, the refusal names the holder and the expiry. Only `simctl list` has run by then, which changes nothing.
    static func resolve(_ requested: String?, lease token: String? = nil, leases: LeaseStore, now: Date, shell: Shell = Shell()) throws -> Simulator {
        let devices = try available(shell: shell)
        guard !devices.isEmpty else {
            throw SimulatorError.noDevices
        }
        if let token {
            guard let entry = leases.entry(token: token) else {
                throw LeaseError.noSuchLease
            }
            guard entry.lease.expiresAt > now else {
                throw LeaseError.expired(udid: entry.udid, expiresAt: entry.lease.expiresAt)
            }
            guard let device = devices.first(where: { $0.udid == entry.udid }) else {
                throw SimulatorError.noSuchDevice(requested: entry.udid, available: devices.map(\.name))
            }
            return device
        }
        let held = leases.held(now: now)
        guard let requested else {
            let free = devices.filter { held[$0.udid] == nil }
            guard let first = free.first else {
                throw LeaseError.noUnleasedDevice(runtime: "iOS")
            }
            return free.first(where: \.isBooted) ?? first
        }
        let matches = devices.filter { $0.udid == requested || $0.name == requested }
        guard let match = matches.first else {
            throw SimulatorError.noSuchDevice(requested: requested, available: devices.map(\.name))
        }
        let free = matches.filter { held[$0.udid] == nil }
        if let pick = free.first(where: \.isBooted) ?? free.first {
            return pick
        }
        let chosen = matches.first(where: \.isBooted) ?? match
        guard case let .some(.some(lease)) = held[chosen.udid] else {
            throw LeaseError.unreadable(path: leases.url(for: chosen.udid).path)
        }
        throw LeaseError.held(udid: chosen.udid, holderPID: lease.holderPID, expiresAt: lease.expiresAt)
    }

    /// Boots the device if it is not already booted, and waits until it is usable.
    func boot(shell: Shell = Shell()) throws {
        if !isBooted {
            let booted = try shell.run("/usr/bin/xcrun", ["simctl", "boot", udid])
            // Already-booted is reported as a failure by simctl and is not one here; a device someone
            // else booted between resolve and now is exactly the state we wanted.
            guard booted.succeeded || booted.failureLine.contains("Booted") else {
                throw SimulatorError.simctlFailed(command: "boot", reason: booted.failureLine)
            }
        }
        let ready = try shell.run("/usr/bin/xcrun", ["simctl", "bootstatus", udid, "-b"])
        guard ready.succeeded else {
            throw SimulatorError.simctlFailed(command: "bootstatus", reason: ready.failureLine)
        }
    }

    /// Installs an app bundle onto the device.
    func install(appPath: String, shell: Shell = Shell()) throws {
        let result = try shell.run("/usr/bin/xcrun", ["simctl", "install", udid, appPath])
        guard result.succeeded else {
            throw SimulatorError.simctlFailed(command: "install \(appPath)", reason: result.failureLine)
        }
    }

    /// The host path of an installed app's bundle, or `nil` when the app is not installed.
    ///
    /// The host path is readable directly, which is what lets the driver hash the binary it is about to walk rather than trusting a caller's claim about it.
    ///
    /// A non-zero exit is `nil` only when simctl itself says the app is absent — `get_app_container` fails that way with "No such file or directory". Anything else (a CoreSimulator error, another agent shutting the device down between boot and this call, on a machine several walks share) is the machine failing to answer, not a caller naming a bundle ID that is not there, and is thrown as `simctlFailed` rather than read as an absent app.
    func installedAppPath(bundleID: String, shell: Shell = Shell()) throws -> String? {
        let result = try shell.run("/usr/bin/xcrun", ["simctl", "get_app_container", udid, bundleID, "app"])
        guard result.succeeded else {
            guard result.standardError.contains("No such file or directory") else {
                throw SimulatorError.simctlFailed(command: "get_app_container", reason: result.failureLine)
            }
            return nil
        }
        let path = result.standardOutput.trimmed
        return path.isEmpty ? nil : path
    }

    /// When the device booted, as `now` less its `launchd_sim`'s elapsed time in `ps`, or `nil` where that cannot be read — a step's refusal then says nothing of the boot (SimWalk#88).
    ///
    /// **The device's own `launchd_sim`, not `simctl`**: nothing `simctl` lists says when a device booted, and the process starts with the device, so its age is the boot's whether this walk booted the device or found it booted. Read once the device is booted; any failure is `nil`, never a refusal, because the age only chooses a hint's wording.
    func bootedAt(now: Date, shell: Shell = Shell()) -> Date? {
        guard let listing = try? shell.run("/bin/ps", ["-axo", "pid=,etime=,command="]), listing.succeeded,
              let uptime = Self.bootUptime(of: udid, inProcessList: listing.standardOutput)
        else {
            return nil
        }
        return now.addingTimeInterval(-uptime)
    }

    /// How long the `launchd_sim` of the device `udid` has run, in seconds, from `ps -axo pid=,etime=,command=` output; `nil` where no line is that process or its elapsed time does not parse.
    ///
    /// A line reads `84326 04:15 launchd_sim /Users/…/CoreSimulator/Devices/<UDID>/data/var/run/launchd_bootstrap.plist`: the device is matched by `/Devices/<UDID>/` in the command, so another device's `launchd_sim` is never read.
    static func bootUptime(of udid: String, inProcessList listing: String) -> TimeInterval? {
        for line in listing.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3, fields[2] == "launchd_sim" || fields[2].hasSuffix("/launchd_sim"), line.contains("/Devices/\(udid)/") else {
                continue
            }
            return elapsedSeconds(fromEtime: String(fields[1]))
        }
        return nil
    }

    /// `ps`'s `etime`, `[[dd-]hh:]mm:ss`, in seconds; `nil` for anything else.
    static func elapsedSeconds(fromEtime etime: String) -> TimeInterval? {
        let dayAndClock = etime.split(separator: "-", omittingEmptySubsequences: false)
        guard let clockText = dayAndClock.last, dayAndClock.count <= 2, let days = dayAndClock.count == 2 ? Int(dayAndClock[0]) : 0 else {
            return nil
        }
        let fields = clockText.split(separator: ":", omittingEmptySubsequences: false)
        let clock = fields.compactMap { Int($0) }
        let fieldsExpected = dayAndClock.count == 2 ? 3 ... 3 : 2 ... 3
        guard fieldsExpected.contains(fields.count), clock.count == fields.count, days >= 0, clock.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        return TimeInterval(days * 86400 + clock.reduce(0) { $0 * 60 + $1 })
    }

    static func parseDevices(_ json: Data) throws -> [Simulator] {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]]
        else {
            throw SimulatorError.unreadableDeviceList
        }
        // iOS runtimes only. SimWalk walks iOS apps, and `simctl` reports every platform on the machine —
        // with `watchOS` sorting *above* `iOS` as a string, so resolving "the newest available device"
        // across the raw list picked an Apple Watch and then reported every screen unreachable.
        return byRuntime.keys.filter { $0.contains(Self.iOSRuntimeMarker) }.sorted(by: >).flatMap { runtime -> [Simulator] in
            (byRuntime[runtime] ?? []).compactMap { device in
                guard let udid = device["udid"] as? String, let name = device["name"] as? String else { return nil }
                return Simulator(
                    udid: udid,
                    name: name,
                    osVersion: Self.version(fromRuntime: runtime),
                    isBooted: (device["state"] as? String) == "Booted",
                    runtimeIdentifier: runtime
                )
            }
        }
    }

    /// What marks a runtime as one this tool can walk.
    ///
    /// `.iOS-` carries both delimiters deliberately, so no other platform's identifier can match it on a substring.
    static var iOSRuntimeMarker: String {
        ".iOS-"
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-5` → `26.5`.
    static func version(fromRuntime runtime: String) -> String {
        guard let tail = runtime.split(separator: ".").last else { return runtime }
        return tail.split(separator: "-").dropFirst().joined(separator: ".")
    }
}
