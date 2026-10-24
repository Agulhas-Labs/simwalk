//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
import SimWalkCore
import SimWalkDriver

extension WalkCommand {
    /// Where a walk runs: a simulator, which is ``performWalk(shell:pause:now:nonce:runner:logFileURL:builds:leases:telemetry:note:)``, or a physical iPhone or iPad, which is ``DeviceWalk`` (SimWalk#116).
    enum Target {
        case simulator
        case device(DeviceWalk)
    }

    /// Decides which, **before the simulator path touches anything**, and refuses what the target cannot take.
    ///
    /// What counts as a physical device is ``PhysicalDeviceRoute``'s, which `session start` reads too.
    ///
    /// `--team` and `--runner-bundle-id` are the device path's and are refused on a simulator walk; `--dry-run` and `--verbose` are the simulator path's and are refused on a device.
    ///
    /// `firstLaunch` is the command's one preflight, asked before the route check's `simctl list` (SimWalk#136).
    func target(shell: Shell, leases: LeaseStore, firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check()) throws -> Target {
        let device = try physicalWalk(shell: shell, leases: leases, firstLaunch: firstLaunch)
        guard let device else {
            for (flag, value) in [("--team", team), ("--runner-bundle-id", runnerBundleId)] where value != nil {
                throw DeviceWalkRefusal.deviceOnly(flag: flag)
            }
            return .simulator
        }
        guard !dryRun else {
            throw DeviceWalkRefusal.dryRunOnDevice
        }
        guard !verbose else {
            throw DeviceWalkRefusal.verboseOnDevice
        }
        guard !stock else {
            throw DeviceWalkRefusal.stockOnDevice
        }
        guard parallel == nil else {
            throw DeviceWalkRefusal.parallelOnDevice
        }
        return .device(device)
    }

    private func physicalWalk(shell: Shell, leases: LeaseStore, firstLaunch: XcodeFirstLaunch.Check) throws -> DeviceWalk? {
        try PhysicalDeviceRoute.resolve(device: device, lease: lease, shell: shell, leases: leases, firstLaunch: firstLaunch).map { deviceWalk(udid: $0.udid) }
    }

    private func deviceWalk(udid: String?) -> DeviceWalk {
        DeviceWalk(walkbook: walkbook, requestedUDID: udid, lease: lease, team: team, runnerBundleID: runnerBundleId, app: appPath, output: output, screens: screens, settle: settle, motion: motion, appleAudit: appleAudit)
    }

    /// A walk of whichever target `--device` or `--lease` names, answered as `walk` answers: the simulator's served answer, or the device walk's.
    ///
    /// The device path takes none of the simulator path's pause or nonce, and its progress file holds only what `begin` and the end write plus the device it resolved (marked `physical`); its waits are the runner's own.
    ///
    /// `firstLaunch` is the walk's one preflight, made before its first `simctl` call on either path (SimWalk#136). `logFileURL` is the usage log a simulator walk writes to, resolved at the face as `performWalk`'s is.
    func walked(
        shell: Shell = Shell(),
        runner resolveRunner: (() throws -> RunnerSource)? = nil,
        logFileURL: URL = UsageLog.standard().fileURL,
        builds: RunnerBuilds,
        leases: LeaseStore,
        now: @escaping () -> Date = { Date() },
        telemetry: WalkTelemetry? = nil,
        firstLaunch: XcodeFirstLaunch.Check = XcodeFirstLaunch.Check(),
        junit: JUnitOutput? = nil,
        animationsLibrary: AnimationsLibrary? = nil,
        interruption: Cancellation? = nil,
        provisioning: (Shell) -> SlimWalkProvisioning = { SlimWalkProvisioning(shell: $0) },
        note: (String) -> Void = { _ in }
    ) throws -> Answer {
        let target = try target(shell: shell, leases: leases, firstLaunch: firstLaunch)
        guard case let .device(walk) = target else {
            return try performWalk(shell: shell, now: now, runner: resolveRunner, logFileURL: logFileURL, builds: builds, leases: leases, telemetry: telemetry, firstLaunch: firstLaunch, provisioning: provisioning, animationsLibrary: animationsLibrary, interruption: interruption, note: note).servedAnswer(junit: junit)
        }
        var reporting = walk
        reporting.junit = junit
        return try reporting.answer(shell: shell, builds: builds, resolveRunner: resolveRunner, leases: leases, holderPID: ProcessInfo.processInfo.processIdentifier, now: now(), telemetry: telemetry)
    }
}
