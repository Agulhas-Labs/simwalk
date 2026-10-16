//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Why `device walk` declined before touching the device.
enum DeviceWalkRefusal: Error, CustomStringConvertible, UsageFailureClassifiable {
    /// The walkbook asks for something only `simctl` can do; one line per offender.
    case unsupported([String])
    /// The runner failed and no bundle of this walk came back; carries both reasons.
    case noBundleAfterRunnerFailure(runner: String, fetch: String)
    /// `underlying` ended the walk after the first appearance read; `handback` says what became of the phone's appearance.
    case failed(String, usageFailureKind: UsageFailureKind, handback: [String])
    /// `--app` names an `.app` that cannot be walked: unreadable, or not the walkbook's app.
    case unusableApp(String)
    /// The `.app` changed between the Mac-side hash and the install; the phone holds an install whose build is not the one checked.
    case appChangedBeforeInstall(path: String, checked: String, installed: String)
    /// The bundle copied back is not this walk's; it was refused, not written.
    case bundleNotThisWalks(problems: [String])
    /// `setup.increaseContrast` was set with `devicectl` and the appearance read back still says it is off: nothing was run on the phone after.
    case contrastNotSet(found: Bool)
    /// `walk` was given a flag only a device walk takes, for a simulator.
    case deviceOnly(flag: String)
    /// `walk --dry-run` on a physical device, which has no route probe.
    case dryRunOnDevice
    /// `walk --verbose` on a physical device, whose answer is `device walk`'s and writes no result file for it to shape.
    case verboseOnDevice
    /// `--device` is no simulator `simctl` lists and no physical device `devicectl` lists, though `devicectl` lists others.
    case unknownDevice(requested: String, simulators: [String], physical: [String])

    var description: String {
        switch self {
        case let .unsupported(lines):
            (["the walkbook asks for what a device target cannot do (SimWalk#116):"] + lines.map { "  - \($0)" }).joined(separator: "\n")
        case let .noBundleAfterRunnerFailure(runner, fetch):
            "the runner failed and no bundle of this walk came back.\nrunner failure: \(runner)\nbundle: \(fetch)"
        case let .unusableApp(reason):
            "\(reason) — nothing was run"
        case let .appChangedBeforeInstall(path, checked, installed):
            "\(path) changed after it was checked: hashed \(AppBuildIdentity.printed(checked)) before the lease, \(AppBuildIdentity.printed(installed)) after the install — the phone now holds an install whose build is not the one checked, and nothing was walked"
        case let .bundleNotThisWalks(problems):
            (["the bundle copied back from the phone is not this walk's, and was refused and not written:"] + problems.map { "  - \($0)" }).joined(separator: "\n")
        case let .failed(underlying, _, handback):
            ([underlying] + handback).joined(separator: "\n")
        case let .contrastNotSet(found):
            "setup.increaseContrast: devicectl set Increase Contrast on, but the appearance read back says it is off (found \(found ? "on" : "off")) — refused before the runner started, with nothing walked"
        case let .deviceOnly(flag):
            "\(flag) is the device walk's: it names the signing team or the runner a physical iPhone or iPad is built under, and this walk is on a simulator — drop it, or pass --device <physical udid>"
        case .dryRunOnDevice:
            "--dry-run follows routes against a simulator and is not available on a physical device — drop it, or walk a simulator"
        case .verboseOnDevice:
            "--verbose shapes a simulator walk's result file, and a device walk writes none — drop it, or walk a simulator"
        case let .unknownDevice(requested, simulators, physical):
            "no simulator or physical device '\(requested)' — simulators: \(simulators.prefix(8).joined(separator: ", "))\(simulators.count > 8 ? ", …" : ""); physical devices present: \(physical.joined(separator: ", "))"
        }
    }

    /// The caller's walkbook is what is wrong for an unsupported feature; a wrapped failure keeps its own kind.
    var usageFailureKind: UsageFailureKind {
        switch self {
        case .unsupported, .unusableApp, .deviceOnly, .dryRunOnDevice, .verboseOnDevice, .unknownDevice: .inputRefused
        case .noBundleAfterRunnerFailure, .appChangedBeforeInstall, .bundleNotThisWalks: .runnerFailed
        // The runner never started: a setup step did not take, as a simulator's `DeviceSetupError` is classed.
        case .contrastNotSet: .setupFailed
        case let .failed(_, kind, _): kind
        }
    }
}
