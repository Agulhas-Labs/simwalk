//
// Copyright © Agulhas Labs
//

import Foundation

/// The host-side check that a physical iPhone can be walked, run before anything is built (SimWalk#116).
public struct PhysicalDevicePrerequisites {
    /// Returns the device when every prerequisite holds, else throws the first one that does not, by name.
    ///
    /// Checked in order, each its own refusal, and a later command is never run once an earlier one refuses: a signing team was given; the device is among the physical devices `devicectl` lists; it is paired; it is connected; Developer Mode is enabled; it is unlocked.
    ///
    /// **There is no "Enable UI Automation" check**: `devicectl` reports nothing about it, and three walks passed on iOS 27.0.1 with Xcode 27.0 with it off.
    public static func check(udid: String, team: String?, shell: Shell) throws -> PhysicalDevice {
        guard let team, !team.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PhysicalDeviceError.noTeam
        }
        let listing = try devicectl(["list", "devices"], command: PhysicalDevice.command, shell: shell)
        var device = try PhysicalDevice.parse(listDevicesJSON: listing, udid: udid)
        guard device.pairingState == "paired" else {
            throw PhysicalDeviceError.notPaired(udid: udid, state: device.pairingState)
        }
        if device.connectionState != "connected" {
            // A device paired over the network lists as `disconnected` until a call to it opens its tunnel: measured on an
            // iPad on Wi-Fi, one `device info lockState` turned it `connected` (SimWalk#116). So one such call, then the
            // judgement is made on a fresh listing; a call that fails leaves the device as it was, refused below.
            _ = try? devicectl(["device", "info", "lockState", "--device", udid], command: "devicectl device info lockState", shell: shell)
            device = try PhysicalDevice.parse(listDevicesJSON: devicectl(["list", "devices"], command: PhysicalDevice.command, shell: shell), udid: udid)
        }
        guard device.connectionState == "connected" else {
            throw PhysicalDeviceError.notConnected(udid: udid, state: device.connectionState)
        }
        guard let report = device.developerModeReport, let enabled = device.developerModeEnabled else {
            throw PhysicalDeviceError.unreadable(command: PhysicalDevice.command, reason: "properties.state.developerModeStatus is missing for \(udid)")
        }
        guard enabled else {
            throw PhysicalDeviceError.developerModeOff(udid: udid, reported: report)
        }
        guard try !passcodeRequired(udid: udid, shell: shell) else { throw PhysicalDeviceError.locked(udid: udid) }
        return device
    }

    /// Whether the phone is locked, as `devicectl device info lockState` reports `passcodeRequired`; throws when the read fails or lacks it.
    ///
    /// One read, shared by the prerequisite check and by a live session's refusal, which names a locked phone (SimWalk#116).
    public static func passcodeRequired(udid: String, shell: Shell) throws -> Bool {
        let lockCommand = "devicectl device info lockState"
        let lock = try devicectl(["device", "info", "lockState", "--device", udid], command: lockCommand, shell: shell)
        guard let root = try? JSONSerialization.jsonObject(with: lock) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let passcodeRequired = result["passcodeRequired"] as? Bool
        else {
            throw PhysicalDeviceError.unreadable(command: lockCommand, reason: "result.passcodeRequired is missing")
        }
        return passcodeRequired
    }

    /// Installs the `.app` at `appPath` on the phone with `xcrun devicectl device install app`, replacing a copy already there; a failure carries devicectl's own error.
    public static func install(appAt appPath: String, udid: String, shell: Shell) throws {
        let result: Shell.Result
        do {
            result = try shell.run("/usr/bin/xcrun", ["devicectl", "device", "install", "app", "--device", udid, appPath])
        } catch {
            throw PhysicalDeviceError.installFailed(path: appPath, udid: udid, reason: "could not run: \(error)")
        }
        guard result.succeeded else {
            throw PhysicalDeviceError.installFailed(path: appPath, udid: udid, reason: result.failureLine)
        }
    }

    /// The physical device `udid` as `devicectl list devices` reports it.
    ///
    /// A read that changes nothing, which `walk --device` makes to tell a phone from a simulator. Throws `PhysicalDeviceError.notFound` naming the physical UDIDs present when it is none.
    public static func listed(udid: String, shell: Shell) throws -> PhysicalDevice {
        try PhysicalDevice.parse(listDevicesJSON: devicectl(["list", "devices"], command: PhysicalDevice.command, shell: shell), udid: udid)
    }

    /// Runs `xcrun devicectl <arguments>` with its JSON on stdout and returns that JSON.
    static func devicectl(_ arguments: [String], command: String, shell: Shell) throws -> Data {
        let result: Shell.Result
        do {
            result = try shell.run("/usr/bin/xcrun", ["devicectl"] + arguments + ["--json-output", "-", "--quiet"])
        } catch {
            throw PhysicalDeviceError.unreadable(command: command, reason: "could not run: \(error)")
        }
        guard result.succeeded else {
            throw PhysicalDeviceError.unreadable(command: command, reason: result.failureLine)
        }
        return Data(result.standardOutput.utf8)
    }
}
