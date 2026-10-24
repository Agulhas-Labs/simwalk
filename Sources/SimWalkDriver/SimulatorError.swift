//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why a walk could not get a device to run on.
public enum SimulatorError: Error, Equatable, CustomStringConvertible {
    case noDevices
    case noSuchDevice(requested: String, available: [String])
    case unreadableDeviceList
    case simctlFailed(command: String, reason: String)
    case appNotInstalled(bundleID: String, udid: String)
    /// The app declares iPhone only and the device is an iPad, where it would run scaled in compatibility mode and its frames could not be trusted (SimWalk#166).
    case iPhoneOnlyAppOnIPad(DeviceFamilyCheck.Refusal)
    /// The device is not booted, and the command reads a device as it stands — `simwalk inspect` never boots one, since a fresh boot has no screen anybody left an app on.
    case notBooted(name: String, udid: String)
    /// No `--device` was given and nothing is booted, so `Simulator.resolve` never chose a device the caller asked for — naming the one it picked anyway (`devices[0]`) would blame a choice nobody made.
    case noSimulatorBooted

    public var description: String {
        switch self {
        case .noDevices:
            "no available simulators — install a runtime in Xcode, or check `xcrun simctl list devices available`"
        case let .noSuchDevice(requested, available):
            "no simulator named '\(requested)' — available: \(available.prefix(8).joined(separator: ", "))\(available.count > 8 ? ", …" : "")"
        case .unreadableDeviceList:
            "cannot read `simctl list devices --json` — the format is not what this build expects"
        case let .simctlFailed(command, reason):
            "simctl \(command) failed: \(reason)"
        case let .appNotInstalled(bundleID, udid):
            "\(bundleID) is not installed on \(udid) — install it first, or pass --app-path to have the walk install it; walking an app that is not there would report every screen unreachable and blame the walkbook"
        case let .iPhoneOnlyAppOnIPad(refusal):
            refusal.description
        case let .notBooted(name, udid):
            "\(name) (\(udid)) is not booted — inspect reads a device as it stands and never boots one; boot it and bring the app to the screen you want (xcrun simctl boot \(udid)), or name a booted device with --device"
        case .noSimulatorBooted:
            "no simulator is booted — boot one (`xcrun simctl boot <udid>`) and inspect again"
        }
    }
}

extension SimulatorError: UsageFailureClassifiable {
    /// `noSuchDevice`, `appNotInstalled`, `iPhoneOnlyAppOnIPad` and `notBooted` name a specific value a caller gave — `--device`, a bundle ID — that does not match reality, which is a bad argument.
    ///
    /// The other three are `simctl`, or the machine it runs on, not answering the way the walk needs regardless of what was asked: no runtime installed at all, its device list unreadable, or the command itself failing — none of which any argument could have prevented.
    public var usageFailureKind: UsageFailureKind {
        switch self {
        case .noSuchDevice, .appNotInstalled, .iPhoneOnlyAppOnIPad, .notBooted, .noSimulatorBooted: .inputRefused
        case .noDevices, .unreadableDeviceList, .simctlFailed: .runnerFailed
        }
    }
}
