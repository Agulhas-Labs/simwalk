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
    ///
    /// `suffixedOutput` is the output path the walk completed with `.simwalk`, which the description marks "(suffix added)" where `underlying` names it (SimWalk#122).
    case failed(String, suffixedOutput: String?, usageFailureKind: UsageFailureKind, handback: [String])
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
    /// `walk --stock` on a physical device, whose launchd services SimWalk never switches off.
    case stockOnDevice
    /// `walk --parallel` on a physical device, which walks one device at a time.
    case parallelOnDevice
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
        case let .failed(underlying, suffixedOutput, _, handback):
            ([Self.marking(suffixedOutput, in: underlying)] + handback).joined(separator: "\n")
        case let .contrastNotSet(found):
            "setup.increaseContrast: devicectl set Increase Contrast on, but the appearance read back says it is off (found \(found ? "on" : "off")) — refused before the runner started, with nothing walked"
        case let .deviceOnly(flag):
            "\(flag) is the device walk's: it names the signing team or the runner a physical iPhone or iPad is built under, and this walk is on a simulator — drop it, or pass --device <physical udid>"
        case .dryRunOnDevice:
            "--dry-run follows routes against a simulator and is not available on a physical device — drop it, or walk a simulator"
        case .verboseOnDevice:
            "--verbose shapes a simulator walk's result file, and a device walk writes none — drop it, or walk a simulator"
        case .parallelOnDevice:
            "--parallel shards a walk across simulators, and a physical device walks alone — drop it, or walk a simulator"
        case .stockOnDevice:
            "--stock boots a simulator SimWalk created with every service on, and a physical device has none switched off — drop it, or walk a simulator"
        case let .unknownDevice(requested, simulators, physical):
            "no simulator or physical device '\(requested)' — simulators: \(simulators.prefix(8).joined(separator: ", "))\(simulators.count > 8 ? ", …" : ""); physical devices present: \(physical.joined(separator: ", "))"
        }
    }

    /// The caller's walkbook is what is wrong for an unsupported feature; a wrapped failure keeps its own kind.
    var usageFailureKind: UsageFailureKind {
        switch self {
        case .unsupported, .unusableApp, .deviceOnly, .dryRunOnDevice, .verboseOnDevice, .stockOnDevice, .parallelOnDevice, .unknownDevice: .inputRefused
        case .noBundleAfterRunnerFailure, .appChangedBeforeInstall, .bundleNotThisWalks: .runnerFailed
        // The runner never started: a setup step did not take, as a simulator's `DeviceSetupError` is classed.
        case .contrastNotSet: .setupFailed
        case let .failed(_, _, kind, _): kind
        }
    }

    /// Whether `rest`, the text right after a match of the path, ends it.
    ///
    /// It does at the end of the text, at whitespace or closing punctuation, or at a full stop that is itself followed by the end or whitespace. A longer name that starts with the path (`out.simwalk-2`, `out.simwalk.tmp`) or a file inside it does not.
    private static func endsThePath(_ rest: Substring) -> Bool {
        guard let next = rest.first else { return true }
        if next.isWhitespace || ",;:)]'\"".contains(next) {
            return true
        }
        guard next == "." else { return false }
        return rest.dropFirst().first?.isWhitespace ?? true
    }

    /// `text` with " (suffix added)" after each place it names `path` itself; a longer path that merely starts with it (a file inside the bundle) is not the output path, so it is left as written.
    private static func marking(_ path: String?, in text: String) -> String {
        guard let path, !path.isEmpty else { return text }
        var marked = ""
        var rest = text[...]
        while let found = rest.firstRange(of: path) {
            marked += rest[..<found.upperBound]
            rest = rest[found.upperBound...]
            if endsThePath(rest) {
                marked += " (suffix added)"
            }
        }
        return marked + rest
    }
}
